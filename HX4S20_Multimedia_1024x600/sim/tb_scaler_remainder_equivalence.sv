`timescale 1ns/1ps
// Check the actual new/old combinational nodes, including the full 17-bit
// sum range (a superset of reachable 16-bit remainder + 11-bit dimension).
module tb_scaler_remainder_equivalence;
 reg [16:0] sx=0,sy=0;
 reg [11:0] dx=0,dy=0;
 bmp_mode_scaler dut(.clk(1'b0),.rst(1'b1),.image_start(1'b0),
  .output_start(1'b0),.output_pause(1'b0),.source_width(16'd1),
  .source_height(16'd1),.mode(2'd1),.pixel_valid(1'b0),.pixel_rgb(24'd0));
 bmp_mode_scaler_preparallel_ref reference(.clk(1'b0),.rst(1'b1),.image_start(1'b0),
  .output_start(1'b0),.output_pause(1'b0),.source_width(16'd1),
  .source_height(16'd1),.mode(2'd1),.pixel_valid(1'b0),.pixel_rgb(24'd0));
 integer d,k,r,checks=0;
 integer samples[0:17];
 integer ex,ey,rx,ry;
 task check;
 begin
  #1;
  ex=(sx>=2*dx)?2:((sx>=dx)?1:0);
  ey=(sy>=2*dy)?2:((sy>=dy)?1:0);
  rx=sx-ex*dx;ry=sy-ey*dy;
  if(dut.x_step!==reference.x_step || dut.y_step!==reference.y_step ||
     dut.x_rem_next!==reference.x_rem_next || dut.y_rem_next!==reference.y_rem_next ||
     dut.x_step!==ex[1:0] || dut.y_step!==ey[1:0] ||
     dut.x_rem_next!==rx[16:0] || dut.y_rem_next!==ry[16:0])
   $fatal(1,"remainder mismatch sx=%0d dx=%0d sy=%0d dy=%0d",sx,dx,sy,dy);
  checks=checks+2;
 end endtask
 initial begin
  force dut.x_sum=sx;force reference.x_sum=sx;
  force dut.y_sum=sy;force reference.y_sum=sy;
  force dut.virtual_w=dx;force reference.virtual_w=dx;
  force dut.virtual_h=dy;force reference.virtual_h=dy;
  for(d=0;d<4096;d=d+1)begin
   samples[0]=0;samples[1]=1;samples[2]=d-1;samples[3]=d;
   samples[4]=d+1;samples[5]=2*d-1;samples[6]=2*d;
   samples[7]=2*d+1;samples[8]=3*d-1;samples[9]=3*d;
   samples[10]=3*d+1;samples[11]=65534;samples[12]=65535;
   samples[13]=65536;samples[14]=67581;samples[15]=67582;
   samples[16]=131070;samples[17]=131071;
   dx=d;dy=d;
   for(k=0;k<18;k=k+1)begin
    sx=samples[k]<0?0:samples[k];sy=131071-sx;check;
   end
  end
  for(r=0;r<200000;r=r+1)begin
   sx=$random;sy=$random;dx=$random;dy=$random;check;
  end
  $display("PASS scaler parallel remainder: %0d axis cases, all 4096 divisors, full 17-bit boundaries and random; zero and >=3D retained",checks);
  $finish;
 end
endmodule
