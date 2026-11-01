`timescale 1ns/1ps
module tb_smooth_animation;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,enable=1,stream_reset=1,sample_consumed=1;
 reg [31:0] sample_position=1;
 wire signed [5:0] bow_offset;wire signed [2:0] bow_tilt;wire signed [5:0] bow_angle;
 wire [4:0] drum_offset,drum_right_offset;
 heritage_fx dut(.clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(enable),
  .stream_reset(stream_reset),.scene(3'd2),.sample_consumed(sample_consumed),
  .sample_position(sample_position),.valid(1'b0),.x(11'd0),.y(11'd0),.rgb(24'd0),
  .out_valid(),.out_x(),.out_y(),.out_rgb(),.bow_offset(bow_offset),.bow_tilt(bow_tilt),
  .bow_angle(bow_angle),.drum_offset(drum_offset),.drum_right_offset(drum_right_offset));
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask
 task frame;begin frame_tick=1;step;frame_tick=0;step;end endtask
 integer i,previous_offset,previous_angle,delta,distinct_angles=0;
 integer minimum_offset=32,maximum_offset=-32;
 reg [7:0] previous_flow;
 reg [63:0] angles=0;
 reg [127:0] snapshot;
 function [127:0] state;
  input unused;
  begin state={dut.bow_phase,bow_offset,bow_angle,dut.level_q,dut.flow_phase,
               dut.age};end
 endfunction
 initial begin
  repeat(3)step;rst=0;stream_reset=0;
  for(i=0;i<2048;i=i+1)dut.u_cue.cue_mem[i]=8'hc0;
  repeat(6)step;
  previous_offset=0;previous_angle=0;
  // Ignore startup angle adoption; then require a full set of gradual slopes.
  repeat(4)frame;previous_offset=$signed(bow_offset);previous_angle=$signed(bow_angle);
  previous_flow=dut.flow_phase;
  repeat(200)begin
   frame;
   if(dut.flow_phase!==(previous_flow+8'd1))$fatal(1,"played audio did not advance flute flow phase");
   previous_flow=dut.flow_phase;
   delta=$signed(bow_offset)-previous_offset;
   if(delta < -3 || delta>3)$fatal(1,"bow translation jumped %0d pixels/frame",delta);
   delta=$signed(bow_angle)-previous_angle;
   if(delta < -3 || delta>3)$fatal(1,"bow angle jumped %0d slope units/frame",delta);
   if(bow_offset < -24 || bow_offset>24 || bow_angle < -24 || bow_angle>24)$fatal(1,"bow geometry range");
   if($signed(bow_offset)<minimum_offset)minimum_offset=$signed(bow_offset);
   if($signed(bow_offset)>maximum_offset)maximum_offset=$signed(bow_offset);
   angles[$signed(bow_angle)+32]=1;
   previous_offset=$signed(bow_offset);previous_angle=$signed(bow_angle);
  end
  for(i=0;i<64;i=i+1)if(angles[i])distinct_angles=distinct_angles+1;
  if(distinct_angles<25)$fatal(1,"angle still quantised: only %0d slopes",distinct_angles);
  if(minimum_offset!=-24 || maximum_offset!=24)
   $fatal(1,"bow did not use enlarged travel: min=%0d max=%0d",minimum_offset,maximum_offset);
  sample_consumed=0;frame;snapshot=state(0);
  repeat(20)begin frame;if(state(0)!==snapshot)$fatal(1,"pause easing drift");end
  sample_consumed=1;force dut.pending_level=0;
  repeat(10)frame;
  if(dut.level_q!=0 || dut.level!=0)$fatal(1,"release did not converge to silence");
  release dut.pending_level;
  $display("PASS smooth animation: %0d slope values, +/-24px travel, <=3 px/frame travel and slope steps, consumed audio advances flow, pause freezes easing, silence converges",distinct_angles);
  $finish;
 end
endmodule
