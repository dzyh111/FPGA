`timescale 1ns/1ps
module tb_audio;
reg clk=0;always #1 clk=~clk;
reg rst=1,mute=0;wire valid,acr,re;wire signed [23:0] l,r,analysis;wire[19:0] n,cts;
wav_audio_player dut(.clk(clk),.rst(rst),.play_enable(1'b1),.mute(mute),
 .stream_reset(1'b0),.sample_total(32'd0),
 .fifo_data(32'h56781234),.fifo_empty(1'b0),.fifo_read(re),.valid(valid),
 .left_data(l),.right_data(r),.analysis_sample(analysis),.acr_valid(acr),.acr_n(n),.acr_cts(cts));
integer cycles=0,samples=0,last_cycle=0,acrs=0;
always @(negedge clk)if(!rst)begin
 cycles=cycles+1;
 if(valid)begin
   if(samples>0 && cycles-last_cycle!=1066 && cycles-last_cycle!=1067)$fatal(1,"sample interval");
   last_cycle=cycles;samples=samples+1;
   if(!re)$fatal(1,"FIFO not consumed");
   if(!mute && (l!==24'h123400 || r!==24'h567800 || analysis!==24'h123400))$fatal(1,"stereo PCM mismatch");
   if(mute && l!==0)$fatal(1,"mute failed");
 end
 if(acr)acrs=acrs+1;
 if(cycles==512000)begin
   if(samples!=480 || acrs!=10 || n!=6144 || cts!=51200)$fatal(1,"audio count %d %d",samples,acrs);
   $display("PASS audio: exact 480 samples/10ms, ACR, stereo WAV PCM and mute");$finish;
 end
end
initial begin #3;rst=0;#600001;mute=1;end
endmodule
