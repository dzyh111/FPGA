`timescale 1ns/1ps
module tb_original_real;
 reg clk=0; always #5 clk=~clk;
 reg rst=1,start=0,go=0,pv=0;
 reg [23:0] pixel=24'h123456;
 wire ready,ov,done,over;
 wire [23:0] rgb;
 bmp_mode_scaler dut(.clk(clk),.rst(rst),.image_start(start),.output_start(go),.output_pause(1'b0),
  .source_width(16'd640),.source_height(16'd480),.mode(2'd1),
  .pixel_valid(pv),.pixel_rgb(pixel),.config_ready(ready),
  .output_valid(ov),.output_rgb(rgb),.output_done(done),.input_overrun(over));
`ifdef SCALER_REFERENCE_CHECK
 wire reference_ov,reference_done,reference_over;
 wire [23:0] reference_rgb;
 bmp_mode_scaler_reference reference(.clk(clk),.rst(rst),.image_start(start),.output_start(go),.output_pause(1'b0),
  .source_width(16'd640),.source_height(16'd480),.mode(2'd1),
  .pixel_valid(pv),.pixel_rgb(pixel),.config_ready(),
  .output_valid(reference_ov),.output_rgb(reference_rgb),.output_done(reference_done),.input_overrun(reference_over));
 always @(negedge clk)if(!rst)begin
  if(ov!==reference_ov || done!==reference_done || over!==reference_over ||
     (ov && rgb!==reference_rgb))$fatal(1,"ORIGINAL differs from legacy RTL");
 end
`endif
 integer n=0,i;
 always @(posedge clk) if(ov) n<=n+1;
 initial begin
  repeat(5) @(negedge clk); rst=0;
  start=1; @(negedge clk); start=0;
  wait(ready); @(negedge clk); go=1; @(negedge clk); go=0;
  for(i=0;i<640*480;i=i+1)begin
   repeat(95) @(negedge clk);
   pv=1; @(negedge clk); pv=0;
  end
  // done and the final registered valid are asserted on the same edge.
  // Give the posedge monitor one more edge to count that final output.
  wait(done); repeat(2) @(negedge clk);
  if(over) $fatal(1,"ORIGINAL input overrun");
  if(n!=1024*600) $fatal(1,"ORIGINAL pixels %0d",n);
  $display("PASS ORIGINAL real 640x480, 96 clocks/pixel, %0d output pixels",n);
  $finish;
 end
 initial begin #400000000;$fatal(1,"ORIGINAL stalled: out_y=%0d src_y=%0d input_y=%0d",dut.out_y,dut.source_y,dut.in_y); end
endmodule
