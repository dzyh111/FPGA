module rgb565_packer(
 input clk,input rst,input clear,input valid,input [23:0] rgb,
 output reg write_en,output reg [31:0] write_data,output reg half_pending
);
 reg [15:0] first;
 reg [9:0] pixel_x;
 reg [1:0] pixel_y;
 function [3:0] bayer4;
 input [1:0] x,y;
 begin case({y,x})
  4'h0:bayer4=0; 4'h1:bayer4=8; 4'h2:bayer4=2; 4'h3:bayer4=10;
  4'h4:bayer4=12;4'h5:bayer4=4; 4'h6:bayer4=14;4'h7:bayer4=6;
  4'h8:bayer4=3; 4'h9:bayer4=11;4'ha:bayer4=1; 4'hb:bayer4=9;
  4'hc:bayer4=15;4'hd:bayer4=7; 4'he:bayer4=13;default:bayer4=5;
 endcase end
 endfunction
 wire [3:0] dither=bayer4(pixel_x[1:0],pixel_y);
 wire [8:0] red_sum={1'b0,rgb[23:16]}+{6'b0,dither[3:1]};
 wire [8:0] green_sum={1'b0,rgb[15:8]}+{7'b0,dither[3:2]};
 wire [8:0] blue_sum={1'b0,rgb[7:0]}+{6'b0,dither[3:1]};
 wire [4:0] red5=red_sum[8]?5'h1f:red_sum[7:3];
 wire [5:0] green6=green_sum[8]?6'h3f:green_sum[7:2];
 wire [4:0] blue5=blue_sum[8]?5'h1f:blue_sum[7:3];
 wire [15:0] pixel565={red5,green6,blue5};
 always @(posedge clk or posedge rst)begin
  if(rst)begin first<=0;write_en<=0;write_data<=0;half_pending<=0;pixel_x<=0;pixel_y<=0;end
  else begin
   write_en<=0;
   if(clear)begin half_pending<=0;pixel_x<=0;pixel_y<=0;end
   else if(valid)begin
    if(!half_pending)begin first<=pixel565;half_pending<=1;end
    else begin write_data<={first,pixel565};write_en<=1;half_pending<=0;end
    if(pixel_x==1023)begin pixel_x<=0;pixel_y<=pixel_y+1'b1;end
    else pixel_x<=pixel_x+1'b1;
   end
  end
 end
endmodule
