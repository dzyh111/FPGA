`timescale 1ns/1ps
// Behavioural checks for refreshed gestures. Unlike the retired old-effect
// golden test, these check the intended new geometry and per-stick event clock.
module tb_heritage_fx_refresh;
 reg clk=0,rst=1,frame_tick=0,enable=0,stream_reset=1;
 reg sample_consumed=0,valid=1;
 reg [31:0] sample_position=1;
 reg [2:0] scene=4;
 reg [10:0] x=0,y=0;
 reg [23:0] rgb=24'h204060;
 wire out_valid;wire [10:0] out_x,out_y;wire [23:0] out_rgb;
 wire signed [5:0] bow_offset;wire signed [2:0] bow_tilt;
 wire signed [5:0] bow_angle;
 wire [4:0] drum_offset,drum_right_offset;
 heritage_fx dut(.*);
 always #5 clk=~clk;
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask
 task frame;begin frame_tick=1;step;frame_tick=0;step;end endtask
 task onset;
  input [3:0] strength;
  begin
   // Inject an already-decoded real cue event at the frame adoption boundary.
   // ROM/cue single-event/sample-count behaviour is separately covered by tb_fx.
   dut.hit_pending=1;dut.pending_level=strength;sample_consumed=1;
   step;frame;
  end
 endtask
 integer i,left_hits=0,right_hits=0,simultaneous=0,left_peak=0,right_peak=0;
 reg [5:0] left_age,right_age;
 reg [4:0] left_lift,right_lift;
 reg signed [5:0] saved_bow;
 reg signed [2:0] saved_tilt;
 reg [4:0] previous_phase;
 reg saw_negative_tilt=0,saw_positive_tilt=0;
 initial begin
  repeat(3)step;rst=0;
  for(i=0;i<2048;i=i+1)dut.u_cue.cue_mem[i]=0;
  enable=1;stream_reset=0;sample_consumed=1;
  repeat(5)step;frame;
  for(i=0;i<8;i=i+1)begin
   onset(15);
   if(dut.drum_left_age==0)left_hits=left_hits+1;
   if(dut.drum_right_age==0)right_hits=right_hits+1;
   if(dut.drum_left_age==0 && dut.drum_right_age==0)simultaneous=simultaneous+1;
   if(dut.drum_left_age==0 && drum_offset!=0)$fatal(1,"left contact not aligned");
   if(dut.drum_right_age==0 && drum_right_offset!=0)$fatal(1,"right contact not aligned");
   repeat(12)begin
    frame;
    if(drum_offset>left_peak)left_peak=drum_offset;
    if(drum_right_offset>right_peak)right_peak=drum_right_offset;
   end
  end
  if(left_hits!=4 || right_hits!=5 || simultaneous!=1)
   $fatal(1,"stroke pattern L%0d R%0d both%0d",left_hits,right_hits,simultaneous);
  if(drum_offset>30 || drum_right_offset>30)$fatal(1,"drum lift range");
  if(left_peak!=30 || right_peak!=30)
   $fatal(1,"drum enlarged lift missing: left=%0d right=%0d",left_peak,right_peak);
  // No onset during active audio: ages advance, but no autonomous new contact.
  repeat(70)begin
   frame;
   if(drum_offset==0 || drum_right_offset==0)$fatal(1,"spontaneous strike");
  end
  sample_consumed=0;frame;
  left_age=dut.drum_left_age;right_age=dut.drum_right_age;
  left_lift=drum_offset;right_lift=drum_right_offset;
  repeat(12)frame;
  if({left_age,right_age,left_lift,right_lift} !==
     {dut.drum_left_age,dut.drum_right_age,drum_offset,drum_right_offset})
   $fatal(1,"paused/underflow drum moved");
  // Bow sees multiple shallow angles over the enlarged +/-24 px travel.
  scene=2;sample_consumed=1;force dut.pending_level=12;
  repeat(40)begin
   frame;
   if(bow_offset < -24 || bow_offset>24 || bow_tilt < -2 || bow_tilt>2)
    $fatal(1,"bow range");
   if(bow_tilt<0)saw_negative_tilt=1;
   if(bow_tilt>0)saw_positive_tilt=1;
  end
  if(!saw_negative_tilt || !saw_positive_tilt)$fatal(1,"bow has no angle variation");
  sample_consumed=0;frame;saved_bow=bow_offset;saved_tilt=bow_tilt;
  repeat(12)frame;
  if(saved_bow!=bow_offset || saved_tilt!=bow_tilt)$fatal(1,"paused bow moved");
  release dut.pending_level;
  // Geometry is selected in input stage, colour reaches output three clocks later.
  scene=1;x=365;y=286;force dut.note=2;force dut.age=0;force dut.level=12;
  repeat(3)step;
  if(out_rgb!=24'hb6fff1)$fatal(1,"guqin pluck not at left-hand string");
  x=820;y=205;repeat(3)step;
  if(out_rgb==24'hb6fff1)$fatal(1,"old crowded guqin hotspot remains");
  // Restore the photographed hole rings without filling their black centres.
  scene=3;x=446;y=288;repeat(3)step;
  if(out_rgb!=rgb)$fatal(1,"dizi black finger hole changed");
  dut.hole_glow[0]=15;x=456;y=288;repeat(3)step;
  if(out_rgb!=24'hd5faff)$fatal(1,"dizi calibrated finger annulus missing");
  force dut.flow_phase=0;x=113;y=332;repeat(3)step;
  if(out_rgb!=24'h94293a)$fatal(1,"dizi source note missing: %h",out_rgb);
  x=270;y=266;repeat(3)step;
  if(out_rgb!=rgb)$fatal(1,"removed long flute wave remains");
  release dut.flow_phase;
  release dut.note;release dut.age;release dut.level;
  stream_reset=1;step;
  if(dut.stroke_count!=0 || dut.drum_left_age!=63 || dut.drum_right_age!=63 ||
     bow_tilt!=0 || drum_offset!=15 || drum_right_offset!=15)
   $fatal(1,"stream restart gesture state");
  $display("PASS refreshed FX: left pluck, bow angles, visible flute, independent onset strokes, freeze/reset");
  $finish;
 end
endmodule
