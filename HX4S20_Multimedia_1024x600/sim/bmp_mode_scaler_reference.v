// Resource-light 1024x600 scaler for TF-card BMP images.
// Input and output are both bottom-up. ORIGINAL centres one source pixel per
// output pixel, FIT preserves the whole image, and FILL crops symmetrically.
// Nearest-neighbour sampling keeps the run-time datapath to two line RAMs and
// one small control state machine; division is reused only while configuring.
module bmp_mode_scaler_reference(
 input clk,input rst,input image_start,input output_start,input output_pause,
 input [15:0] source_width,input [15:0] source_height,input [1:0] mode,
 input pixel_valid,input [23:0] pixel_rgb,
 output reg config_ready,output wire input_start_ready,
 output reg output_valid,output reg [23:0] output_rgb,
 output reg output_done,output reg input_overrun
);
 localparam SCREEN_W=1024,SCREEN_H=600;
 localparam C_IDLE=0,C_SIZE_WAIT=1,C_X_START=2,C_X_WAIT=3,
            C_Y_START=4,C_Y_WAIT=5,C_READY=6;
 localparam G_IDLE=0,G_ROW=1,G_WAIT_LINE=2,G_READ=3,G_PIXEL=4;

 reg [2:0] cstate,gstate;
 reg [15:0] src_w,src_h;
 reg [11:0] virtual_w,virtual_h,x_first,x_last,y_first,y_last;
 reg [15:0] x_base,y_base,x_rem_start,y_rem;
 reg [11:0] crop_x,crop_y;
 reg [31:0] div_num,div_den;
 reg div_start;
 wire div_busy,div_done;
 wire [31:0] div_q,div_r;
 wire [31:0] aspect_w=source_width*16'd600;
 wire [31:0] aspect_h=source_height<<10;
 reg size_is_width;

 u32_divider_reference u_div(.clk(clk),.rst(rst),.start(div_start),.dividend(div_num),
  .divisor(div_den),.busy(div_busy),.done(div_done),.quotient(div_q),.remainder(div_r));

 reg input_bank;
 reg [15:0] in_x,in_y;
 reg bank0_valid,bank1_valid;
 reg [15:0] bank0_y,bank1_y;
 reg read_bank;
 wire [23:0] line0_q,line1_q;
 wire [23:0] selected_q=read_bank?line1_q:line0_q;
 line_ram_1024x24 u_line0(.clk(clk),.we(pixel_valid && !input_bank),
  .waddr(in_x[9:0]),.din(pixel_rgb),.raddr(source_x[9:0]),.dout(line0_q));
 line_ram_1024x24 u_line1(.clk(clk),.we(pixel_valid && input_bank),
  .waddr(in_x[9:0]),.din(pixel_rgb),.raddr(source_x[9:0]),.dout(line1_q));

 reg running;
 reg [10:0] out_x,out_y;
 reg [15:0] source_x,source_y,x_rem;
 wire [16:0] x_sum=x_rem+src_w;
 wire [16:0] y_sum=y_rem+src_h;
 wire [1:0] x_step=(x_sum>=({5'b0,virtual_w}<<1))?2:
                       (x_sum>={5'b0,virtual_w})?1:0;
 wire [1:0] y_step=(y_sum>=({5'b0,virtual_h}<<1))?2:
                       (y_sum>={5'b0,virtual_h})?1:0;
 wire [16:0] x_rem_next=x_sum-(x_step==2?({5'b0,virtual_w}<<1):
                                  x_step==1?{5'b0,virtual_w}:17'd0);
 wire [16:0] y_rem_next=y_sum-(y_step==2?({5'b0,virtual_h}<<1):
                                  y_step==1?{5'b0,virtual_h}:17'd0);
 wire row_has_image=out_y>=y_first && out_y<y_last;
 wire pixel_has_image=out_x>=x_first && out_x<x_last;
 wire wanted_in_bank0=bank0_valid && bank0_y==source_y;
 wire wanted_in_bank1=bank1_valid && bank1_y==source_y;
 // The BMP reader may start after the leading ORIGINAL border is drained.
 // Otherwise the two line RAMs can overwrite row zero before it is displayed.
 assign input_start_ready=running && row_has_image;

 always @(posedge clk or posedge rst)begin
  if(rst)begin
   cstate<=C_IDLE;gstate<=G_IDLE;src_w<=1;src_h<=1;virtual_w<=1;virtual_h<=1;
   x_first<=0;x_last<=0;y_first<=0;y_last<=0;crop_x<=0;crop_y<=0;
   x_base<=0;y_base<=0;x_rem_start<=0;y_rem<=0;div_num<=0;div_den<=1;
   div_start<=0;size_is_width<=0;config_ready<=0;
   input_bank<=0;in_x<=0;in_y<=0;bank0_valid<=0;bank1_valid<=0;
   bank0_y<=0;bank1_y<=0;read_bank<=0;
   running<=0;out_x<=0;out_y<=0;source_x<=0;source_y<=0;x_rem<=0;
   output_valid<=0;output_rgb<=0;output_done<=0;input_overrun<=0;
  end else begin
   div_start<=0;output_valid<=0;output_done<=0;
   if(image_start)begin
    src_w<=source_width;src_h<=source_height;config_ready<=0;
    input_bank<=0;in_x<=0;in_y<=0;bank0_valid<=0;bank1_valid<=0;
    running<=0;gstate<=G_IDLE;input_overrun<=0;
    if(mode==1)begin
     virtual_w<=source_width;virtual_h<=source_height;cstate<=C_X_START;
    end else if((mode==2 && aspect_w<=aspect_h) || (mode==3 && aspect_w>=aspect_h))begin
     // Height is fixed; calculate the width with the shared divider.
     virtual_h<=SCREEN_H;div_num<=source_width*16'd600;div_den<=source_height;
     size_is_width<=1;div_start<=1;cstate<=C_SIZE_WAIT;
    end else begin
     virtual_w<=SCREEN_W;div_num<=source_height<<10;div_den<=source_width;
     size_is_width<=0;div_start<=1;cstate<=C_SIZE_WAIT;
    end
   end else case(cstate)
    C_SIZE_WAIT:if(div_done)begin
      if(size_is_width)virtual_w<=div_q<1?1:div_q[11:0];
      else virtual_h<=div_q<1?1:div_q[11:0];
      cstate<=C_X_START;
    end
    C_X_START:begin
      if(virtual_w<=SCREEN_W)begin
       x_first<=(SCREEN_W-virtual_w)>>1;x_last<=((SCREEN_W-virtual_w)>>1)+virtual_w;crop_x<=0;
       x_base<=0;x_rem_start<=0;cstate<=C_Y_START;
      end else begin
       x_first<=0;x_last<=SCREEN_W;crop_x<=(virtual_w-SCREEN_W)>>1;
       div_num<=((virtual_w-SCREEN_W)>>1)*src_w;div_den<=virtual_w;
       div_start<=1;cstate<=C_X_WAIT;
      end
    end
    C_X_WAIT:if(div_done)begin x_base<=div_q[15:0];x_rem_start<=div_r[15:0];cstate<=C_Y_START;end
    C_Y_START:begin
      if(virtual_h<=SCREEN_H)begin
       y_first<=(SCREEN_H-virtual_h)>>1;y_last<=((SCREEN_H-virtual_h)>>1)+virtual_h;crop_y<=0;
       y_base<=0;y_rem<=0;config_ready<=1;cstate<=C_READY;
      end else begin
       y_first<=0;y_last<=SCREEN_H;crop_y<=(virtual_h-SCREEN_H)>>1;
       div_num<=((virtual_h-SCREEN_H)>>1)*src_h;div_den<=virtual_h;
       div_start<=1;cstate<=C_Y_WAIT;
      end
    end
    C_Y_WAIT:if(div_done)begin
      y_base<=div_q[15:0];y_rem<=div_r[15:0];config_ready<=1;cstate<=C_READY;
    end
    default:;
   endcase

   if(pixel_valid)begin
    if(running && row_has_image && pixel_has_image &&
       ((gstate==G_READ)||(gstate==G_PIXEL)) && input_bank==read_bank)
      input_overrun<=1;
    if(in_x==src_w-1)begin
     if(input_bank)begin bank1_y<=in_y;bank1_valid<=1;end
     else begin bank0_y<=in_y;bank0_valid<=1;end
     in_x<=0;input_bank<=~input_bank;
     if(in_y+1<src_h)in_y<=in_y+1'b1;
    end else in_x<=in_x+1'b1;
   end

   if(output_start && config_ready && !running)begin
    running<=1;gstate<=G_ROW;out_x<=0;out_y<=0;
    source_y<=y_base;source_x<=x_base;x_rem<=x_rem_start;
   end
   if(running)case(gstate)
    G_ROW:begin
      out_x<=0;source_x<=x_base;x_rem<=x_rem_start;
      if(row_has_image)gstate<=G_WAIT_LINE;
      else gstate<=G_PIXEL;
    end
    G_WAIT_LINE:begin
      if(wanted_in_bank0)begin read_bank<=0;gstate<=G_READ;end
      else if(wanted_in_bank1)begin read_bank<=1;gstate<=G_READ;end
    end
    G_READ:begin
      if(!pixel_has_image)gstate<=G_PIXEL;
      else gstate<=G_PIXEL;
    end
    G_PIXEL:if(!output_pause)begin
      output_valid<=1;
      output_rgb<=(row_has_image && pixel_has_image)?selected_q:24'h101c30;
      if(out_x==SCREEN_W-1)begin
       out_x<=0;
       if(out_y==SCREEN_H-1)begin
        running<=0;gstate<=G_IDLE;output_done<=1;
       end else begin
        out_y<=out_y+1'b1;
        if(row_has_image)begin source_y<=source_y+y_step;y_rem<=y_rem_next[15:0];end
        gstate<=G_ROW;
       end
      end else begin
       out_x<=out_x+1'b1;
       if(row_has_image && pixel_has_image)begin
        source_x<=source_x+x_step;x_rem<=x_rem_next[15:0];
       end
       gstate<=row_has_image?G_READ:G_PIXEL;
      end
    end
    default:gstate<=G_IDLE;
   endcase
  end
 end
endmodule

module u32_divider_reference(
 input clk,input rst,input start,input [31:0] dividend,input [31:0] divisor,
 output reg busy,output reg done,output reg [31:0] quotient,output reg [31:0] remainder
);
 reg [63:0] work;
 reg [31:0] den;
 reg [5:0] count;
 wire [63:0] shifted=work<<1;
 wire ge=shifted[63:32]>=den;
 wire [63:0] reduced={shifted[63:32]-den,shifted[31:1],1'b1};
 always @(posedge clk or posedge rst)begin
  if(rst)begin busy<=0;done<=0;quotient<=0;remainder<=0;work<=0;den<=1;count<=0;end
  else begin
   done<=0;
   if(start && !busy)begin
    if(divisor==0)begin quotient<=0;remainder<=0;done<=1;end
    else begin work<={32'b0,dividend};den<=divisor;count<=0;busy<=1;end
   end else if(busy)begin
    work<=ge?reduced:shifted;
    if(count==31)begin
     quotient<=ge?reduced[31:0]:shifted[31:0];
     remainder<=ge?reduced[63:32]:shifted[63:32];
     busy<=0;done<=1;
    end else count<=count+1'b1;
   end
  end
 end
endmodule
