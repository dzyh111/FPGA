// Match the supplied NOREG synchronous-read FIFO: request at T, data after T,
// capture at T+1. Coordinates and valid flags follow the same two-stage pipeline.
module video_pixels(
    input clk,input rst,input active,input image_active,input display_enabled,
    input [10:0] x,input [10:0] y,input [23:0] read_data,
    output read_en,output reg valid,output reg [10:0] px,output reg [10:0] py,
    output reg [23:0] rgb
);
    reg act_d,img_d;
    reg [10:0] x_d,y_d;
    assign read_en=image_active && display_enabled;
    always @(posedge clk or posedge rst) begin
        if(rst) begin act_d<=0; img_d<=0; valid<=0; x_d<=0; y_d<=0; px<=0; py<=0; rgb<=0; end
        else begin
            act_d<=active; img_d<=image_active && display_enabled; x_d<=x; y_d<=y;
            valid<=act_d; px<=x_d; py<=y_d;
            rgb<=img_d ? read_data : 24'h101c30;
        end
    end
endmodule
