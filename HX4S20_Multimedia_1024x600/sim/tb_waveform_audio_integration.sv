`timescale 1ns/1ps
// Integration proof using the unmodified production WAV player and its real
// 51.2 MHz / 48 kHz fractional sample clock, not a hand-built sample pulse.
module tb_waveform_audio_integration;
 reg clk=0;always #1 clk=~clk;
 reg rst=1,play=0,mute=0,empty=0,stream_reset=0,frame_tick=0;
 reg [31:0] fifo_data=32'hc0004000;
 wire fifo_read,audio_valid,consumed,acr,loop_toggle;
 wire signed [23:0] left_data,right_data,analysis;
 wire [31:0] position;wire [19:0] n,cts;
 reg pixel_valid=0;reg [10:0] x=0,y=552;
 wire line_hit,halo_hit;wire [23:0] line_rgb;
 wav_audio_player player(.clk(clk),.rst(rst),.play_enable(play),.mute(mute),
  .stream_reset(stream_reset),.sample_total(32'd8192),
  .fifo_data(fifo_data),.fifo_empty(empty),.fifo_read(fifo_read),.valid(audio_valid),
  .left_data(left_data),.right_data(right_data),.analysis_sample(analysis),
  .sample_consumed(consumed),.sample_position(position),.loop_toggle(loop_toggle),
  .acr_valid(acr),.acr_n(n),.acr_cts(cts));
 audio_waveform wave(.clk(clk),.rst(rst),.stream_reset(stream_reset),
  .frame_tick(frame_tick),.sample_valid(consumed),.sample(analysis),.scene(3'd1),
  .valid(pixel_valid),.x(x),.y(y),.line_hit(line_hit),.halo_hit(halo_hit),.line_rgb(line_rgb));

 integer cycles=0,ticks=0,total_consumed=0,last_tick=-1;
 integer pause_ticks=0,underflow_ticks=0,mute_samples=0,commits=0;
 always @(negedge clk)begin
  if(!rst)begin
   cycles=cycles+1;
   if(audio_valid)begin
    ticks=ticks+1;
    if(last_tick>=0&&cycles-last_tick!=1066&&cycles-last_tick!=1067)
      $fatal(1,"production sample clock interval %0d",cycles-last_tick);
    last_tick=cycles;
    if(!play)pause_ticks=pause_ticks+1;
    else if(empty)underflow_ticks=underflow_ticks+1;
    if(consumed)begin
     total_consumed=total_consumed+1;
     if(!fifo_read||!play||empty||stream_reset)$fatal(1,"invalid PCM consumption");
     if(analysis!=={fifo_data[15:0],8'h00})$fatal(1,"analysis PCM is not pre-mute left PCM");
     if(mute)begin
      mute_samples=mute_samples+1;
      if(left_data!==0||right_data!==0)$fatal(1,"mute leaked audio");
     end else if(left_data!=={fifo_data[15:0],8'h00}||right_data!=={fifo_data[31:16],8'h00})
       $fatal(1,"stereo PCM output mismatch");
    end else if(fifo_read||left_data!==0||right_data!==0||analysis!==0)
      $fatal(1,"pause/underflow tick did not carry zero audio without consumption");
   end else if(consumed||fifo_read)$fatal(1,"consumption without audio tick");
  end
 end
 task idle_clocks(input integer count);
  begin repeat(count)@(negedge clk);end
 endtask
 task stop_and_flush;
  begin @(negedge clk);play=0;idle_clocks(5);end
 endtask
 task commit_and_check(input integer amplitude);
  integer c;
  begin
   if(!wave.capture_pending)$fatal(1,"commit requested without a complete PCM snapshot");
   @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;idle_clocks(4);
   if(!wave.display_ready||wave.capture_pending)$fatal(1,"waveform bank commit failed");
   for(c=0;c<256;c=c+1)begin
    if($signed(wave.wave_ram[{wave.display_bank,c[7:0]}][13:7])!==amplitude ||
       $signed(wave.wave_ram[{wave.display_bank,c[7:0]}][6:0])!==amplitude)
      $fatal(1,"PCM waveform bank incorrect at %0d, expected %0d",c,amplitude);
   end
   commits=commits+1;
  end
 endtask
 task probe(input integer px,py,expected_core);
  begin
   @(negedge clk);pixel_valid=1;x=px;y=py;idle_clocks(5);
   if(line_hit!==expected_core[0])$fatal(1,"wave trace pixel %0d,%0d expected %0d",px,py,expected_core);
   pixel_valid=0;idle_clocks(5);
  end
 endtask
 integer before_consumed,before_ticks,target;
 reg frozen_bank;
 reg [8:0] frozen_capture;
 initial begin
  idle_clocks(4);rst=0;@(negedge clk);play=1;
  wait(wave.capture_pending);stop_and_flush;
  if(wave.display_ready)$fatal(1,"PCM bank visible before its frame boundary");
  commit_and_check(20);probe(0,532,1);probe(1023,532,1);probe(0,552,0);

  // HDMI silence packets still exist while paused; they must not enter the
  // waveform, otherwise the trace would incorrectly decay to a flat line.
  before_consumed=total_consumed;before_ticks=ticks;
  frozen_bank=wave.display_bank;frozen_capture={wave.write_column,wave.sample_phase};
  idle_clocks(48000);
  if(ticks-before_ticks<40||total_consumed!=before_consumed||position!=before_consumed)
   $fatal(1,"pause semantics: ticks=%0d consumed=%0d position=%0d",ticks-before_ticks,total_consumed-before_consumed,position);
  if(wave.display_bank!==frozen_bank||{wave.write_column,wave.sample_phase}!==frozen_capture)
   $fatal(1,"paused waveform advanced from HDMI packet ticks");
  probe(1023,532,1);

  // Muting only affects HDMI samples, not the actual PCM consumption clock
  // or analysis data: the next captured trace must contain negative audio.
  @(negedge clk);fifo_data=32'h2000c000;mute=1;play=1;
  wait(wave.capture_pending);stop_and_flush;commit_and_check(-20);
  probe(0,572,1);probe(1023,572,1);probe(0,552,0);
  if(mute_samples<512)$fatal(1,"mute was not exercised for a complete capture");

  // FIFO starvation behaves like a pause, even though play remains selected.
  @(negedge clk);empty=1;play=1;
  before_consumed=total_consumed;before_ticks=ticks;
  frozen_bank=wave.display_bank;frozen_capture={wave.write_column,wave.sample_phase};
  idle_clocks(48000);
  if(ticks-before_ticks<40||total_consumed!=before_consumed||underflow_ticks<40)
   $fatal(1,"underflow did not preserve the production sample/packet distinction");
  if(wave.display_bank!==frozen_bank||{wave.write_column,wave.sample_phase}!==frozen_capture)
   $fatal(1,"FIFO underflow altered the waveform");
  probe(0,572,1);

  // Scene reset during an odd-sized partial capture must reset the player
  // sample position and discard both old trace data and the partial pair.
  @(negedge clk);empty=0;fifo_data=32'h10002000;
  target=total_consumed+17;wait(total_consumed>=target);stop_and_flush;
  if(wave.sample_phase!==1||wave.write_column!=8)$fatal(1,"expected an odd partial capture");
  @(negedge clk);stream_reset=1;idle_clocks(4);
  if(position!=0||wave.display_ready||wave.capture_pending||wave.sample_phase||wave.write_column!=0)
   $fatal(1,"scene reset did not clear player and waveform together");
  @(negedge clk);stream_reset=0;idle_clocks(4);
  probe(0,552,1);probe(0,572,0);
  @(negedge clk);fifo_data=0;mute=0;play=1;
  wait(wave.capture_pending);stop_and_flush;commit_and_check(0);
  probe(0,552,1);probe(1023,552,1);probe(1023,532,0);
  if(commits!=3||pause_ticks<40||underflow_ticks<40||n!=6144||cts!=51200)
   $fatal(1,"insufficient actual WAV integration coverage");
  $display("PASS waveform/WAV integration: %0d consumed samples, %0d HDMI ticks, %0d muted samples, %0d pause/%0d underflow ticks; real 1066/1067-clock sample spacing, mute-before-analysis, frozen pause/underflow, scene-reset and coherent frame commits",total_consumed,ticks,mute_samples,pause_ticks,underflow_ticks);
  $finish;
 end
 initial begin #10000000;$fatal(1,"waveform/WAV integration timeout");end
endmodule
