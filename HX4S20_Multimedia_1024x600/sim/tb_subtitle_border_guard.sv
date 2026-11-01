`timescale 1ns/1ps
// Final compositing must preserve the artwork border, not only its OSD stage.
module tb_subtitle_border_guard;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,wr_en=0,font_wr_en=0;
 reg [8:0] wr_addr=0;reg [7:0] wr_data=8'h80;
 reg [9:0] font_wr_addr=0;reg [15:0] font_wr_data=16'hffff;
 reg valid=0,sof=0,last=0;reg [23:0] rgb=24'h204060;
 integer xx=0,yy=0;
 wire ov,os,ol;wire [23:0] orgb;
 subtitle_overlay basic(.wr_clk(clk),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_data),
  .font_wr_en(font_wr_en),.font_wr_addr(font_wr_addr),.font_wr_data(font_wr_data),
  .font_ready(1'b1),.font_quiet_request(1'b0),.clk(clk),.rst(rst),.frame_tick(frame_tick),
  .enable(1'b1),.show_picture(1'b1),.intro_pause(1'b0),.intro_restart(1'b0),
  .image_index(2'd0),.len0(8'd128),.len1(8'd128),.len2(8'd128),.len3(8'd128),
  .valid(valid),.sof(sof),.last(last),.rgb(rgb),.out_valid(ov),.out_sof(os),.out_last(ol),.out_rgb(orgb));

 reg native_valid=0;reg [10:0] native_x=0,native_y=0;
 reg [2:0] zoom=2,scene=1;reg audio_valid=0;
 wire osd_valid,osd_sof,osd_last;wire [23:0] osd_rgb;
 media_osd osd(.clk(clk),.rst(rst),.frame_tick(frame_tick),.cover_active(1'b0),
  .state_code(4'd6),.fade_alpha(5'd16),.manual_transition(1'b0),.manual_phase(6'd63),
  .menu_active(1'b0),.menu_item(3'd0),.rebuild_busy(1'b0),.rebuild_progress(3'd0),.rebuild_total(3'd4),
  .brightness_level(3'd2),.contrast_level(3'd2),.zoom_level(zoom),.scale_override(2'd0),
  .spectrum_enable(1'b0),.scene(scene),.audio_valid(audio_valid),.audio_sample(24'sh600000),
  .audio_stream_reset(1'b0),.valid(native_valid),.x(native_x),.y(native_y),.rgb(24'h204060),
  .out_valid(osd_valid),.out_sof(osd_sof),.out_last(osd_last),.out_rgb(osd_rgb));
 wire cv,cs,cl;wire [23:0] crgb;
 subtitle_overlay combined(.wr_clk(clk),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_data),
  .font_wr_en(font_wr_en),.font_wr_addr(font_wr_addr),.font_wr_data(font_wr_data),
  .font_ready(1'b1),.font_quiet_request(1'b0),.clk(clk),.rst(rst),.frame_tick(frame_tick),
  .enable(1'b1),.show_picture(1'b1),.intro_pause(1'b0),.intro_restart(1'b0),
  .image_index(2'd0),.len0(8'd128),.len1(8'd128),.len2(8'd128),.len3(8'd128),
  .valid(osd_valid),.sof(osd_sof),.last(osd_last),.rgb(osd_rgb),
  .out_valid(cv),.out_sof(cs),.out_last(cl),.out_rgb(crgb));

 function [23:0] subtitle_reference;
  input [23:0] under;input integer px,py;input is_valid;
  reg [7:0] r,g,b;
  begin
   subtitle_reference=under;
   if(is_valid && px>=6 && px<1018 && py>=552 && py<594)begin
    if(py>=560 && py<592)subtitle_reference=24'h101820;
    else begin
     r=192+under[23:16]/4;g=192+under[15:8]/4;b=192+under[7:0]/4;
     subtitle_reference={r,g,b};
    end
   end
  end
 endfunction
 reg [23:0] br[0:2],nr[0:2];
 reg bv[0:2],bs[0:2],bl[0:2],nv[0:2],ns[0:2],nl[0:2];
 integer xp[0:5],yp[0:5];reg vp[0:5];
 integer q,basic_checks=0,chain_checks=0,border_checks=0;
 integer left_edge=2,right_edge=1021,top_edge=2,bottom_edge=597;
 reg checking=0;
 always @(posedge clk)begin
  if(rst)begin
   for(q=0;q<3;q=q+1)begin br[q]=0;nr[q]=0;bv[q]=0;bs[q]=0;bl[q]=0;nv[q]=0;ns[q]=0;nl[q]=0;end
   for(q=0;q<6;q=q+1)begin xp[q]=0;yp[q]=0;vp[q]=0;end
  end else begin
   for(q=2;q>0;q=q-1)begin
    br[q]=br[q-1];bv[q]=bv[q-1];bs[q]=bs[q-1];bl[q]=bl[q-1];
    nr[q]=nr[q-1];nv[q]=nv[q-1];ns[q]=ns[q-1];nl[q]=nl[q-1];
   end
   br[0]=subtitle_reference(rgb,xx,yy,valid);bv[0]=valid;bs[0]=sof;bl[0]=last;
   nr[0]=subtitle_reference(osd_rgb,xp[5],yp[5],osd_valid);
   nv[0]=osd_valid;ns[0]=osd_sof;nl[0]=osd_last;
   if(checking && osd_valid)begin
    if(!vp[5] || osd_sof!==(xp[5]==0 && yp[5]==0) || osd_last!==(xp[5]==1023))
     $fatal(1,"native OSD six-cycle coordinate/marker fixture misaligned");
    if(xp[5]>=left_edge && xp[5]<=right_edge && yp[5]>=top_edge && yp[5]<=bottom_edge &&
       (yp[5]<top_edge+4 || yp[5]>=bottom_edge-3 || xp[5]<left_edge+4 || xp[5]>=right_edge-3))begin
     if(osd_rgb===24'h204060)$fatal(1,"native border fixture was not coloured zoom%0d xy%0d,%0d",zoom,xp[5],yp[5]);
     if(nr[0]!==osd_rgb)$fatal(1,"subtitle reference would cover border zoom%0d xy%0d,%0d",zoom,xp[5],yp[5]);
     border_checks=border_checks+1;
    end
   end
   for(q=5;q>0;q=q-1)begin xp[q]=xp[q-1];yp[q]=yp[q-1];vp[q]=vp[q-1];end
   xp[0]=native_x;yp[0]=native_y;vp[0]=native_valid;
   #1;
   if(checking)begin
    if(ov!==bv[2] || os!==bs[2] || ol!==bl[2])$fatal(1,"standalone three-cycle metadata");
    if(bv[2])begin basic_checks=basic_checks+1;if(orgb!==br[2])$fatal(1,"viewport boundary RGB got%h expected%h",orgb,br[2]);end
    if(cv!==nv[2] || cs!==ns[2] || cl!==nl[2])$fatal(1,"OSD-subtitle three-cycle metadata");
    if(nv[2])begin chain_checks=chain_checks+1;if(crgb!==nr[2])$fatal(1,"OSD-subtitle RGB got%h expected%h zoom%0d",crgb,nr[2],zoom);end
   end
  end
 end
 task tick;begin @(negedge clk);end endtask
 task frame;begin repeat(5)tick;frame_tick=1;tick;frame_tick=0;repeat(6)tick;end endtask
 task probe(input integer px,py,input is_valid,input is_sof,input is_last);
 begin
  tick;xx=px;yy=py;basic.x=px;basic.y=py;
  valid=is_valid;sof=is_sof;last=is_last;rgb=24'h204060 ^ ((px*13+py*7)&24'hffffff);
 end endtask
 integer xs[0:7],ys[0:9],lines[0:12];
 integer i,j,z,row,col;
 initial begin
  xs[0]=0;xs[1]=2;xs[2]=5;xs[3]=6;xs[4]=1017;xs[5]=1018;xs[6]=1021;xs[7]=1023;
  ys[0]=551;ys[1]=552;ys[2]=559;ys[3]=560;ys[4]=591;ys[5]=592;ys[6]=593;ys[7]=594;ys[8]=597;ys[9]=599;
  repeat(5)tick;rst=0;
  for(i=0;i<512;i=i+1)begin wr_en=1;wr_addr=i;tick;end wr_en=0;
  for(i=0;i<16;i=i+1)begin font_wr_en=1;font_wr_addr=i;tick;end font_wr_en=0;
  frame;frame;force basic.scroll=13'd1024;force combined.scroll=13'd1024;
  repeat(6)tick;checking=1;
  for(i=0;i<8;i=i+1)for(j=0;j<10;j=j+1)begin
   probe(xs[i],ys[j],1,0,xs[i]==1023);
   if((i+j)%3==0)probe(0,0,0,0,0);
  end
  probe(0,0,1,1,0);probe(1023,599,1,0,1);probe(0,0,0,0,0);repeat(6)tick;
  for(z=0;z<5;z=z+1)begin
   zoom=z;scene=z%4+1;
   case(z)
    0:begin left_edge=258;right_edge=765;top_edge=152;bottom_edge=447;end
    1:begin left_edge=130;right_edge=893;top_edge=77;bottom_edge=522;end
    default:begin left_edge=2;right_edge=1021;top_edge=2;bottom_edge=597;end
   endcase
   audio_valid=1;frame;audio_valid=0;frame;
   for(i=0;i<10;i=i+1)lines[i]=ys[i];
   lines[10]=top_edge;lines[11]=bottom_edge-3;lines[12]=bottom_edge;
   for(row=0;row<13;row=row+1)begin
    native_valid=0;repeat(12)tick;combined.x=0;combined.y=lines[row];
    for(col=0;col<1024;col=col+1)begin
     native_valid=1;native_x=col;native_y=lines[row];tick;
    end
    native_valid=0;repeat(12)tick;
   end
  end
  if(basic_checks!=82 || chain_checks!=66560 || border_checks<13000)
   $fatal(1,"guard coverage basic%0d chain%0d borders%0d",basic_checks,chain_checks,border_checks);
  $display("PASS subtitle border guard: %0d viewport probes/%0d actual OSD-subtitle pixels/%0d native border pixels, five zooms/four palettes, x5/6/1017/1018 and y551/552/591/592/593/594/597, independent75-percent-white/ink reference, exact3-cycle RGB/valid/SOF/EOL and bubbles",basic_checks,chain_checks,border_checks);
  $finish;
 end
 initial begin #15000000;$fatal(1,"subtitle border guard timeout");end
endmodule
