`timescale 1ns/1ps
module tb_heritage_fx;
 reg clk=0,rst=1,frame=0,enable=0,clear=1,consumed=0,valid=1;
 reg [31:0] pos=0;
 reg [2:0] scene=1;
 reg [10:0] x=365,y=274;
 reg [23:0] rgb=24'h204060;
 wire ov;wire [10:0] ox,oy;wire [23:0] color;
 wire signed [5:0] bow;wire [4:0] drum;
 integer i,errors=0;
 reg [5:0] frozen_age;reg [8:0] frozen_phase;
 heritage_fx dut(.clk(clk),.rst(rst),.frame_tick(frame),.enable(enable),
 .stream_reset(clear),.scene(scene),.sample_consumed(consumed),.sample_position(pos),
 .valid(valid),.x(x),.y(y),.rgb(rgb),.out_valid(ov),.out_x(ox),.out_y(oy),
 .out_rgb(color),.bow_offset(bow),.drum_offset(drum));
 always #5 clk=~clk;
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask
 task tick;begin frame=1;step;frame=0;step;end endtask
 initial begin
  step;rst=0;repeat(3)step; // geometry -> ink selection -> RGB, three registered stages
  if(!ov || ox!=x || oy!=y || color!=rgb)$fatal(1,"bypass pipeline");
  // Deterministic fixture, independent of subjective audio content.
  for(i=0;i<2048;i=i+1)dut.u_cue.cue_mem[i]=8'hf8;
  clear=0;enable=1;consumed=1;pos=1;
  repeat(5)step;
  tick;
  if(dut.age!=0)$fatal(1,"missing onset");
  tick;
  if(dut.age!=1)$fatal(1,"same cue retriggered");
  consumed=0;tick; // settle preceding moved flag
  frozen_age=dut.age;frozen_phase=dut.bow_phase;
  repeat(8)tick;
  if(dut.age!=frozen_age || dut.bow_phase!=frozen_phase)$fatal(1,"paused motion advanced");
  clear=1;step;
  if(dut.cue_index!=0 || dut.window_sample!=0 || dut.age!=63)$fatal(1,"scene reset");
  clear=0;consumed=1;pos=1;
  for(i=0;i<1500;i=i+1)begin pos=i+1;step;end
  if(dut.cue_index!=1 || dut.window_sample!=0)$fatal(1,"cue sample count");
  pos=0;step;
  if(dut.cue_index!=0 || dut.window_sample!=0)$fatal(1,"cue loop count");
  $display("PASS heritage FX: onset once, freeze, reset, exact cue count, bypass");
  $finish;
 end
endmodule
