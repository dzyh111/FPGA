`timescale 1ns/1ps
// Standalone anticipation/rebound contract plus all 70 recording-derived cues.
// This tests digital gesture scheduling, not physical LCD/acoustic latency.
module tb_drum_motion;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,stream_reset=0,enable=1,frame_tick=0,advance=0,onset=0;
 reg [3:0] level=15;
 reg [8:0] cue_index=0;
 reg [10:0] window_sample=0;
 wire [5:0] left_age,right_age;
 wire left_strong,right_strong;
 wire [2:0] stroke_count;
 wire [4:0] left_lift,right_lift;
 reg [10:0] ahead_addr=1538;
 wire [7:0] data,ahead_data;
 reg synthetic=0,synthetic_ahead=0;
 wire ahead_onset=synthetic ? synthetic_ahead : ahead_data[3];
 heritage_cue_rom cues(.clk(clk),.addr({2'd3,cue_index}),.data(data),
                      .ahead_addr(ahead_addr),.ahead_data(ahead_data));
 drum_motion dut(.clk(clk),.rst(rst),.stream_reset(stream_reset),.enable(enable),
  .frame_tick(frame_tick),.advance(advance),.onset(onset),.level(level),
  .cue_index(cue_index),.window_sample(window_sample),.ahead_onset(ahead_onset),
  .left_age(left_age),.right_age(right_age),.left_strong(left_strong),
  .right_strong(right_strong),.stroke_count(stroke_count),
  .left_lift(left_lift),.right_lift(right_lift));
 reg [7:0] reference_cue [0:2047];
 integer events=0,frames=0,prepared_frames=0,preparation_changes=0;
 integer max_left=0,k,p,old_left,old_right,expected_side;
 integer expected_events=0,old_count,contact_jumps=0,largest_contact_jump=0;
 integer max_left_weak=0;
 reg pending=0,was_preparing;
 reg [8:0] old_target;
 reg [63:0] snapshot;
 function [63:0] state_snapshot;
  input unused;
  begin state_snapshot={dut.preparing,dut.prepare_right,dut.prepare_index,
    dut.last_index,left_age,right_age,left_strong,right_strong,
    stroke_count,left_lift,right_lift};end
 endfunction
 function integer absdiff;
  input integer a,b;
  begin absdiff=a>b?a-b:b-a;end
 endfunction
 task reset_motion;begin
  @(negedge clk);stream_reset=1;frame_tick=0;advance=0;onset=0;
  cue_index=0;window_sample=0;
  repeat(3)@(negedge clk);
  if(left_age!=63 || right_age!=63 || left_lift!=15 || right_lift!=15 ||
     left_strong || right_strong || stroke_count!=0 || dut.preparing)
   $fatal(1,"reset contract changed");
  stream_reset=0;
 end endtask
 task adopt;
  input integer selected_cue,selected_sample;
  input hit,lookahead;
  begin
   @(negedge clk);cue_index=selected_cue;window_sample=selected_sample;
   synthetic_ahead=lookahead;onset=hit;advance=1;frame_tick=1;
   old_left=left_lift;old_right=right_lift;old_count=stroke_count;
   expected_side=stroke_count[0]^stroke_count[2];
   @(posedge clk);#1;
   if(left_lift>30 || right_lift>30)$fatal(1,"lift exceeded 30 pixels");
   if(hit)begin
    if(stroke_count!==((old_count+1)&7))$fatal(1,"real onset did not count once");
    if((!expected_side || (level>=13 && old_count==7)) && (left_lift!=0 || left_age!=0))
     $fatal(1,"left onset delayed or failed to contact");
    if((expected_side || (level>=13 && old_count==7)) && (right_lift!=0 || right_age!=0))
     $fatal(1,"right onset delayed or failed to contact");
   end else begin
    if(stroke_count!=old_count)$fatal(1,"preparation/rebound fabricated a stroke");
    if(absdiff(left_lift,old_left)>4 || absdiff(right_lift,old_right)>4)
     $fatal(1,"non-contact movement exceeded 4 pixels/frame");
    if(left_lift==0 || right_lift==0)$fatal(1,"a no-onset frame touched the skin");
   end
   @(negedge clk);frame_tick=0;advance=0;onset=0;
  end
 endtask
 task stopped_audio;
  input [127:0] reason;
  begin
   snapshot=state_snapshot(0);
   for(k=0;k<9;k=k+1)begin
    @(negedge clk);frame_tick=1;advance=0;
    @(posedge clk);#1;
    if(state_snapshot(0)!==snapshot)$fatal(1,"%s advanced geometry/preparation without PCM",reason);
    @(negedge clk);frame_tick=0;
   end
   $display("PASS drum motion %s freezes pending preparation and geometry",reason);
  end
 endtask
 initial begin
  $readmemh("rtl/heritage_cue.hex",reference_cue);
  repeat(4)@(negedge clk);rst=0;synthetic=1;reset_motion;
  // Latch target 102 exactly once, even if the following lookahead is also set.
  adopt(100,0,0,1);
  if(!dut.preparing || dut.prepare_index!=102)$fatal(1,"lookahead target not latched");
  adopt(100,800,0,1);
  if(left_lift>=15)$fatal(1,"lookahead did not start a visible preparatory descent");
  stopped_audio("pause");
  adopt(101,100,0,1);
  if(dut.prepare_index!=102)$fatal(1,"lookahead retargeted a pending stroke");
  adopt(101,900,0,1);
  stopped_audio("underflow");
  adopt(102,199,1,0);
  if(dut.preparing)$fatal(1,"onset did not clear preparation");
  // Do not lose a distinct future event while consuming the current onset.
  reset_motion;adopt(100,800,1,1);
  if(!dut.preparing || dut.prepare_index!=102 || !dut.prepare_right)
   $fatal(1,"current contact discarded/reassigned a known future event incorrectly");
  adopt(101,100,0,0);
  if(dut.prepare_index!=102)$fatal(1,"future target did not survive cue address advance");
  adopt(102,100,1,0);
  // A single strong hit reaches 30 px with a smooth, finer rebound curve.
  reset_motion;adopt(0,0,1,0);
  for(k=1;k<=24;k=k+1)begin
   adopt(k/2,(k%2)*800,0,0);
   if(left_lift>max_left)max_left=left_lift;
  end
  if(max_left!=30)$fatal(1,"strong stroke did not reach the full 30-pixel lift");
  reset_motion;level=8;adopt(0,0,1,0);
  for(k=1;k<=24;k=k+1)begin
   adopt(k/2,(k%2)*800,0,0);
   if(left_lift>max_left_weak)max_left_weak=left_lift;
  end
  if(max_left_weak!=23)$fatal(1,"weak stroke peak changed: %0d",max_left_weak);
  // Exercise both sides and the actual every-eighth strong double accent.
  reset_motion;level=15;
  for(k=0;k<8;k=k+1)adopt(k,0,1,0);
  if(stroke_count!=0 || left_age!=0 || right_age!=0 || left_lift!=0 || right_lift!=0)
   $fatal(1,"eighth strong stroke no longer produces the original double accent");
  reset_motion;adopt(510,0,0,1);adopt(511,800,0,1);
  if(dut.preparing)$fatal(1,"lookahead crossed the final two windows into another scene");
  reset_motion;adopt(509,0,0,1);
  if(dut.prepare_index!=511)$fatal(1,"last legal same-scene target was lost");
  adopt(0,0,0,1);
  if(dut.preparing)$fatal(1,"wrapped stream kept a stale target");
  enable=0;@(negedge clk);@(negedge clk);
  if(left_lift!=15 || right_lift!=15 || stroke_count!=0)$fatal(1,"disable reset failed");
  enable=1;
  $display("PASS drum motion contracts: bounded preparation/rebound, real contact, strong/weak peaks, double accent, same-scene guard, reset");

  // Replay the unchanged real cue data and one accepted sample at a time.
  synthetic=0;reset_motion;
  for(k=0;k<512;k=k+1)
   if(reference_cue[1536+k][3])expected_events=expected_events+1;
  if(expected_events!=70)$fatal(1,"recording no longer has 70 cue events");
  for(p=0;p<768000;p=p+1)begin
   @(negedge clk);cue_index=p/1500;window_sample=p%1500;
   ahead_addr=1536+(cue_index<510 ? cue_index+2 : cue_index);
   if((p%1500)==0 && reference_cue[1536+cue_index][3])pending=1;
   level=reference_cue[1536+cue_index][7:4];
   onset=pending;advance=1;frame_tick=((p+1)%800)==0;
   old_left=left_lift;old_right=right_lift;old_count=stroke_count;
   expected_side=stroke_count[0]^stroke_count[2];
   was_preparing=dut.preparing;old_target=dut.prepare_index;
   snapshot=state_snapshot(0);
   @(posedge clk);#1;
   if(data!==reference_cue[1536+cue_index] || ahead_data!==reference_cue[ahead_addr])
    $fatal(1,"shared cue ROM ports do not match their independently addressed reference entries");
   if(left_lift>30 || right_lift>30)$fatal(1,"real cue lift exceeded bounds");
   if(frame_tick)begin
    frames=frames+1;
    if(pending)begin
     events=events+1;
     if(stroke_count!==((old_count+1)&7))$fatal(1,"real cue event lost or duplicated");
     if((!expected_side || (level>=13 && old_count==7)) && (left_lift!=0 || left_age!=0))
      $fatal(1,"real left contact missed onset frame");
     if((expected_side || (level>=13 && old_count==7)) && (right_lift!=0 || right_age!=0))
      $fatal(1,"real right contact missed onset frame");
     if((!expected_side && old_left>4) || (expected_side && old_right>4))contact_jumps=contact_jumps+1;
     if((!expected_side ? old_left : old_right)>largest_contact_jump)
      largest_contact_jump=!expected_side ? old_left : old_right;
    end else begin
     if(stroke_count!=old_count)$fatal(1,"real non-onset frame added a stroke");
     if(absdiff(left_lift,old_left)>4 || absdiff(right_lift,old_right)>4)
      $fatal(1,"real non-contact frame exceeded 4-pixel slew");
     if(left_lift==0 || right_lift==0)$fatal(1,"real anticipation touched skin before onset");
     if(was_preparing && dut.preparing && dut.prepare_index!=old_target)
      $fatal(1,"real lookahead changed an existing target");
    end
    if(dut.preparing)begin
     prepared_frames=prepared_frames+1;
     if(left_lift!=old_left || right_lift!=old_right)preparation_changes=preparation_changes+1;
    end
    pending=0;
   end else if(state_snapshot(0)!==snapshot)begin
    $fatal(1,"drum changed outside an adopted video frame");
   end
   @(negedge clk);frame_tick=0;advance=0;onset=0;
  end
  if(events!=70 || stroke_count!=(70&7))$fatal(1,"real clip event count %0d, expected 70",events);
  if(preparation_changes<100)$fatal(1,"lookahead did not produce enough visible preparation");
  $display("PASS drum real cue replay: 768000 samples, %0d frames, exactly %0d onsets, %0d prepared frames, %0d moving preparations",
            frames,events,prepared_frames,preparation_changes);
  $display("PASS drum contact scheduling: no contact delay; %0d/70 onset contacts require a >4 px correction (maximum %0d px), never disguised as globally jump-free",
            contact_jumps,largest_contact_jump);
  $finish;
 end
 initial begin #35000000;$fatal(1,"drum motion test timed out");end
endmodule
