// Keep screen coordinates alongside source-coordinate picture overlays.
module video_xy_delay #(parameter STAGES=9)(
 input clk,input rst,input [10:0] x,input [10:0] y,
 output [10:0] out_x,output [10:0] out_y
);
 reg [10:0] xd[0:STAGES-1],yd[0:STAGES-1];
 integer i;
 always @(posedge clk or posedge rst)begin
  if(rst)for(i=0;i<STAGES;i=i+1)begin xd[i]<=0;yd[i]<=0;end
  else begin
   xd[0]<=x;yd[0]<=y;
   for(i=1;i<STAGES;i=i+1)begin xd[i]<=xd[i-1];yd[i]<=yd[i-1];end
  end
 end
 assign out_x=xd[STAGES-1];assign out_y=yd[STAGES-1];
endmodule
