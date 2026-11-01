// Streaming BMP scaler. Input and output row order is bottom-up; the SDRAM
// writer flips the finished 800x600 frame. Two true dual-port line memories
// provide one write port and one synchronous read port per source row.
module bmp_bilinear_scaler #(
 parameter OUT_W=800,OUT_H=600,MAX_W=1024
)(
 input clk,input rst,input image_start,
 input [15:0] source_width,input [15:0] source_height,
 input pixel_valid,input [23:0] pixel_rgb,
 output reg output_valid,output reg [23:0] output_rgb,
 output reg output_done,output reg input_overrun
);
wire [23:0] line0_q,line1_q;
reg [23:0] left0,left1;
reg [7:0] top_r_q,top_g_q,top_b_q,bot_r_q,bot_g_q,bot_b_q;
reg input_bank,pair_first_bank;
reg [15:0] in_x,in_y,src_w,src_h,pair_y;
reg generating;
reg [1:0] read_phase;
reg [15:0] out_x,out_y,h_base,v_base;
reg [10:0] h_rem,v_rem;
reg [7:0] fx_d,fy_d;
localparam H_DEN=OUT_W-1,V_DEN=OUT_H-1;
wire [11:0] h_sum=h_rem+src_w-1'b1;
wire [11:0] v_sum=v_rem+src_h-1'b1;
wire [15:0] h_next_base=h_base+(h_sum>=2*H_DEN?2:(h_sum>=H_DEN?1:0));
wire [10:0] h_next_rem=h_sum>=2*H_DEN?h_sum-2*H_DEN:(h_sum>=H_DEN?h_sum-H_DEN:h_sum);
wire [15:0] v_next_base=v_base+(v_sum>=2*V_DEN?2:(v_sum>=V_DEN?1:0));
wire [10:0] v_next_rem=v_sum>=2*V_DEN?v_sum-2*V_DEN:(v_sum>=V_DEN?v_sum-V_DEN:v_sum);
wire [15:0] x1=(h_base+1<src_w)?h_base+1:h_base;
// OUT_W/OUT_H are fixed at 800/600. These rounded constant multiplies
// approximate rem*256/799 and rem*256/599 without long divider chains.
wire [17:0] fx_scaled=h_rem*7'd82+8'd128;
wire [18:0] fy_scaled=v_rem*7'd109+8'd128;
wire [7:0] fx=(OUT_W==800)?fx_scaled[15:8]:((h_rem<<8)/H_DEN);
wire [7:0] fy=(OUT_H==600)?fy_scaled[15:8]:((v_rem<<8)/V_DEN);
wire [9:0] ram_raddr=(read_phase==0)?h_base[9:0]:x1[9:0];
wire [23:0] right0=pair_first_bank?line1_q:line0_q;
wire [23:0] right1=pair_first_bank?line0_q:line1_q;
line_ram_1024x24 u_line0(.clk(clk),.we(pixel_valid && input_bank==0),
 .waddr(in_x[9:0]),.din(pixel_rgb),.raddr(ram_raddr),.dout(line0_q));
line_ram_1024x24 u_line1(.clk(clk),.we(pixel_valid && input_bank==1),
 .waddr(in_x[9:0]),.din(pixel_rgb),.raddr(ram_raddr),.dout(line1_q));

