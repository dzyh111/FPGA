`timescale 1ns/1ps
module tb_audio_spectrum_equivalence;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,sample_valid=0;
 reg signed [23:0] sample=0;
 wire [127:0] levels_ref,levels_new;
 wire valid_ref,valid_new;
 audio_spectrum_reference reference_dut(.clk(clk),.rst(rst),.sample_valid(sample_valid),.sample(sample),
  .levels(levels_ref),.levels_valid(valid_ref));
 audio_spectrum candidate_dut(.clk(clk),.rst(rst),.sample_valid(sample_valid),.sample(sample),
  .levels(levels_new),.levels_valid(valid_new));
 integer cycle_count=0,last_sample_cycle=-100000,accepted_samples=0;
 integer ref_count=0,new_count=0,total_matches=0,total_samples=0;
 integer segments=0,reset_cancellations=0,max_delay=0;
 integer ref_time[0:127];reg [127:0] ref_value[0:127];
 reg ref_previous_valid=0,new_previous_valid=0;
 always @(posedge clk)begin
  #1;cycle_count=cycle_count+1;
  if(rst)begin
   ref_count=0;new_count=0;accepted_samples=0;last_sample_cycle=-100000;
   ref_previous_valid=0;new_previous_valid=0;
  end else begin
   if(sample_valid)begin
    if(cycle_count-last_sample_cycle<65)$fatal(1,"spectrum sample interval below65 clocks");
    last_sample_cycle=cycle_count;accepted_samples=accepted_samples+1;total_samples=total_samples+1;
   end
   if(valid_ref)begin
    if(ref_previous_valid)$fatal(1,"old output event is wider than one clock");
    if(ref_count>=128)$fatal(1,"reference queue capacity");
    ref_time[ref_count]=cycle_count;ref_value[ref_count]=levels_ref;ref_count=ref_count+1;
   end
   if(valid_new)begin
    if(new_previous_valid)$fatal(1,"new output event is wider than one clock");
    if(new_count>=ref_count)$fatal(1,"new output has no prior reference event");
    if(levels_new!==ref_value[new_count])
     $fatal(1,"segment%0d event%0d full128bits differ old=%032h new=%032h",segments,new_count,ref_value[new_count],levels_new);
    if(cycle_count-ref_time[new_count]!=16)
     $fatal(1,"segment%0d event%0d latency=%0d expected16",segments,new_count,cycle_count-ref_time[new_count]);
    if(cycle_count-ref_time[new_count]>max_delay)max_delay=cycle_count-ref_time[new_count];
    new_count=new_count+1;total_matches=total_matches+1;
   end
   ref_previous_valid=valid_ref;new_previous_valid=valid_new;
  end
 end
 task reset_epoch;
  begin
   @(negedge clk);rst=1;sample_valid=0;sample=0;
   repeat(4)@(negedge clk);
   if(levels_ref!==0||levels_new!==0||valid_ref||valid_new)$fatal(1,"reset did not clear levels/valid");
   rst=0;repeat(2)@(negedge clk);
  end
 endtask
 task send_sample(input signed [23:0] value,input integer gap);
  begin
   @(negedge clk);
   if(reference_dut.state!=0||candidate_dut.state!=0)$fatal(1,"sample submitted while a bin engine is busy");
   sample=value;sample_valid=1;
   @(negedge clk);sample_valid=0;
   repeat(gap-2)@(negedge clk);
  end
 endtask
 task check_epoch(input integer expected_samples,input integer expect_silence);
  begin
   repeat(80)@(negedge clk);
   if(accepted_samples!=expected_samples||ref_count!=expected_samples/256||new_count!=expected_samples/256)
    $fatal(1,"segment%0d count mismatch samples%0d/%0d events%0d/%0d expected%0d",segments,accepted_samples,expected_samples,
      ref_count,new_count,expected_samples/256);
   if(levels_ref!==levels_new)$fatal(1,"idle final levels differ");
   if(expect_silence&&(levels_ref!==0||levels_new!==0))$fatal(1,"true silence invented spectral energy");
   segments=segments+1;
  end
 endtask
 function automatic integer bin_step(input integer bin_index);
  begin case(bin_index)
   0:bin_step=1;1:bin_step=2;2:bin_step=3;3:bin_step=4;
   4:bin_step=5;5:bin_step=6;6:bin_step=8;7:bin_step=10;
   8:bin_step=12;9:bin_step=15;10:bin_step=19;11:bin_step=24;
   12:bin_step=30;13:bin_step=38;14:bin_step=48;default:bin_step=64;
  endcase end
 endfunction
 function automatic signed [23:0] tone(input integer n,input integer k,input integer amplitude);
  real wave;begin
   wave=amplitude*$sin(6.28318530717958647692*k*n/256.0);tone=$rtoi(wave);
  end
 endfunction
 function automatic signed [23:0] mixed_tone(input integer n);
  real wave;integer k;begin
   wave=0.0;
   for(k=0;k<16;k=k+1)wave=wave+270000.0*$sin(6.28318530717958647692*bin_step(k)*n/256.0+0.23*k);
   if(wave>8388607.0)wave=8388607.0;if(wave< -8388608.0)wave= -8388608.0;
   mixed_tone=$rtoi(wave);
  end
 endfunction
 task cancel_final_sample(input integer clocks_after_accept);
  integer n;begin
   reset_epoch;
   for(n=0;n<255;n=n+1)send_sample(tone(n,19,4194304),65);
   @(negedge clk);sample=tone(255,19,4194304);sample_valid=1;
   @(negedge clk);sample_valid=0;
   repeat(clocks_after_accept-1)@(negedge clk);
   rst=1;
   repeat(4)@(negedge clk);rst=0;
   repeat(100)begin
    @(negedge clk);
    if(valid_ref||valid_new||levels_ref!==0||levels_new!==0||
       reference_dut.state!=0||candidate_dut.state!=0||reference_dut.count!=0||candidate_dut.count!=0)
      $fatal(1,"reset cancellation leaked work at delay%0d",clocks_after_accept);
   end
   reset_cancellations=reset_cancellations+1;
   // BRAM deliberately has no reset: following samples must overwrite old sums.
   for(n=0;n<512;n=n+1)send_sample(tone(n,48,1048576),65);
   check_epoch(512,0);
  end
 endtask
 integer n,k,amplitude,gap,seed=32'h6412a8ce,discard;
 reg signed [23:0] random_pcm;
 initial begin
  discard=$urandom(seed);
  reset_epoch;
  for(n=0;n<1024;n=n+1)send_sample(24'sd0,65);
  check_epoch(1024,1);
  reset_epoch;
  for(n=0;n<1024;n=n+1)send_sample(n[0]?24'sh800000:24'sh7fffff,65);
  check_epoch(1024,0);
  reset_epoch;
  for(n=0;n<2048;n=n+1)begin
   random_pcm=$urandom;gap=$urandom_range(65,83);send_sample(random_pcm,gap);
  end
  check_epoch(2048,0);
  for(k=0;k<16;k=k+1)begin
   reset_epoch;
   case(k%6)
    0:amplitude=4096;1:amplitude=32768;2:amplitude=131072;
    3:amplitude=1048576;4:amplitude=4194304;default:amplitude=8000000;
   endcase
   for(n=0;n<512;n=n+1)send_sample(tone(n,bin_step(k),amplitude),65);
   check_epoch(512,0);
  end
  reset_epoch;
  for(n=0;n<1024;n=n+1)send_sample(mixed_tone(n),65);
  check_epoch(1024,0);
  reset_epoch;
  for(n=0;n<512;n=n+1)send_sample(24'sh123456,65);
  check_epoch(512,0);
  // 51.2MHz/48kHz is 1066+2/3 clocks/sample, exercising both NCO gaps.
  reset_epoch;
  for(n=0;n<768;n=n+1)begin random_pcm=$urandom;send_sample(random_pcm,1066+(n%3!=0));end
  check_epoch(768,0);
  reset_epoch;
  for(n=0;n<512;n=n+1)send_sample(mixed_tone(n),1066+(n%3!=0));
  check_epoch(512,0);
  cancel_final_sample(1);cancel_final_sample(2);cancel_final_sample(3);cancel_final_sample(4);
  cancel_final_sample(31);cancel_final_sample(47);cancel_final_sample(48);cancel_final_sample(49);cancel_final_sample(63);
  $display("PASS spectrum equivalence: segments=%0d matched_full128bit_events=%0d samples=%0d fixed_delay=%0d reset_cancellations=%0d; 16exactbins/multitone/random/extremes/silence; gaps65and1066/1067",segments,total_matches,total_samples,max_delay,reset_cancellations);
  $finish;
 end
 initial begin #100000000;$fatal(1,"spectrum equivalence timeout");end
endmodule
