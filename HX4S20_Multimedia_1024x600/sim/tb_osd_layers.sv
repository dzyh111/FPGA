`timescale 1ns/1ps
module tb_osd_layers;
reg clk=0;always #5 clk=~clk;
reg rst=1,frame=0,aval=0,valid=1;reg [3:0] sw=0;
reg signed [23:0] sample=24'sd2000000;reg [10:0] x=0,y=0;
wire ov,sof,last,mute;wire [23:0] out;
media_osd #(.NOTICE_CYCLES(100)) dut(.clk(clk),.rst(rst),.frame_tick(frame),
 .switches(sw),.state_code(4'd6),.image_index(2'd1),.auto_play(1'b0),
 .audio_valid(aval),.audio_sample(sample),.valid(valid),.x(x),.y(y),.rgb(24'h204060),
 .out_valid(ov),.out_sof(sof),.out_last(last),.out_rgb(out),.mute(mute));
task tick;begin @(negedge clk);end endtask
task frame_pulse;begin frame=1;tick;frame=0;tick;end endtask
task point(input [10:0] px,input [10:0] py);begin x=px;y=py;tick;tick;end endtask
integer i;
initial begin
 repeat(4)tick;rst=0;repeat(4)tick;
 // Fill and publish a positive sample waveform buffer.
 aval=1;for(i=0;i<256;i=i+1)tick;aval=0;frame_pulse;
 sw=4'b0100;repeat(4)tick;frame_pulse;
 point(128,549);if(out!==24'h40ffc0)$fatal(1,"wave trace invisible: %h",out);
 point(128,564);if(out===24'h204060)$fatal(1,"wave alpha panel absent");
 // A known red-stripe location in the generated Anlogic logo.
 point(975,26);if(out===24'h204060)$fatal(1,"logo layer absent");
 // Switch change opens the left parameter panel, then expires.
 sw=4'b1101;repeat(4)tick;frame_pulse;
 point(8,100);if(out===24'h204060)$fatal(1,"side notice absent");
 repeat(110)tick;frame_pulse;point(8,100);if(out!==24'h102030)$fatal(1,"side notice did not expire: %h",out);
 $display("PASS osd_layers: logo, alpha panels, visible waveform and 2-second notice control");$finish;
end
endmodule
