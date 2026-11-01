`timescale 1ns/1ps
// Real pixel pipeline with synthetic controls, not a board/audio measurement.
module tb_ui_visibility_render;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame=0,valid=0,menu=0;
 reg [2:0] scene=3,item=0,bri=2,con=2,zoom=2;
 reg [10:0] x=0,y=0;
 reg [23:0] rgb=0;
 reg [3:0] fixture_level=12;
 reg [7:0] fixture_phase=0;
 wire fv,tv,ov,sof,last;
 wire [10:0] fx,fy,tx,ty;
 wire [23:0] frgb,trgb,orgb;
 heritage_fx effects(.clk(clk),.rst(rst),.frame_tick(frame),.enable(1'b1),
  .stream_reset(1'b0),.scene(scene),.sample_consumed(1'b0),.sample_position(32'd0),
  .valid(valid),.x(x),.y(y),.rgb(rgb),.out_valid(fv),.out_x(fx),.out_y(fy),.out_rgb(frgb));
 calligraphy_title title(.clk(clk),.rst(rst),.frame_tick(frame),.enable(1'b1),
  .scene(scene),.valid(fv),.x(fx),.y(fy),.rgb(frgb),.out_valid(tv),.out_x(tx),.out_y(ty),.out_rgb(trgb));
 media_osd osd(.clk(clk),.rst(rst),.frame_tick(frame),.cover_active(1'b0),
  .state_code(4'd6),.fade_alpha(5'd16),.manual_transition(1'b0),.menu_active(menu),.menu_item(item),
  .rebuild_busy(1'b0),.rebuild_progress(3'd0),.rebuild_total(3'd4),
  .brightness_level(bri),.contrast_level(con),.scale_override(2'd0),.zoom_level(zoom),
  .spectrum_enable(1'b0),.scene(scene),.audio_valid(1'b0),.audio_sample(24'sd0),
  .audio_stream_reset(1'b0),.valid(tv),.x(tx),.y(ty),.rgb(trgb),
  .out_valid(ov),.out_sof(sof),.out_last(last),.out_rgb(orgb));
 reg [10:0] trace_x[0:5],trace_y[0:5];
 integer k;
 always @(posedge clk)begin
  trace_x[0]<=tx;trace_y[0]<=ty;
  for(k=1;k<6;k=k+1)begin trace_x[k]<=trace_x[k-1];trace_y[k]<=trace_y[k-1];end
 end
 reg [23:0] photo[0:614399];
 reg [1023:0] filename;
 integer file,index_file,rx,ry,rw,rh,pixels,xx,yy,n,a,captures=0;
 reg capturing=0;
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask
 always @(negedge clk)if(capturing && ov)begin
  if(trace_x[5]!==rx+pixels%rw || trace_y[5]!==ry+pixels/rw || (^orgb)===1'bx)
   $fatal(1,"UI preview pixel/coordinate unknown or misaligned: %0d",pixels);
  $fdisplay(file,"%06h",orgb);pixels=pixels+1;
 end
 task fill_title;
  begin
   for(n=0;n<8192;n=n+1)begin
    a=(scene-1)*8192+((n%128)>=64?4096:0)+(n/128)*64+n%64;
    title.ink_canvas[n]=title.glyph_dictionary_rom[title.glyph_index_rom[a>>4]][a%16];
    if(title.ink_canvas[n]!==title.glyph_rom[a])$fatal(1,"preview packed glyph differs");
   end
  end
 endtask
 task capture;
  input [255:0] label;
  input integer left,top,width,height;
  begin
   valid=0;
   // Explicit position-QA fixture: make every finger-hole rim visible.
   // This is not the recorded performer's inferred fingering.
   for(n=0;n<6;n=n+1)effects.hole_glow[n]=fixture_level>=2?12:0;
   repeat(16)step;frame=1;step;frame=0;repeat(16)step;
   if(menu && osd.zoom_d!==3'd2)$fatal(1,"menu proof did not latch 100-percent ZOOM");
   rx=left;ry=top;rw=width;rh=height;
   $sformat(filename,"sim/ui_visibility_preview/%0s.rgbhex",label);
   file=$fopen(filename,"w");if(!file)$fatal(1,"cannot open UI RGB capture");
   $fdisplay(file,"RTL_RGB_HEX_V1 %0d %0d",rw,rh);
   $fdisplay(index_file,"%0s %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
    label,scene,fixture_phase,fixture_level,menu,item,bri,con,zoom,rx,ry,rw,rh);
   pixels=0;capturing=1;
   for(yy=ry;yy<ry+rh;yy=yy+1)for(xx=rx;xx<rx+rw;xx=xx+1)begin
    valid=1;x=xx;y=yy;rgb=photo[yy*1024+xx];step;
   end
   valid=0;repeat(16)step;capturing=0;$fclose(file);
   if(pixels!=rw*rh)$fatal(1,"incomplete UI preview %0s: %0d",label,pixels);
   captures=captures+1;$display("CAPTURE %0s: %0d actual RTL pixels",label,pixels);
  end
 endtask
 initial begin
  index_file=$fopen("sim/ui_visibility_preview/capture_index.txt","w");
  if(!index_file)$fatal(1,"prepare UI preview directory first");
  $fdisplay(index_file,"RTL_UI_VISIBILITY_CAPTURE_V2 synthetic_controls_not_board_or_audio");
  repeat(4)step;rst=0;
  force effects.level=fixture_level;force effects.flow_phase=fixture_phase;
  force effects.age=63;force effects.drum_left_age=63;force effects.drum_right_age=63;
  force title.state=4;force title.ready=1;force title.done=1;force title.pen_visible=0;
  scene=3;repeat(12)step;fill_title;
  $readmemh("sim/ui_visibility_preview/source_scene3.hex",photo);
  fixture_phase=0;capture("dizi_phase00",75,190,805,170);
  fixture_phase=16;capture("dizi_phase16",75,190,805,170);
  fixture_phase=32;capture("dizi_phase32",75,190,805,170);
  fixture_phase=48;capture("dizi_phase48",75,190,805,170);
  fixture_level=0;fixture_phase=0;capture("dizi_quiet",75,190,805,170);
  scene=4;repeat(12)step;fill_title;
  $readmemh("sim/ui_visibility_preview/source_scene4.hex",photo);
  fixture_level=0;capture("drum_title",244,32,108,188);
  menu=1;item=0;capture("menu_zoom",240,80,544,440);
  item=1;bri=3;capture("menu_brightness",240,80,544,440);
  $fclose(index_file);
  if(captures!=8)$fatal(1,"UI capture count");
  $display("PASS 8 actual RTL UI captures: FX/title/OSD pixels and 12-clock xy alignment; synthetic controls, not real-board/audio proof");
  $finish;
 end
 initial begin #30000000;$fatal(1,"UI preview timeout");end
endmodule
