`timescale 1ns/1ps
// Keep captions inside the same curtain/fade without adding pixel latency.
// Geometry is checked against the standalone, non-precomputed transition;
// channel references use integer arithmetic, not DUT palette signals.
module tb_subtitle_transition_palette;
 reg clk=0; always #5 clk=~clk;
 reg rst=1,frame_tick=0;
 reg valid=0; reg [10:0] x=0,y=0; reg [23:0] rgb=24'h204060;
 reg [4:0] fade=16; reg manual=0; reg [5:0] phase=63;
 reg ready=1,quiet=0; reg [1:0] image=0;
 reg wr_en=0,font_wr_en=0;reg [8:0] wr_addr=0;
 reg [9:0] font_wr_addr=0;
 wire ov,os,ol;wire [23:0] orgb,paper,ink;
 media_osd #(.SUBTITLE_PALETTE(1)) osd(
  .clk(clk),.rst(rst),.frame_tick(frame_tick),.cover_active(1'b0),
  .state_code(4'd6),.fade_alpha(fade),.manual_transition(manual),.manual_phase(phase),
  .menu_active(1'b0),.menu_item(3'd0),.rebuild_busy(1'b0),.rebuild_progress(3'd0),.rebuild_total(3'd4),
  .brightness_level(3'd2),.contrast_level(3'd2),.zoom_level(3'd0),.scale_override(2'd0),
  .spectrum_enable(1'b0),.scene(3'd1),.audio_valid(1'b0),.audio_sample(24'sd0),
  .audio_stream_reset(1'b0),.valid(valid),.x(x),.y(y),.rgb(rgb),
  .out_valid(ov),.out_sof(os),.out_last(ol),.out_rgb(orgb),
  .subtitle_paper_rgb(paper),.subtitle_ink_rgb(ink));
 wire cv,cs,cl,cache_idle,quiet_ack;
 wire [23:0] crgb;
 subtitle_overlay #(.TRANSITION_PALETTE(1)) sub(
  .wr_clk(clk),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(8'h80),
  .font_wr_en(font_wr_en),.font_wr_addr(font_wr_addr),.font_wr_data(18'h0ffff),
  .font_ready(ready),.font_quiet_request(quiet),
  .clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(1'b1),.show_picture(1'b1),
  .intro_pause(1'b1),.intro_restart(1'b0),.image_index(image),
  .len0(8'd128),.len1(8'd128),.len2(8'd128),.len3(8'd128),
  .valid(ov),.sof(os),.last(ol),.rgb(orgb),
  .subtitle_paper_rgb(paper),.subtitle_ink_rgb(ink),
  .font_cache_idle(cache_idle),.font_quiet_ack(quiet_ack),
  .out_valid(cv),.out_sof(cs),.out_last(cl),.out_rgb(crgb));
 wire [23:0] ref_rgb,ref_bg;
 wire [4:0] ref_alpha;
 gallery_transition #(.PRECOMPUTED_GAIN(0)) geometry(
  .rgb(rgb),.x(x),.y(y),.fade_alpha(fade),.manual_active(manual),.manual_phase(phase),
  .valid(valid),.curve_gain_in(8'd0),.out_rgb(ref_rgb),.out_alpha(ref_alpha),.out_background(ref_bg));

 function [7:0] blend;
  input [7:0] fg,bg;input integer a;
  integer weighted;
  begin weighted=fg*a+bg*(16-a);blend=weighted/16;end
 endfunction
 function [23:0] palette_reference;
  input [23:0] foreground,background;input integer a;
  begin palette_reference={blend(foreground[23:16],background[23:16],a),
   blend(foreground[15:8],background[15:8],a),blend(foreground[7:0],background[7:0],a)};end
 endfunction
 function [23:0] paper_reference;
  input [23:0] under,white;
  integer r,g,b;
  begin
   // Ceiling 3/4 of premixed paper plus floor 1/4 of premixed photograph.
   r=(3*white[23:16]+3)/4+under[23:16]/4;
   g=(3*white[15:8]+3)/4+under[15:8]/4;
   b=(3*white[7:0]+3)/4+under[7:0]/4;
   paper_reference={r[7:0],g[7:0],b[7:0]};
  end
 endfunction
 reg checking=0,caption_expected=1;
 reg [23:0] gr[0:8],gp[0:8],gi[0:8],gf[0:8];
 reg gv[0:8],gs[0:8],gl[0:8];
 integer gx[0:8],gy[0:8],ga[0:8];
 reg gm[0:8],gcaption[0:8];
 integer q;
 integer pixels=0,osd_pixels=0,opaque=0,open_pixels=0,soft_pixels=0;
 integer paper_pixels=0,text_pixels=0,outside_pixels=0,bubbles=0,opening_text=0,not_ready_pixels=0;
 reg [23:0] expected_pixel;
 always @(posedge clk)begin
  if(rst)begin
   for(q=0;q<9;q=q+1)begin
    gr[q]=0;gp[q]=0;gi[q]=0;gf[q]=0;gv[q]=0;gs[q]=0;gl[q]=0;
    gx[q]=0;gy[q]=0;ga[q]=0;gm[q]=0;gcaption[q]=0;
   end
  end else begin
   for(q=8;q>0;q=q-1)begin
    gr[q]=gr[q-1];gp[q]=gp[q-1];gi[q]=gi[q-1];gf[q]=gf[q-1];
    gv[q]=gv[q-1];gs[q]=gs[q-1];gl[q]=gl[q-1];
    gx[q]=gx[q-1];gy[q]=gy[q-1];ga[q]=ga[q-1];gm[q]=gm[q-1];gcaption[q]=gcaption[q-1];
   end
   gr[0]=ref_rgb;gp[0]=palette_reference(24'hffffff,ref_bg,ref_alpha);
   gi[0]=palette_reference(24'h101820,ref_bg,ref_alpha);
   gf[0]=ref_bg;gv[0]=valid;gs[0]=valid && x==0 && y==0;gl[0]=valid && x==1023;
   gx[0]=x;gy[0]=y;ga[0]=ref_alpha;gm[0]=manual;gcaption[0]=caption_expected;
   #1;
   // Drive only the coordinate counter, as a sparse raster fixture. RAM,
   // character decoding, palette pipelines and all RGB/control are real.
   sub.x=gx[5];sub.y=gy[5];
   if(checking)begin
    if({ov,os,ol}!=={gv[5],gs[5],gl[5]})$fatal(1,"OSD metadata not six clocks");
    if({cv,cs,cl}!=={gv[8],gs[8],gl[8]})$fatal(1,"Combined metadata not nine clocks");
    if(gv[5])begin
     osd_pixels=osd_pixels+1;
     if(orgb!==gr[5])$fatal(1,"OSD base transition RGB xy%0d,%0d got%h want%h",gx[5],gy[5],orgb,gr[5]);
     if(paper!==gp[5] || ink!==gi[5])$fatal(1,"Palette misaligned xy%0d,%0d a%0d paper%h/%h ink%h/%h",gx[5],gy[5],ga[5],paper,gp[5],ink,gi[5]);
    end
    if(!gv[8])bubbles=bubbles+1;
    else begin
     pixels=pixels+1;expected_pixel=gr[8];
     if(gcaption[8] && gx[8]>=6 && gx[8]<1018 && gy[8]>=552 && gy[8]<594)begin
      if(gy[8]>=560 && gy[8]<592)begin
       expected_pixel=gi[8];text_pixels=text_pixels+1;
       if(gm[8] && ga[8]>0 && expected_pixel!=gr[8])opening_text=opening_text+1;
      end else begin expected_pixel=paper_reference(gr[8],gp[8]);paper_pixels=paper_pixels+1;end
      if(ga[8]==0)begin
       opaque=opaque+1;
       if(expected_pixel!==gf[8])$fatal(1,"Opaque caption reference must equal cloth");
      end else if(ga[8]==16)open_pixels=open_pixels+1;
      else soft_pixels=soft_pixels+1;
     end else outside_pixels=outside_pixels+1;
     if(!gcaption[8])not_ready_pixels=not_ready_pixels+1;
     if(crgb!==expected_pixel)$fatal(1,"Final subtitle transition RGB xy%0d,%0d a%0d caption%b got%h want%h",gx[8],gy[8],ga[8],gcaption[8],crgb,expected_pixel);
    end
   end
  end
 end
 task tick;begin @(negedge clk);end endtask
 task drain;begin valid=0;repeat(12)tick;end endtask
 task frame;begin drain;frame_tick=1;tick;frame_tick=0;repeat(10)tick;end endtask
 task set_transition(input is_manual,input integer p,input integer a);
 begin drain;manual=is_manual;phase=p;fade=a;repeat(12)tick;end endtask
 task probe(input integer px,py,input is_valid);
 begin
  x=px;y=py;valid=is_valid;
  rgb=24'h204060 ^ ((px*37+py*131)&24'hffffff);
  tick;
 end endtask
 integer xs[0:15],ys[0:7],phases[0:7];
 integer i,j,k,a,px;
 initial begin
  xs[0]=0;xs[1]=2;xs[2]=5;xs[3]=6;xs[4]=7;xs[5]=64;xs[6]=256;xs[7]=480;
  xs[8]=511;xs[9]=512;xs[10]=543;xs[11]=768;xs[12]=1017;xs[13]=1018;xs[14]=1021;xs[15]=1023;
  ys[0]=551;ys[1]=552;ys[2]=559;ys[3]=560;ys[4]=591;ys[5]=592;ys[6]=593;ys[7]=594;
  phases[0]=0;phases[1]=1;phases[2]=8;phases[3]=16;phases[4]=32;phases[5]=48;phases[6]=62;phases[7]=63;
  repeat(5)tick;rst=0;
  for(i=0;i<512;i=i+1)begin wr_en=1;wr_addr=i;tick;end wr_en=0;
  for(i=0;i<16;i=i+1)begin font_wr_en=1;font_wr_addr=i;tick;end font_wr_en=0;
  frame;frame;force sub.scroll=13'd1024;
  drain;checking=1;
  for(a=0;a<=16;a=a+1)begin
   set_transition(0,63,a);
   for(j=0;j<8;j=j+1)for(i=0;i<16;i=i+1)begin
    probe(xs[i],ys[j],1);
    if((i+j)%5==0)probe(17,575,0);
   end
   probe(0,0,1);probe(1023,599,1);drain;
  end
  set_transition(0,63,31);probe(512,560,1);probe(512,552,1);drain;
  for(k=0;k<8;k=k+1)begin
   set_transition(1,phases[k],16);
   for(j=0;j<8;j=j+1)for(px=0;px<1024;px=px+1)begin
    probe(px,ys[j],1);
    if(px%67==0)probe(17,575,0);
   end
   probe(0,0,1);probe(1023,599,1);drain;
  end
  // Simulate the next scene's quiet/cache handoff. There is deliberately no
  // transition_busy gate on show_picture: after ready, phase 8 already reveals
  // its new text in the open centre while opaque outside cloth stays intact.
  checking=0;drain;ready=0;quiet=1;image=1;frame;frame;
  if(!cache_idle || quiet_ack!==quiet)$fatal(1,"quiet/idle handshake did not drain");
  caption_expected=0;checking=1;set_transition(1,8,16);
  for(i=0;i<16;i=i+1)begin probe(xs[i],560,1);probe(xs[i],552,1);end drain;
  checking=0;ready=1;frame;frame;caption_expected=1;drain;checking=1;
  if(!sub.pic_d || !sub.ready_d || sub.index_d!=1)$fatal(1,"scene not published during opening");
  for(px=400;px<624;px=px+1)begin probe(px,560,1);probe(px,552,1);end drain;
  if(pixels<68000 || opaque<1000 || open_pixels<1000 || soft_pixels<100 ||
     text_pixels<1000 || paper_pixels<1000 || opening_text<100 || bubbles<100 || not_ready_pixels!=32)
   $fatal(1,"insufficient transition coverage p%0d opaque%0d open%0d soft%0d text%0d paper%0d opening%0d bubbles%0d notready%0d",pixels,opaque,open_pixels,soft_pixels,text_pixels,paper_pixels,opening_text,bubbles,not_ready_pixels);
  $display("PASS subtitle transition palette: %0d final pixels/%0d OSD pixels, %0d opaque/%0d open/%0d feather, %0d text/%0d paper/%0d outside, %0d opening text before completion, %0d not-ready pixels, 6+3 RGB/valid/SOF/EOL and %0d bubbles",pixels,osd_pixels,opaque,open_pixels,soft_pixels,text_pixels,paper_pixels,outside_pixels,opening_text,not_ready_pixels,bubbles);
  $finish;
 end
 initial begin #10000000;$fatal(1,"subtitle transition palette timeout");end
endmodule
