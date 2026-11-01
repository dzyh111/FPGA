`timescale 1ns/1ps
module tb_notice;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg [3:0] sw=0;integer n=0;
wire mute,ov,sof,last;wire [23:0] rgb;
media_osd #(.NOTICE_CYCLES(100)) dut(.clk(clk),.rst(rst),.frame_tick(1'b1),
 .switches(sw),.state_code(4'd6),.image_index(2'd0),.auto_play(1'b0),
 .audio_valid(1'b0),.audio_sample(24'd0),.valid(1'b1),.x(11'd16),.y(11'd12),
 .rgb(24'h123456),.out_valid(ov),.out_sof(sof),.out_last(last),.out_rgb(rgb),.mute(mute));
initial begin
 #21;rst=0;repeat(5)@(negedge clk);
 if(dut.notice_visible)$fatal(1,"startup notice");
 sw=1;wait(dut.notice_visible);@(negedge clk);
 repeat(60)@(negedge clk);
 if(!dut.notice_visible)$fatal(1,"early expiry");
 sw=9;repeat(5)@(negedge clk);
 if(!mute)$fatal(1,"mute control");
 repeat(60)@(negedge clk);
 if(!dut.notice_visible)$fatal(1,"timer did not restart");
 repeat(45)@(negedge clk);
 if(dut.notice_visible)$fatal(1,"notice did not expire");
 $display("PASS notice: restart on change, expiry, mute");$finish;
end
endmodule
