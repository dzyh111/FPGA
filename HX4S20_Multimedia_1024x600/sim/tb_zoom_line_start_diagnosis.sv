`timescale 1ns/1ps
`include "display_config.vh"
// Reproduce the RELEASED top-level expression, not the isolated zoom fixture.
module tb_zoom_line_start_diagnosis;
 reg clk=0; always #5 clk=~clk;
 reg rst=1;
 wire [10:0] x,y;
 wire tick,active,image_active;
 video_scan #(.IMG_W(1024),.IMG_H(600)) scan(
  .clk(clk),.rst(rst),.commit_toggle(1'b0),.commit_index(2'd0),
  .commit_cover(1'b0),.blank_toggle(1'b0),.read_req_ack(1'b0),
  .frame_tick(tick),.active(active),.image_active(image_active),.x(x),.y(y));
 wire released_line_start=x==(11'd2048-(`H_SYNC+`H_BP));
 integer starts=0,expected_starts=0,wrapped_starts=0;
 always @(posedge clk)if(!rst)begin
  if(released_line_start)starts=starts+1;
  if(scan.hc==0)expected_starts=expected_starts+1;
  if(x==11'd1888)wrapped_starts=wrapped_starts+1;
 end
 initial begin
  repeat(4)@(negedge clk);rst=0;
  repeat(1344*4)@(negedge clk);
  $display("Released line-start pulses=%0d, actual line boundaries=%0d, wrapped x=1888 pulses=%0d",starts,expected_starts,wrapped_starts);
  if(starts!=0 || expected_starts!=4 || wrapped_starts!=4)$fatal(1,"Diagnosis did not reproduce expected width truncation");
  $display("CONFIRMED: released top never resets zoom row state; 11'd2048 is truncated, while prior isolated test used hc==0");
  $finish;
 end
endmodule
