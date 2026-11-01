`timescale 1ns/1ps
module tb_engraving_fade;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0;reg [2:0] scene=1;
 reg [4:0] fade=16;
 wire ev,ov,sof,last;wire [10:0] ex,ey;wire [23:0] ergb,orgb;
 sonic_engraving ink(.clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(1'b1),
  .stream_reset(1'b0),.scene(scene),.sample_valid(1'b0),.sample(24'sd0),
  .valid(1'b1),.x(11'd0),.y(11'd468),.rgb(24'h204060),
  .out_valid(ev),.out_x(ex),.out_y(ey),.out_rgb(ergb));
 media_osd osd(.clk(clk),.rst(rst),.frame_tick(frame_tick),.cover_active(1'b0),
  .state_code(4'd4),.fade_alpha(fade),.menu_active(1'b0),.menu_item(3'd0),
  .rebuild_busy(1'b0),.rebuild_progress(3'd0),.rebuild_total(3'd0),
  .brightness_level(3'd2),.contrast_level(3'd2),.scale_override(2'd0),
  .spectrum_enable(1'b0),.scene(scene),.audio_valid(1'b0),.audio_sample(24'sd0),
  .audio_stream_reset(1'b0),.valid(ev),.x(ex),.y(ey),.rgb(ergb),
  .out_valid(ov),.out_sof(sof),.out_last(last),.out_rgb(orgb));
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask
 initial begin
  repeat(3)step;rst=0;repeat(5)step;
  frame_tick=1;step;frame_tick=0;step;
  ink.history[0]={4'd8,7'd0,1'b1,4'd0};ink.written_count=1;
  frame_tick=1;step;frame_tick=0;repeat(15)step;
  if(!ov || orgb==24'h204060)$fatal(1,"art not in full picture");
  fade=0;repeat(15)step;
  if(orgb!==24'h101c30)$fatal(1,"engraving escaped whole-picture fade: %h",orgb);
  fade=8;repeat(15)step;
  if(orgb===24'h101c30 || orgb===24'h204060)$fatal(1,"half fade did not blend");
  if(ink.written_count!=1)$fatal(1,"fade reset the painting");
  $display("PASS engraving fade: photo and ink share existing fade stage, no reload, progress preserved");
  $finish;
 end
endmodule
