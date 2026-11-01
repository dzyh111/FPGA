`timescale 1ns/1ps
module tb_heritage_ascii;
 reg clk=0;always #5 clk=~clk;
 reg [6:0] code=0;reg [2:0] row=0;
 wire [4:0] pixels;
 reg [34:0] bits;reg [4:0] expected;
 integer c,r;
 `include "font5x7.vh"
 ascii_font_rom dut(.clk(clk),.code(code),.row(row),.pixels(pixels));
 initial begin
  for(c=0;c<128;c=c+1)for(r=0;r<8;r=r+1)begin
   @(negedge clk);code=c;row=r;bits=glyph(c);
   expected=r<7?((bits>>(30-r*5))&31):0;
   @(posedge clk);#1;
   if(pixels!==expected)$fatal(1,"ASCII ROM differs char=%d row=%d",c,r);
  end
  $display("PASS ASCII ROM: all 1024 rows match original font exactly");$finish;
 end
endmodule
