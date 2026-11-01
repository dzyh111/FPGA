`timescale 1ns/1ps
module tb_sonic_engraving;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,enable=1,stream_reset=0,sample_valid=0,valid=1;
 reg [2:0] scene=1;
 reg signed [23:0] sample=0;
 reg [10:0] x=0,y=461;
 reg [23:0] rgb=24'h204060;
 wire out_valid;wire [10:0] out_x,out_y;wire [23:0] out_rgb;
 sonic_engraving dut(.*);
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask
 task frame;begin frame_tick=1;step;frame_tick=0;step;end endtask
 task pixel(input integer xx,input integer yy);begin x=xx;y=yy;repeat(4)step;end endtask
 integer n,w,old_count;
 reg [15:0] first_word;
 reg [47:0] frozen;
 reg [9:0] previous_visible;
 reg checking=0;
 // Newly completed columns and clearing are exposed only at frame boundaries.
 always @(posedge clk)begin
  previous_visible=dut.visible_count;
  #1;if(checking && dut.visible_count!=previous_visible && !frame_tick)
   $fatal(1,"visible prefix changed outside frame boundary");
 end
 initial begin
  repeat(3)step;rst=0;repeat(3)step;frame;checking=1;
  pixel(0,461);if(out_rgb!==rgb)$fatal(1,"uninitialised history leaked");
  // 1500 actual consumed samples; both magnitude signs, clipping and silence.
  sample_valid=1;
  for(n=0;n<1500;n=n+1)begin sample=n[0]?-24'sh400000:24'sh400000;step;end
  sample_valid=0;repeat(3)step;
  if(dut.written_count!=1 || dut.sample_count!=0)$fatal(1,"not exactly 1500 PCM samples/column");
  if(dut.history[0]!=={4'd8,7'd127,1'b1,4'd0})$fatal(1,"PCM feature mismatch %h",dut.history[0]);
  pixel(0,461);if(out_rgb!==rgb)$fatal(1,"unfinished frame exposed a column");
  frame;pixel(0,461);if(out_rgb===rgb)$fatal(1,"guqin ink missing");
  pixel(2,461);if(out_rgb!==rgb)$fatal(1,"unwritten column visible");
  pixel(0,552);if(out_rgb!==rgb)$fatal(1,"ink entered waveform region");
  pixel(0,580);if(out_rgb!==rgb)$fatal(1,"ink entered subtitles region");
  // Video advances during pause/underflow, but no audio means no new features.
  frozen={dut.sample_count,dut.peak,dut.crossings,dut.written_count,dut.previous_peak};
  repeat(12)frame;
  if(frozen!=={dut.sample_count,dut.peak,dut.crossings,dut.written_count,dut.previous_peak})
   $fatal(1,"pause/underflow changed the painting");
  sample_valid=1;sample=24'sh100000;
  repeat(1500)step;sample_valid=0;repeat(3)step;
  if(dut.history[1]!=={4'd2,7'd0,1'b0,4'd1})$fatal(1,"quiet feature mismatch %h",dut.history[1]);
  first_word=dut.history[0];
  // Fill the actual remaining 510 windows; no injected feature/counter values.
  for(w=2;w<512;w=w+1)begin
   sample_valid=1;
   for(n=0;n<1500;n=n+1)begin
    sample=n[4]?24'sh300000:-24'sh300000;
    frame_tick=((w*1500+n)%800)==799;step;
   end
   frame_tick=0;sample_valid=0;repeat(2)step;
  end
  frame;
  if(dut.written_count!=512 || dut.visible_count!=512)$fatal(1,"16-second phrase did not fill 512 columns");
  sample_valid=1;sample=24'sh200000;step;sample_valid=0;
  if(dut.sample_count!=1 || dut.written_count!=0 || dut.history[0]!==first_word)
   $fatal(1,"phrase wrap overwrote the displayed old RAM or dropped its first sample");
  frame;if(dut.visible_count!=0)$fatal(1,"phrase did not clear at frame boundary");
  // Stream reset also clears at a frame, without a RAM-wide reset loop.
  stream_reset=1;repeat(5)step;frame;stream_reset=0;
  if(dut.written_count!=0 || dut.visible_count!=0 || dut.sample_count!=0)$fatal(1,"stream reset state");
  // All four visual styles, using explicit known RAM fixture only for geometry.
  for(w=1;w<=4;w=w+1)begin
   scene=w;repeat(3)step;frame;
   dut.history[0]={4'd8,7'd0,1'b1,4'd0};dut.written_count=1;frame;
   pixel(0,w==4?480:468);
   if(out_rgb===rgb)$fatal(1,"style %0d has no visible mark",w);
  end
  enable=0;repeat(4)step;pixel(0,480);
  if(out_rgb!==rgb)$fatal(1,"disabled art changed photo");
  scene=0;enable=1;repeat(4)step;
  if(out_rgb!==rgb)$fatal(1,"cover/non-heritage scene changed photo");
  $display("PASS sonic engraving: 768000 PCM samples, one 512x16 history, real features, frame commit, freeze, wrap, reset, four styles, bounded overlay");
  $finish;
 end
 initial begin #20000000;$fatal(1,"engraving timeout");end
endmodule
