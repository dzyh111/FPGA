`timescale 1ns/1ps
// Real recording-derived cue regression. No ROM entries, pending flags or
// gesture registers are injected. This measures DIGITAL cue -> motion frame
// adoption only; it is not end-to-end loudspeaker/display synchronization and
// does not validate the audio onset detector or real hardware latency.
module tb_real_tanggu_sync;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,enable=1,stream_reset=1,sample_consumed=0;
 reg [31:0] sample_position=0;
 wire out_valid;wire [10:0] out_x,out_y;wire [23:0] out_rgb;
 wire signed [5:0] bow_offset;wire signed [2:0] bow_tilt;
 wire [4:0] drum_offset,drum_right_offset;
 heritage_fx dut(.clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(enable),
  .stream_reset(stream_reset),.scene(3'd4),.sample_consumed(sample_consumed),
  .sample_position(sample_position),.valid(1'b0),.x(11'd0),.y(11'd0),.rgb(24'd0),
  .out_valid(out_valid),.out_x(out_x),.out_y(out_y),.out_rgb(out_rgb),
  .bow_offset(bow_offset),.bow_tilt(bow_tilt),
  .drum_offset(drum_offset),.drum_right_offset(drum_right_offset));
 reg [7:0] reference_cue[0:2047];
 integer expected_window[0:511];
 reg seen_window[0:511];
 integer expected_events=0,events=0,last_position=-1,minimum_delay=800,maximum_delay=0;
 integer k,position,delay_samples,expected_start;
 reg checking=0;reg [2:0] previous_stroke=0;
 // Track actual consumed sample positions, not elapsed simulation clocks.
 always @(posedge clk)begin
  if(sample_consumed && !rst && !stream_reset)last_position=sample_position;
  #1;
  if(checking && !rst && !stream_reset)begin
   if(sample_consumed && (dut.cue_index!==sample_position/1500 ||
                         dut.window_sample!==sample_position%1500))
    $fatal(1,"cue counter differs from consumed samples at position %0d",sample_position);
   if(dut.stroke_count!==previous_stroke)begin
    if(dut.stroke_count!==((previous_stroke+1)&7))
     $fatal(1,"stroke_count skipped or changed without exactly one event");
    if(!frame_tick)$fatal(1,"stroke changed outside video adoption frame");
    if(events>=expected_events)$fatal(1,"more strokes than recording-derived onset windows");
    if(seen_window[expected_window[events]])$fatal(1,"same cue onset retriggered");
    expected_start=expected_window[events]*1500;
    delay_samples=last_position-expected_start;
    if(delay_samples<0 || delay_samples>800)
     $fatal(1,"onset %0d window %0d adopted outside 0..800 samples: at %0d delay %0d",
               events,expected_window[events],last_position,delay_samples);
    if(delay_samples<minimum_delay)minimum_delay=delay_samples;
    if(delay_samples>maximum_delay)maximum_delay=delay_samples;
    seen_window[expected_window[events]]=1;events=events+1;
   end
  end
  previous_stroke=dut.stroke_count;
 end
 function [255:0] frozen_state(input reg unused);
  begin
   frozen_state={dut.cue_index,dut.window_sample,dut.stroke_count,
    dut.drum_left_age,dut.drum_right_age,drum_offset,drum_right_offset,
    dut.age,dut.bow_phase,bow_offset,bow_tilt,dut.level,dut.note,
    dut.hit_pending,dut.u_drum.preparing,dut.u_drum.prepare_right,
    dut.u_drum.prepare_index,dut.u_drum.last_index};
  end
 endfunction
 task consume(input integer selected_position);begin
  @(negedge clk);sample_position=selected_position;sample_consumed=1;
  frame_tick=((selected_position+1)%800)==0; // 48 kHz / 800 = 60 video frames/s.
  @(negedge clk);sample_consumed=0;frame_tick=0;
 end endtask
 task frame_without_audio;begin
  // Keep video advancing while no PCM sample is accepted. The accelerated
  // simulation uses two clocks/sample, hence 1600 clocks per 60 Hz frame.
  repeat(1599)@(negedge clk);frame_tick=1;
  @(negedge clk);frame_tick=0;
 end endtask
 task stopped_audio(input string reason);
  reg [255:0] snapshot;integer count_before,n;begin
   count_before=events;
   // The first boundary may adopt the final pre-stop consumed frame. Subsequent
   // frames must freeze: this is the same frame-latched contract as playback.
   frame_without_audio;snapshot=frozen_state(0);
   for(n=0;n<6;n=n+1)begin
    frame_without_audio;
    if(frozen_state(0)!==snapshot)$fatal(1,"%s advanced cue/gesture without consumed PCM",reason);
   end
   if(events!=count_before)$fatal(1,"%s produced an additional onset",reason);
   $display("PASS real tanggu %s: video continues, consumed-sample cue and gesture state freeze",reason);
  end
 endtask
 task restart_stream;begin
  @(negedge clk);checking=0;stream_reset=1;sample_consumed=0;frame_tick=0;
  repeat(4)@(negedge clk);
  if(dut.cue_index!=0 || dut.window_sample!=0 || dut.stroke_count!=0 ||
     dut.hit_pending || dut.drum_left_age!=63 || dut.drum_right_age!=63 ||
     drum_offset!=15 || drum_right_offset!=15)
   $fatal(1,"stream_reset did not restore initial real-drum cue/gesture state");
  events=0;last_position=-1;minimum_delay=800;maximum_delay=0;
  for(k=0;k<512;k=k+1)seen_window[k]=0;
  stream_reset=0;checking=1;
 end endtask
 initial begin
  $readmemh("rtl/heritage_cue.hex",reference_cue);
  for(k=0;k<512;k=k+1)begin
   seen_window[k]=0;
   if(reference_cue[1536+k][3])begin
    expected_window[expected_events]=k;expected_events=expected_events+1;
   end
  end
  if(expected_events!=70)$fatal(1,"real TANGGU cue changed: expected 70 onsets, got %0d",expected_events);
  repeat(5)@(negedge clk);rst=0;restart_stream;
  for(position=0;position<768000;position=position+1)begin
   consume(position);
   if(position==79999)stopped_audio("pause");
   if(position==383999)stopped_audio("underflow");
  end
  if(events!=expected_events)$fatal(1,"16-second real cue lost onset strokes: %0d/%0d",events,expected_events);
  for(k=0;k<expected_events;k=k+1)
   if(!seen_window[expected_window[k]])$fatal(1,"missing real onset window %0d",expected_window[k]);
  $display("PASS real tanggu full clip: 768000 consumed samples, 512 windows, %0d/%0d onset strokes exactly once; digital frame wait min=%0d max=%0d samples (%0d..%0d us at 48 kHz)",
    events,expected_events,minimum_delay,maximum_delay,
    minimum_delay*1000000/48000,maximum_delay*1000000/48000);
  restart_stream;
  for(position=0;position<20000;position=position+1)consume(position);
  if(events!=3)$fatal(1,"stream_reset did not replay first three real cue events exactly once");
  $display("PASS real tanggu restart: first three recording-derived onset strokes replayed from sample zero");
  $display("PASS real tanggu digital cue-to-motion only; excludes DAC, loudspeaker, LCD and source-onset extraction latency");
  $finish;
 end
 initial begin #30000000;$fatal(1,"real tanggu synchronization timeout position=%0d events=%0d",sample_position,events);end
endmodule
