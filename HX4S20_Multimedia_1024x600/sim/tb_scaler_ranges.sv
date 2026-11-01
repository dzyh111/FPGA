`timescale 1ns/1ps
module tb_scaler_ranges;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0;
 reg [15:0] width=1,height=1;
 reg [1:0] mode=1;
 wire ready,reference_ready;
 bmp_mode_scaler dut(.clk(clk),.rst(rst),.image_start(start),.output_start(1'b0),
  .output_pause(1'b0),.source_width(width),.source_height(height),.mode(mode),
  .pixel_valid(1'b0),.pixel_rgb(24'd0),.config_ready(ready));
 bmp_mode_scaler_reference reference(.clk(clk),.rst(rst),.image_start(start),.output_start(1'b0),
  .output_pause(1'b0),.source_width(width),.source_height(height),.mode(mode),
  .pixel_valid(1'b0),.pixel_rgb(24'd0),.config_ready(reference_ready));
 integer dims[0:18];integer wi,hi,mi,r,tests=0;
 task check_geometry;
 begin
  @(negedge clk);start=1;
  @(negedge clk);start=0;
  wait(ready && reference_ready);@(negedge clk);
  if(dut.virtual_w!==reference.virtual_w || dut.virtual_h!==reference.virtual_h ||
     dut.x_first!==reference.x_first || dut.x_last!==reference.x_last ||
     dut.y_first!==reference.y_first || dut.y_last!==reference.y_last ||
     dut.x_base!==reference.x_base || dut.y_base!==reference.y_base ||
     dut.x_rem_start!==reference.x_rem_start || dut.y_rem!==reference.y_rem)
   $fatal(1,"geometry mismatch %0dx%0d mode %0d",width,height,mode);
  tests=tests+1;
 end
 endtask
 initial begin
  dims[0]=1;dims[1]=2;dims[2]=3;dims[3]=4;dims[4]=7;dims[5]=41;
  dims[6]=82;dims[7]=256;dims[8]=511;dims[9]=512;dims[10]=513;
  dims[11]=519;dims[12]=599;dims[13]=600;dims[14]=601;dims[15]=767;
  dims[16]=768;dims[17]=1023;dims[18]=1024;
  repeat(4)@(negedge clk);rst=0;
  for(wi=0;wi<19;wi=wi+1)for(hi=0;hi<19;hi=hi+1)
   for(mi=0;mi<4;mi=mi+1)begin
    width=dims[wi];height=dims[hi];mode=mi;check_geometry;
   end
  for(r=0;r<2048;r=r+1)begin
   width=($random&1023)+1;height=($random&1023)+1;mode=r&3;check_geometry;
  end
  $display("PASS scaler ranges: %0d geometries equal legacy (all modes, extreme aspect, random)",tests);
  $finish;
 end
 initial begin #100000000;$fatal(1,"scaler geometry timeout");end
endmodule

module tb_scaler_divider;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0;
 reg [20:0] numerator;
 reg [11:0] denominator;
 wire busy,done;wire [20:0] quotient;wire [11:0] remainder;
 scaler_divider_21_12 dut(clk,rst,start,numerator,denominator,busy,done,quotient,remainder);
 integer den,ni,tests=0;reg [20:0] nums[0:5];
 task check_divide;
 begin
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(done);@(negedge clk);
  if(denominator==0)begin
   if(quotient!==0 || remainder!==0)$fatal(1,"zero denominator");
  end else if(quotient!==numerator/denominator || remainder!==numerator%denominator)
   $fatal(1,"divide mismatch %0d / %0d = %0d r%0d",numerator,denominator,quotient,remainder);
  tests=tests+1;
 end
 endtask
 initial begin
  nums[0]=0;nums[1]=1;nums[2]=614400;nums[3]=1048576;
  nums[4]=1788928;nums[5]=2097151;
  repeat(4)@(negedge clk);rst=0;
  for(den=0;den<4096;den=den+1)for(ni=0;ni<6;ni=ni+1)begin
   denominator=den;numerator=nums[ni];check_divide;
  end
  $display("PASS scaler divider: %0d boundary divisions, every 12-bit divisor",tests);
  $finish;
 end
 initial begin #100000000;$fatal(1,"divider timeout");end
endmodule
