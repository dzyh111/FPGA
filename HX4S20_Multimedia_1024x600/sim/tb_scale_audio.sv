`timescale 1ns/1ps
module tb_scale_audio;
reg clk=0;always #1 clk=~clk;
reg rst=1,play=1,mute=0,empty=0;
wire valid,acr,re;wire signed [23:0] l,r,analysis;wire [19:0] n,cts;
wav_audio_player #(.PIXEL_HZ(48000)) dut(.clk(clk),.rst(rst),.play_enable(play),.mute(mute),
 .stream_reset(1'b0),.sample_total(32'd0),
 .fifo_data(32'h80017fff),.fifo_empty(empty),.fifo_read(re),.valid(valid),
 .left_data(l),.right_data(r),.analysis_sample(analysis),.acr_valid(acr),.acr_n(n),.acr_cts(cts));
integer count=0;
initial begin
 #2.5;rst=0;
end
always @(negedge clk)if(!rst && valid)begin
 count=count+1;
 if(count<4 && (!re || l!==24'h7fff00 || r!==24'h800100))$fatal(1,"PCM read");
 if(count==4)play=0;
 if(count>=5 && count<8 && (re || l!==0 || analysis!==0))$fatal(1,"pause consumed FIFO");
 if(count==8)begin play=1;mute=1;end
 if(count>=9 && count<12 && (!re || l!==0 || analysis!==24'h7fff00))$fatal(1,"mute/analysis");
 if(count==12)begin empty=1;mute=0;end
 if(count>=13 && (re || l!==0) )$fatal(1,"empty handling");
 if(count==16)begin $display("PASS scale_audio: WAV FIFO play, pause, mute, analysis and underflow");$finish;end
end
endmodule
