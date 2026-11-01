`timescale 1ns/1ps
// Phrase-cue mapping is artwork, not recovered real-world fingering. This
// independently verifies all eight maps, smoothing, consumed-audio clocking,
// pause/underflow freeze, silence release and stream reset of the restored FX.
module tb_flute_notes_timing;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,enable=1,stream_reset=1,sample_consumed=0;
 reg [31:0] sample_position=1;
 reg [2:0] scene=3,fixture_note=0;
 reg [3:0] fixture_strength=15;
 reg valid=1;reg [10:0] x=113,y=332;reg [23:0] rgb=24'h204060;
 wire out_valid;wire [10:0] out_x,out_y;wire [23:0] out_rgb;
 wire signed [5:0] bow_offset,bow_angle;wire signed [2:0] bow_tilt;
 wire [4:0] drum_offset,drum_right_offset;
 heritage_fx dut(.*);
 integer n,h,i,expected_glow,map;
 integer maps[0:7];
 reg [7:0] last_flow;
 reg [63:0] snapshot;
 reg [23:0] saved_pixel;
 function [63:0] visible_state(input unused);
  begin visible_state={dut.flow_phase,dut.level_q,dut.level,dut.note,
   dut.hole_glow[0],dut.hole_glow[1],dut.hole_glow[2],
   dut.hole_glow[3],dut.hole_glow[4],dut.hole_glow[5]};end
 endfunction
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask
 task frame;begin frame_tick=1;step;frame_tick=0;step;end endtask
 initial begin
  maps[0]=63;maps[1]=31;maps[2]=15;maps[3]=7;
  maps[4]=3;maps[5]=1;maps[6]=0;maps[7]=0;
  repeat(4)step;rst=0;
  force dut.pending_note=fixture_note;force dut.pending_level=fixture_strength;
  for(n=0;n<8;n=n+1)begin
   stream_reset=1;sample_consumed=0;fixture_note=n;step;
   for(h=0;h<6;h=h+1)if(dut.hole_glow[h]!=0)$fatal(1,"reset left hole ink");
   stream_reset=0;sample_consumed=1;repeat(4)step;
   for(i=1;i<=6;i=i+1)begin
    last_flow=dut.flow_phase;frame;
    if(dut.flow_phase!==(last_flow+8'd1))$fatal(1,"consumed audio did not move notes");
    expected_glow=i<5?i*3:15;map=maps[n];
    for(h=0;h<6;h=h+1)begin
     if(dut.hole_glow[h]!==(((map>>h)&1)?expected_glow:0))
      $fatal(1,"phrase map %0d hole %0d frame %0d glow=%0d",n,h,i,dut.hole_glow[h]);
    end
   end
   sample_consumed=0;frame;repeat(5)step;
   snapshot=visible_state(0);saved_pixel=out_rgb;
   repeat(10)begin
    frame;
    if(visible_state(0)!==snapshot || out_rgb!==saved_pixel)
     $fatal(1,"paused/underflow notes or holes drifted for map %0d",n);
   end
  end
  // Lowering audio level while audio is still consumed releases the old
  // accents by one level/frame, and completely removes every moving note.
  stream_reset=1;step;stream_reset=0;fixture_note=0;sample_consumed=1;
  repeat(4)step;repeat(6)frame;
  fixture_strength=0;
  for(i=1;i<=16;i=i+1)begin
   frame;
   for(h=0;h<6;h=h+1)if(dut.hole_glow[h] !== (i<15?15-i:0))
    $fatal(1,"silent hole release mismatch frame %0d",i);
  end
  if(dut.level!=0 || dut.music_note)$fatal(1,"silent note remained visible");
  enable=0;step;
  if(dut.flow_phase!=0 || dut.level_q!=0)$fatal(1,"disable did not reset phase");
  for(h=0;h<6;h=h+1)if(dut.hole_glow[h]!=0)$fatal(1,"disable left hole ink");
  release dut.pending_note;release dut.pending_level;
  $display("PASS flute notes timing: 8 phrase maps, 6x4-bit eased hole accents, consumed-frame notes, pause/underflow freezes pixel/state, silence release, stream/disable reset");
  $finish;
 end
 initial begin #1000000;$fatal(1,"flute notes timing timeout");end
endmodule
