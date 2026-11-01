// Unpack two RGB565 pixels from each 32-bit SDRAM FIFO word. The FIFO uses a
// synchronous NOREG output, matching the coordinate delay used here.
module video_pixels_rgb565(
 input clk,input rst,input active,input image_active,input display_enabled,
 input [10:0] x,input [10:0] y,input [31:0] read_data,
 output read_en,output reg valid,output reg [10:0] px,output reg [10:0] py,
 output reg [23:0] rgb
);
 reg act_d,img_d;
 reg [10:0] x_d,y_d;
 reg [15:0] low_pixel;
 wire [15:0] selected=x_d[0]?low_pixel:read_data[31:16];
 wire [23:0] expanded={{selected[15:11],selected[15:13]},
                        {selected[10:5],selected[10:9]},
                        {selected[4:0],selected[4:2]}};
 assign read_en=image_active && display_enabled && !x[0];
 always @(posedge clk or posedge rst)begin
  if(rst)begin act_d<=0;img_d<=0;x_d<=0;y_d<=0;low_pixel<=0;
   valid<=0;px<=0;py<=0;rgb<=0;end
  else begin
   act_d<=active;img_d<=image_active && display_enabled;x_d<=x;y_d<=y;
   valid<=act_d;px<=x_d;py<=y_d;
   if(img_d && !x_d[0])low_pixel<=read_data[15:0];
   rgb<=img_d?expanded:24'h101c30;
  end
 end
endmodule
