`timescale 1ns/1ps
module tb_adjust_ranges;
 reg clk=0;always #5 clk=~clk;
 media_osd dut(.clk(clk),.rst(1'b1));
 function [7:0] reference_adjust;
  input [7:0] value;input [2:0] bri,con;
  reg signed [11:0] t,d,q;
  begin
   t=$signed({1'b0,value});
   case(bri)
    0:t=t>>>1;1:t=t-(t>>>2);3:t=t+(t>>>2);4:t=t+(t>>>1);default:t=t;
   endcase
   if(t<0)t=0;else if(t>255)t=255;
   d=t-128;
   case(con)
    0:q=(d>>>1)+128;1:q=d-(d>>>2)+128;3:q=d+(d>>>2)+128;
    4:q=d+(d>>>1)+128;default:q=d+128;
   endcase
   if(q<0)reference_adjust=0;else if(q>255)reference_adjust=255;
   else reference_adjust=q[7:0];
  end
 endfunction
 integer value,bri,con;
 initial begin
  for(bri=0;bri<8;bri=bri+1)for(con=0;con<8;con=con+1)
   for(value=0;value<256;value=value+1)
    if(dut.adjust_channel(value,bri,con)!==reference_adjust(value,bri,con))
     $fatal(1,"brightness/contrast differs value=%d bri=%d con=%d",value,bri,con);
  $display("PASS adjustment: all 16384 combinations identical after width reduction");$finish;
 end
endmodule
