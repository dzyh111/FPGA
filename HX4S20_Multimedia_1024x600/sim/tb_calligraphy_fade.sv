`timescale 1ns/1ps
module tb_calligraphy_fade;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,title_enable=1;reg [2:0] scene=1;
 reg [4:0] fade=16;
 reg [10:0] x=142,y=94; // guqin origin(124,64) + display(18,30) -> canvas(16,26)
 wire ev,ov,sof,last;wire [10:0] ex,ey;wire [23:0] ergb,orgb;
 calligraphy_title ink(.clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(title_enable),
  .scene(scene),.valid(1'b1),.x(x),.y(y),.rgb(24'h204060),
  .out_valid(ev),.out_x(ex),.out_y(ey),.out_rgb(ergb));
 media_osd osd(.clk(clk),.rst(rst),.frame_tick(frame_tick),.cover_active(1'b0),
  .state_code(4'd4),.fade_alpha(fade),.manual_transition(1'b0),.menu_active(1'b0),.menu_item(3'd0),
  .rebuild_busy(1'b0),.rebuild_progress(3'd0),.rebuild_total(3'd0),
  .brightness_level(3'd2),.contrast_level(3'd2),.scale_override(2'd0),
  .spectrum_enable(1'b0),.scene(scene),.audio_valid(1'b0),.audio_sample(24'sd0),
  .audio_stream_reset(1'b0),.valid(ev),.x(ex),.y(ey),.rgb(ergb),
  .out_valid(ov),.out_sof(sof),.out_last(last),.out_rgb(orgb));
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask
 initial begin
  repeat(3)step;rst=0;repeat(3)step;
  // Writer correctness is tested separately. Seed one stable written pixel
  // here to isolate the actual title -> OSD whole-picture fade integration.
  ink.ready=1;ink.done=1;ink.state=4;ink.saved_scene=1;
  ink.pen_visible=0;ink.ink_canvas[26*128+16]=1;
  repeat(16)step;
  if(!ov || orgb===24'h204060)$fatal(1,"written name not present at full fade");
  fade=0;repeat(16)step;
  if(orgb!==24'h101c30)$fatal(1,"writing escaped photo fade: %h",orgb);
  fade=8;repeat(16)step;
  if(orgb===24'h101c30 || orgb===24'h204060)$fatal(1,"half fade not applied");
  if(!ink.ink_canvas[26*128+16] || !ink.done)$fatal(1,"fade reset handwriting");
  fade=16;x=200;y=468;repeat(16)step;
  if(orgb!==24'h204060)$fatal(1,"removed engraving still changes lower photo");
  scene=4;repeat(6)step;
  ink.ready=1;ink.done=1;ink.state=4;ink.saved_scene=4;
  ink.pen_visible=0;ink.ink_canvas[26*128+16]=1;
  x=244;y=80;repeat(16)step;
  if(orgb!==24'h204060)$fatal(1,"removed drum plaque still changes photo");
  x=240;y=16;repeat(16)step;
  if(orgb!==24'h204060)$fatal(1,"removed drum frame still changes photo");
  x=278;y=78;repeat(16)step;
  if(orgb!==24'h204060)$fatal(1,"old drum position still contains ink");
  x=82;y=62;repeat(16)step;
  if(orgb!==24'he1e5e9)$fatal(1,"drum bright white dry ink at tree trunk: %h",orgb);
  fade=8;repeat(16)step;
  if(orgb!==24'h78808c)$fatal(1,"drum text half fade mismatch: %h",orgb);
  fade=0;repeat(16)step;
  if(orgb!==24'h101c30)$fatal(1,"drum text escaped whole-picture fade");
  fade=16;title_enable=0;repeat(16)step;
  if(orgb!==24'h204060)$fatal(1,"disabled drum text remains");
  $display("PASS handwriting fade: title/photo share fade, tree-trunk drum bright white ink/no plaque or frame, old position clear, half/zero fade, disabled bypass, old ink retained");
  $finish;
 end
endmodule
