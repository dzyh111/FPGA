`timescale 1ns/1ps
// Control contracts complement the final-glyph regression in tb_calligraphy_title.
module tb_calligraphy_contract;
 reg clk=0;
 always #5 clk=~clk;
 reg rst=1,frame_tick=0,enable=0,valid=0;
 reg [2:0] scene=1;
 reg [10:0] x=0,y=0;
 reg [23:0] rgb=0;
 wire out_valid;
 wire [10:0] out_x,out_y;
 wire [23:0] out_rgb;
 calligraphy_title dut(.*);

 localparam CLEAR=0,LOAD=3,DRAW=5,DRAIN=6,ARM=7;
 reg expected_valid[0:2],expected_bypass[0:2];
 reg [10:0] expected_x[0:2],expected_y[0:2];
 reg [23:0] expected_rgb[0:2];
 integer pipeline_index,pipeline_checks=0,bypass_checks=0;
 // Samples enter stage 0 on an edge and leave stage 2 two edges later:
 // three registered stages, including the input-sampling edge.
 always @(posedge clk)begin
  if(rst)begin
   for(pipeline_index=0;pipeline_index<3;pipeline_index=pipeline_index+1)begin
    expected_valid[pipeline_index]=0;expected_bypass[pipeline_index]=0;
    expected_x[pipeline_index]=0;expected_y[pipeline_index]=0;
    expected_rgb[pipeline_index]=0;
   end
  end else begin
   for(pipeline_index=2;pipeline_index>0;pipeline_index=pipeline_index-1)begin
    expected_valid[pipeline_index]=expected_valid[pipeline_index-1];
    expected_bypass[pipeline_index]=expected_bypass[pipeline_index-1];
    expected_x[pipeline_index]=expected_x[pipeline_index-1];
    expected_y[pipeline_index]=expected_y[pipeline_index-1];
    expected_rgb[pipeline_index]=expected_rgb[pipeline_index-1];
   end
   expected_valid[0]=valid;
   expected_bypass[0]=!enable || scene<1 || scene>4;
   expected_x[0]=x;expected_y[0]=y;expected_rgb[0]=rgb;
   #1;
   if(out_valid!==expected_valid[2] || out_x!==expected_x[2] || out_y!==expected_y[2])
    $fatal(1,"three-stage valid/xy alignment mismatch at %0t",$time);
   pipeline_checks=pipeline_checks+1;
   if(expected_bypass[2])begin
    if(out_rgb!==expected_rgb[2])
     $fatal(1,"three-stage bypass RGB mismatch at %0t: %h vs %h",$time,out_rgb,expected_rgb[2]);
    bypass_checks=bypass_checks+1;
   end
  end
 end

 reg hold_canvas=0;
 reg canvas_snapshot[0:8191];
 integer clear_writes=0,brush_writes=0,lift_checks=0,pause_checks=0;
 reg [13:0] lifted_command;
 wire writer_enabled=!rst && enable && dut.legal_scene && dut.same_scene;
 // This is the existing single-writer contract; snapshots below also compare
 // the actual memory, including uninitialized bits, across ARM intervals.
 wire clear_write=writer_enabled && dut.state==CLEAR;
 wire brush_write=writer_enabled && (dut.state==DRAW || dut.state==DRAIN) && dut.brush_valid && dut.glyph_q;
 always @(posedge clk)if(!rst)begin
  if(hold_canvas && (clear_write || brush_write))
   $fatal(1,"canvas write before the next frame boundary at %0t",$time);
  if(clear_write)clear_writes=clear_writes+1;
  if(brush_write)brush_writes=brush_writes+1;
  if(writer_enabled && dut.pause_frames!=0)begin
   if(clear_write || brush_write || dut.brush_request || dut.brush_valid)
    $fatal(1,"pen pause issued a canvas write/request at %0t",$time);
   if(dut.pen_visible!==0)
    $fatal(1,"pen remained visible while lifted at %0t",$time);
   pause_checks=pause_checks+1;
  end
  if(writer_enabled && dut.state==LOAD && dut.path_q[13])begin
   if(clear_write || brush_write || dut.brush_request || dut.brush_valid)
    $fatal(1,"LOAD pen lift issued a canvas write/request at %0t",$time);
   lifted_command=dut.path_q;
   lift_checks=lift_checks+1;
   #1;
   if(dut.pen_x!==lifted_command[12:6] || dut.pen_y!==lifted_command[5:0] ||
      dut.pen_visible!==0 || dut.pause_frames==0 || dut.budget!==0)
    $fatal(1,"pen lift did not relocate directly and pause at %0t",$time);
  end
 end

 task step;
  begin @(posedge clk);#2;@(negedge clk);end
 endtask
 task pulse_frame;
  begin frame_tick=1;step;frame_tick=0;end
 endtask
 task video_frame;
  begin pulse_frame;repeat(999)step;end
 endtask
 task snapshot_canvas;
  integer address;
  begin
   for(address=0;address<8192;address=address+1)
    canvas_snapshot[address]=dut.ink_canvas[address];
  end
 endtask
 task verify_snapshot;
  integer address;
  begin
   for(address=0;address<8192;address=address+1)
    if(dut.ink_canvas[address]!==canvas_snapshot[address])
     $fatal(1,"canvas changed while awaiting frame boundary at address %0d",address);
  end
 endtask
 task wait_armed;
  integer cycle;
  begin
   for(cycle=0;cycle<127;cycle=cycle+1)begin
    step;
    if(dut.state!==ARM || dut.ready!==0)
     $fatal(1,"mid-frame control change did not stay ARM/hidden at %0t",$time);
   end
   verify_snapshot;
  end
 endtask
 task clear_at_boundary;
  integer address,previous_writes;
  begin
   previous_writes=clear_writes;
   hold_canvas=0;
   pulse_frame;
   if(dut.state!==CLEAR || dut.clear_address!==0 || dut.ready!==0)
    $fatal(1,"frame boundary did not arm CLEAR from address zero");
   for(address=0;address<8192;address=address+1)begin
    if(dut.state!==CLEAR || dut.clear_address!==address || dut.ready!==0)
     $fatal(1,"CLEAR address/ready mismatch before write %0d",address);
    step;
   end
   if(dut.ready!==1 || dut.state===CLEAR || clear_writes-previous_writes!=8192)
    $fatal(1,"CLEAR did not finish after exactly 8192 writes");
   for(address=0;address<8192;address=address+1)
    if(dut.ink_canvas[address]!==0)
     $fatal(1,"CLEAR left a nonzero/unknown canvas pixel %0d",address);
  end
 endtask
 task random_bypass;
  integer cycle;
  begin
   for(cycle=0;cycle<257;cycle=cycle+1)begin
    valid=$urandom_range(0,1);x=$urandom_range(0,2047);y=$urandom_range(0,2047);rgb=$urandom;
    step;
   end
  end
 endtask

 integer frames,previous_lifts,previous_brush_writes,wait_cycles;
 initial begin
  repeat(4)step;
  rst=0;
  step;
  if(dut.state!==ARM || dut.ready!==0)$fatal(1,"reset/disable did not enter ARM");
  random_bypass;

  // Enable midway through a frame: no RAM write until a subsequent tick.
  snapshot_canvas;hold_canvas=1;enable=1;
  wait_armed;
  clear_at_boundary;
  repeat(6)step;
  if(lift_checks!=1 || dut.pause_frames==0)$fatal(1,"initial path command did not lift/pause");
  repeat(3)video_frame;
  pulse_frame;
  wait_cycles=0;
  while(dut.state!=DRAW && wait_cycles<100)begin step;wait_cycles=wait_cycles+1;end
  if(dut.state!=DRAW || brush_writes==0)$fatal(1,"no active brush writing before scene-change test");
  // Change scene precisely while a real ink request is entering the ROM
  // pipeline, so an ungated stale brush_valid would be observable in ARM.
  wait_cycles=0;
  while(!(dut.state==DRAW && dut.brush_request && dut.glyph_rom[dut.glyph_address]===1'b1) && wait_cycles<81)begin
   step;wait_cycles=wait_cycles+1;
  end
  if(wait_cycles==81)$fatal(1,"no pending ink request before scene-change test");

  // Abort an active brush scan; stale ROM/write pipeline must not touch RAM.
  snapshot_canvas;hold_canvas=1;scene=2;
  wait_armed;
  clear_at_boundary;
  previous_lifts=lift_checks;previous_brush_writes=brush_writes;
  frames=0;
  while(!dut.done && frames<700)begin video_frame;frames=frames+1;end
  if(!dut.done || lift_checks-previous_lifts!=11 || brush_writes==previous_brush_writes)
   $fatal(1,"scene 2 failed to exercise all 11 lifted strokes: frames=%0d lifts=%0d",frames,lift_checks-previous_lifts);

  // Preserve already-written ink across disable and a mid-frame re-enable.
  snapshot_canvas;hold_canvas=1;enable=0;
  step;
  if(dut.state!==ARM || dut.ready!==0)$fatal(1,"disable did not enter ARM/hidden");
  random_bypass;
  verify_snapshot;
  enable=1;
  wait_armed;
  clear_at_boundary;
  repeat(6)step;
  if(dut.pause_frames==0)$fatal(1,"re-enabled title did not restart with a lifted pen");
  if(pipeline_checks<1000 || bypass_checks<500 || pause_checks<1000)
   $fatal(1,"insufficient contract coverage");
  $display("PASS calligraphy contracts: mid-frame enable/scene ARM, exact 8192-cycle clear, %0d lifted relocations, %0d pause cycles, %0d pipeline samples (%0d random bypass)",lift_checks,pause_checks,pipeline_checks,bypass_checks);
  $finish;
 end
 initial begin #20000000;$fatal(1,"calligraphy contract timeout");end
endmodule