function [7:0] lerp8;
 input [7:0] a,b;input [7:0] f;
 reg signed [8:0] delta;reg signed [17:0] product;reg signed [18:0] scaled;
 begin
  delta=$signed({1'b0,b})-$signed({1'b0,a});
  product=delta*$signed({1'b0,f});
  scaled=$signed({1'b0,a,8'b0})+product;
  lerp8=scaled>>>8;
 end
endfunction
wire [7:0] top_r=lerp8(left0[23:16],right0[23:16],fx_d);
wire [7:0] top_g=lerp8(left0[15:8],right0[15:8],fx_d);
wire [7:0] top_b=lerp8(left0[7:0],right0[7:0],fx_d);
wire [7:0] bot_r=lerp8(left1[23:16],right1[23:16],fx_d);
wire [7:0] bot_g=lerp8(left1[15:8],right1[15:8],fx_d);
wire [7:0] bot_b=lerp8(left1[7:0],right1[7:0],fx_d);
wire [23:0] interpolated={
 lerp8(top_r_q,bot_r_q,fy_d),lerp8(top_g_q,bot_g_q,fy_d),lerp8(top_b_q,bot_b_q,fy_d)};

always @(posedge clk or posedge rst)begin
 if(rst)begin
  input_bank<=0;pair_first_bank<=0;in_x<=0;in_y<=0;src_w<=1;src_h<=1;pair_y<=0;
  generating<=0;read_phase<=0;out_x<=0;out_y<=0;h_base<=0;v_base<=0;
  h_rem<=0;v_rem<=0;left0<=0;left1<=0;fx_d<=0;fy_d<=0;
  top_r_q<=0;top_g_q<=0;top_b_q<=0;bot_r_q<=0;bot_g_q<=0;bot_b_q<=0;
  output_valid<=0;output_rgb<=0;output_done<=0;input_overrun<=0;
 end else begin
  output_valid<=0;output_done<=0;
  if(image_start)begin
   src_w<=source_width;src_h<=source_height;
   input_bank<=0;in_x<=0;in_y<=0;pair_y<=0;
   generating<=0;read_phase<=0;out_x<=0;out_y<=0;
   h_base<=0;v_base<=0;h_rem<=0;v_rem<=0;input_overrun<=0;
  end

  if(pixel_valid)begin
   if(in_x==src_w-1)begin
    in_x<=0;if(in_y+1<src_h)in_y<=in_y+1'b1;input_bank<=~input_bank;
    if(generating)input_overrun<=1;
    if(src_h==1 && in_y==0)begin
     pair_first_bank<=input_bank;pair_y<=0;generating<=1;read_phase<=0;
     out_x<=0;h_base<=0;h_rem<=0;
    end else if(in_y>0 && v_base==in_y-1 && !generating)begin
     pair_first_bank<=~input_bank;pair_y<=in_y-1'b1;generating<=1;read_phase<=0;
     out_x<=0;h_base<=0;h_rem<=0;
    end else if(in_y==src_h-1 && v_base==in_y && !generating)begin
     pair_first_bank<=input_bank;pair_y<=in_y;generating<=1;read_phase<=0;
     out_x<=0;h_base<=0;h_rem<=0;
    end
   end else in_x<=in_x+1'b1;
  end

  if(generating)begin
   case(read_phase)
    0:begin
     read_phase<=1;
    end
    1:begin
     left0<=pair_first_bank?line1_q:line0_q;
     left1<=pair_first_bank?line0_q:line1_q;
     fx_d<=fx;read_phase<=2;
    end
    2:begin
     top_r_q<=top_r;top_g_q<=top_g;top_b_q<=top_b;
     bot_r_q<=bot_r;bot_g_q<=bot_g;bot_b_q<=bot_b;
     fy_d<=fy;
     read_phase<=3;
    end
    default:begin
     output_valid<=1;output_rgb<=interpolated;
     if(out_x==OUT_W-1)begin
      read_phase<=0;out_x<=0;h_base<=0;h_rem<=0;
      if(out_y==OUT_H-1)begin generating<=0;output_done<=1;end
      else begin
       out_y<=out_y+1'b1;v_base<=v_next_base;v_rem<=v_next_rem;
       if(v_next_base==pair_y)generating<=1;
       else if(v_next_base==src_h-1 && in_y==src_h-1)begin
        pair_y<=src_h-1'b1;pair_first_bank<=~input_bank;generating<=1;
       end else generating<=0;
      end
     end else begin
     out_x<=out_x+1'b1;h_base<=h_next_base;h_rem<=h_next_rem;
      read_phase<=0;
     end
    end
   endcase
  end
 end
end
endmodule
