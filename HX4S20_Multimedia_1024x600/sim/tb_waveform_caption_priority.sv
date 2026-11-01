`timescale 1ns/1ps
module wave_caption_fixture #(parameter FRONT=0)(
 input clk,rst,tick,valid,cover_fixture,menu,rebuild,spec,audio_valid,audio_reset,
 input [3:0] state,input [4:0] fade,input manual,input [5:0] phase,
 input signed [23:0] sample,input [10:0] x,y,input [23:0] rgb,
 output ov,os,ol,output [23:0] color
);
 wire mv,ms,ml,wl,wh;wire [23:0] mrgb,paper,ink,wave;
 media_osd #(.ENABLE_COVER(1),.SUBTITLE_PALETTE(1),.DEFER_WAVEFORM(FRONT)) osd(
  .clk(clk),.rst(rst),.frame_tick(tick),.cover_active(cover_fixture),.state_code(state),
  .fade_alpha(fade),.manual_transition(manual),.manual_phase(phase),
  .menu_active(menu),.menu_item(3'd0),.rebuild_busy(rebuild),.rebuild_progress(3'd0),.rebuild_total(3'd4),
  .brightness_level(3'd2),.contrast_level(3'd2),.zoom_level(3'd2),.scale_override(2'd0),
  .spectrum_enable(spec),.scene(3'd1),.audio_valid(audio_valid),.audio_sample(sample),.audio_stream_reset(audio_reset),
  .valid(valid),.x(x),.y(y),.rgb(rgb),.out_valid(mv),.out_sof(ms),.out_last(ml),.out_rgb(mrgb),
  .subtitle_paper_rgb(paper),.subtitle_ink_rgb(ink),.waveform_line(wl),.waveform_halo(wh),.waveform_rgb(wave));
 subtitle_overlay #(.TRANSITION_PALETTE(1),.WAVEFORM_ON_TOP(FRONT)) sub(
  .wr_clk(clk),.wr_en(1'b0),.wr_addr(9'd0),.wr_data(8'd0),
  .font_wr_en(1'b0),.font_wr_addr(10'd0),.font_wr_data(18'd0),.font_ready(1'b1),.font_quiet_request(1'b0),
  .clk(clk),.rst(rst),.frame_tick(tick),.enable(1'b1),.show_picture(!cover_fixture && state!=14),
  .intro_pause(1'b1),.intro_restart(1'b0),.image_index(2'd0),
  .len0(8'd128),.len1(8'd128),.len2(8'd128),.len3(8'd128),
  .valid(mv),.sof(ms),.last(ml),.rgb(mrgb),.subtitle_paper_rgb(paper),.subtitle_ink_rgb(ink),
  .waveform_line(wl),.waveform_halo(wh),.waveform_rgb(wave),
  .out_valid(ov),.out_sof(os),.out_last(ol),.out_rgb(color));
 integer j;reg [10:0] hx[0:5],hy[0:5];
 // Sparse raster fixture, identical to the established palette regression:
 // only the subtitle coordinate counter is positioned; real RAM/pixels run.
 always @(posedge clk)begin
  for(j=5;j>0;j=j-1)begin hx[j]=hx[j-1];hy[j]=hy[j-1];end
  hx[0]=x;hy[0]=y;
  #1;sub.x=hx[5];sub.y=hy[5];
 end
 task init_glyphs;
  integer i;
  begin
   for(i=0;i<512;i=i+1)sub.chars[i]=8'h80;
   for(i=0;i<1024;i=i+1)sub.font[i]=18'h0ffff;
  end
 endtask
endmodule

module tb_waveform_caption_priority;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,tick=0,valid=1,cover_fixture=0,menu=0,rebuild=0,spec=1,av=0,ar=0,manual=0;
 reg [3:0] state=6;reg [4:0] fade=16;reg [5:0] phase=63;
 reg signed [23:0] sample=0;
 reg [10:0] x=603,y=552;reg [23:0] rgb=24'h204060;
 wire v,s,l,bv,bs,bl,lv,ls,ll;wire [23:0] color,plain_color,legacy_color;
 wave_caption_fixture #(.FRONT(1)) front(
  .clk(clk),.rst(rst),.tick(tick),.valid(valid),.cover_fixture(cover_fixture),.menu(menu),.rebuild(rebuild),.spec(spec),
  .audio_valid(av),.audio_reset(ar),.state(state),.fade(fade),.manual(manual),.phase(phase),.sample(sample),
  .x(x),.y(y),.rgb(rgb),.ov(v),.os(s),.ol(l),.color(color));
 wave_caption_fixture #(.FRONT(0)) plain(
  .clk(clk),.rst(rst),.tick(tick),.valid(valid),.cover_fixture(cover_fixture),.menu(menu),.rebuild(rebuild),.spec(1'b0),
  .audio_valid(av),.audio_reset(ar),.state(state),.fade(fade),.manual(manual),.phase(phase),.sample(sample),
  .x(x),.y(y),.rgb(rgb),.ov(bv),.os(bs),.ol(bl),.color(plain_color));
 wave_caption_fixture #(.FRONT(0)) legacy(
  .clk(clk),.rst(rst),.tick(tick),.valid(valid),.cover_fixture(cover_fixture),.menu(menu),.rebuild(rebuild),.spec(spec),
  .audio_valid(av),.audio_reset(ar),.state(state),.fade(fade),.manual(manual),.phase(phase),.sample(sample),
  .x(x),.y(y),.rgb(rgb),.ov(lv),.os(ls),.ol(ll),.color(legacy_color));
 integer checks=0,n,q;reg burst=0;
 reg [10:0] hx[0:8],hy[0:8];reg hv[0:8],hs[0:8],hl[0:8];
 reg [23:0] expected;
 function [23:0] wave_colour;
  input integer px;integer t,r,g,b;
  begin t=(px/32)%32;r=88+2*t;g=184+t;b=156-t;wave_colour={r[7:0],g[7:0],b[7:0]};end
 endfunction
 function [23:0] half_mix;
  input [23:0] a,b;integer r,g,bb;
  begin r=a[23:16]/2+b[23:16]/2;g=a[15:8]/2+b[15:8]/2;bb=a[7:0]/2+b[7:0]/2;half_mix={r[7:0],g[7:0],bb[7:0]};end
 endfunction
 task settle;begin repeat(16)@(negedge clk);end endtask
 task publish;begin settle;tick=1;@(negedge clk);tick=0;settle;end endtask
 task capture(input [23:0] pcm);
  begin sample=pcm;av=1;repeat(512)@(negedge clk);av=0;publish;end
 endtask
 task pixel(input integer py,input integer mode);
  begin
   x=603;y=py;settle;
   expected=mode==1?wave_colour(603):mode==2?half_mix(plain_color,wave_colour(603)):plain_color;
   checks=checks+1;
   if(!v || color!==expected)$fatal(1,"wave/caption pixel y%0d mode%0d got%h expected%h plain%h",py,mode,color,expected,plain_color);
  end
 endtask
 task same_as_legacy;
  begin settle;checks=checks+1;
   if({v,s,l,color}!=={lv,ls,ll,legacy_color})$fatal(1,"existing upper layer changed menu%b cover_fixture%b rebuild%b state%0d fade%0d",menu,cover_fixture,rebuild,state,fade);
   if(front.wl || front.wh)$fatal(1,"upper layer leaked deferred wave mask");
  end
 endtask
 always @(posedge clk)begin
  for(q=8;q>0;q=q-1)begin hx[q]=hx[q-1];hy[q]=hy[q-1];hv[q]=hv[q-1];hs[q]=hs[q-1];hl[q]=hl[q-1];end
  hx[0]=x;hy[0]=y;hv[0]=valid;hs[0]=valid && x==0 && y==0;hl[0]=valid && x==1023;
  #2;
  if(burst)begin
   checks=checks+1;
   if({v,s,l}!=={hv[8],hs[8],hl[8]})$fatal(1,"combined RGB metadata no longer nine cycles");
   if(v)begin
    expected=plain_color;
    if(hy[8]>=551 && hy[8]<=553)expected=wave_colour(hx[8]);
    else if(hy[8]>=549 && hy[8]<=555)expected=half_mix(plain_color,wave_colour(hx[8]));
    if(color!==expected)$fatal(1,"mask/RGB alignment xy%0d,%0d got%h expected%h",hx[8],hy[8],color,expected);
   end
  end
 end
 initial begin
  repeat(5)@(negedge clk);front.init_glyphs;plain.init_glyphs;legacy.init_glyphs;rst=0;publish;
  capture(24'hc00000); // -20 pixels: trace crosses actual caption lettering.
  pixel(572,1);
  if(plain_color!==24'h101820 || legacy_color!==24'h101820)$fatal(1,"fixture missed opaque text pixels");
  pixel(575,2);pixel(576,0);
  capture(24'h000000); // Zero amplitude: trace crosses caption paper at y552.
  pixel(552,1);pixel(555,2);pixel(556,0);
  if(plain_color!==24'hc8d0d8)$fatal(1,"original75-percent paper opacity changed: %h",plain_color);
  spec=0;publish;pixel(552,0);
  spec=1;menu=1;publish;same_as_legacy;
  menu=0;rebuild=1;publish;same_as_legacy;
  rebuild=0;cover_fixture=1;publish;same_as_legacy;
  cover_fixture=0;state=14;publish;same_as_legacy;
  state=6;publish;fade=0;same_as_legacy;
  fade=8;same_as_legacy;manual=1;phase=20;same_as_legacy;
  manual=0;phase=63;fade=16;publish;
  for(n=0;n<64;n=n+1)begin
   @(negedge clk);x=603;
   case(n%4)0:y=552;1:y=555;2:y=556;default:y=560;endcase
   if(n%16==0)begin x=0;y=0;end
   if(n%16==1)x=1023;
   valid=(n%5)!=3;rgb={8'(32+n),8'(64+2*n),8'(96+3*n)};
   if(n>=12)burst=1;
  end
  @(negedge clk);burst=0;valid=0;settle;
  $display("PASS waveform caption priority: %0d checks, real512-sample PCM, original75-percent paper, core over paper/letters,50-percent halo, upper menu/cover_fixture/error/rebuild/curtain, nine-cycle RGB/valid/SOF/EOL bubbles",checks);
  $finish;
 end
 initial begin #1000000;$fatal(1,"waveform caption priority timeout");end
endmodule
