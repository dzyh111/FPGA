`timescale 1ns/1ps
// Full native frames from real title/OSD RTL. Neutral synthetic background,
// completed handwriting fixture, no TF picture edits and no board claim.
module tb_gallery_visual_render;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,valid=0,menu=0;
 reg [10:0] x=0,y=0;
 wire title_valid,ov,sof,last;
 wire [10:0] title_x,title_y;
 wire [23:0] title_rgb,color;
 calligraphy_title title(.clk(clk),.rst(rst),.frame_tick(frame_tick),
  .enable(1'b1),.scene(3'd4),.valid(valid),.x(x),.y(y),.rgb(24'he6e0d0),
  .out_valid(title_valid),.out_x(title_x),.out_y(title_y),.out_rgb(title_rgb));
 media_osd osd(.clk(clk),.rst(rst),.frame_tick(frame_tick),
  .cover_active(1'b0),.state_code(4'd6),.fade_alpha(5'd16),.manual_transition(1'b0),
  .menu_active(menu),.menu_item(3'd0),.rebuild_busy(1'b0),
  .rebuild_progress(3'd0),.rebuild_total(3'd4),.brightness_level(3'd2),
  .contrast_level(3'd2),.zoom_level(3'd2),.scale_override(2'd0),
  .spectrum_enable(1'b0),.scene(3'd4),.audio_valid(1'b0),
  .audio_sample(24'sd0),.audio_stream_reset(1'b0),.valid(title_valid),
  .x(title_x),.y(title_y),.rgb(title_rgb),
  .out_valid(ov),.out_sof(sof),.out_last(last),.out_rgb(color));
 reg [10:0] trace_x[0:5],trace_y[0:5];
 integer k,fd,pixels=0,xx,yy,n,addr,captures=0;
 reg capturing=0;
 reg [511:0] filename;
 always @(posedge clk)begin
  trace_x[0]<=title_x;trace_y[0]<=title_y;
  for(k=1;k<6;k=k+1)begin trace_x[k]<=trace_x[k-1];trace_y[k]<=trace_y[k-1];end
 end
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask
 always @(negedge clk)if(capturing && ov)begin
  if(trace_x[5]!==pixels%1024 || trace_y[5]!==pixels/1024 || (^color)===1'bx)
   $fatal(1,"native gallery preview coordinate/color mismatch pixel%0d",pixels);
  if(sof!==(pixels==0) || last!==(pixels%1024==1023))
   $fatal(1,"native gallery preview SOF/last mismatch pixel%0d",pixels);
  $fwrite(fd,"%c%c%c",color[23:16],color[15:8],color[7:0]);
  pixels=pixels+1;
 end
 task capture;
  input [255:0] label;
  begin
   valid=0;repeat(16)step;frame_tick=1;step;frame_tick=0;repeat(16)step;
   $sformat(filename,"sim/gallery_preview/%0s.ppm",label);
   fd=$fopen(filename,"wb");if(!fd)$fatal(1,"prepare sim/gallery_preview first");
   $fwrite(fd,"P6\n1024 600\n255\n");
   pixels=0;capturing=1;
   for(yy=0;yy<600;yy=yy+1)for(xx=0;xx<1024;xx=xx+1)begin
    valid=1;x=xx;y=yy;step;
   end
   valid=0;repeat(16)step;capturing=0;$fclose(fd);
   if(pixels!=614400)$fatal(1,"incomplete native gallery frame");
   captures=captures+1;$display("CAPTURE %0s: %0d native RTL RGB pixels",label,pixels);
  end
 endtask
 initial begin
  repeat(4)step;rst=0;repeat(12)step;
  // Exact final ink fixture; writer regressions independently prove paths.
  title.saved_scene=4;title.scene_code=3;title.state=4;title.ready=1;
  title.done=1;title.pen_visible=0;title.budget=0;
  for(n=0;n<8192;n=n+1)begin
   addr=3*8192+((n%128)>=64?4096:0)+(n/128)*64+n%64;
   title.ink_canvas[n]=title.glyph_rom[addr];
  end
  // Position the continuously clocked highlight away from the top-left.
  for(n=0;n<90;n=n+1)begin frame_tick=1;step;frame_tick=0;step;end
  capture("border_blue_title_native");
  menu=1;capture("menu_native");
  if(captures!=2)$fatal(1,"native gallery capture count");
  $display("PASS 2 full native gallery frames: 1228800 real RTL pixels, title/OSD pipeline and SOF/EOL alignment; neutral fixture, not TF photo or board capture");
  $finish;
 end
 initial begin #20000000;$fatal(1,"native gallery render timeout");end
endmodule
