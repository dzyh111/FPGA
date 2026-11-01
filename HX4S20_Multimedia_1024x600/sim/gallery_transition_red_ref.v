`timescale 1ns/1ps
// Independent integer specification for the approved red cloth. Simulation only:
// no bit slices, inferred FPGA arithmetic, pipeline or frame-control implementation.
module gallery_transition_red_ref(
 input [23:0] rgb,input [10:0] x,y,input [4:0] fade_alpha,
 input manual_active,input [5:0] manual_phase,input valid,
 output reg [23:0] out_rgb,output reg [4:0] out_alpha,
 output reg [23:0] out_background
);
 integer distance,curve,phase_gain,gain,bend,width,depth,edge_depth_ref,covered;
 integer broad_position,broad,fine_position,fine,shadow,r,g,b,amount;
 reg [23:0] cloth;
 function [7:0] mix;
  input integer fg,bg,a;
  begin mix=(fg*a+bg*(16-a))/16;end
 endfunction
 always @*begin
  distance=x>=512?x-512:511-x;
  phase_gain=manual_phase>=32?63-manual_phase:manual_phase;
  curve=(y/2)*(y/2);gain=(curve/512)%256;
  bend=(gain*phase_gain/32)%256;
  width=manual_phase*9+bend;
  depth=distance-width;edge_depth_ref=width-distance;covered=distance>=width;
  broad_position=(distance+((y/32)%32)+manual_phase*4)%256;
  broad=broad_position>=128?15-((broad_position/8)%16):(broad_position/8)%16;
  fine_position=(distance+((y/32)%32)+(manual_phase%32)*4)%128;
  fine=fine_position>=64?7-((fine_position/8)%8):(fine_position/8)%8;
  shadow=covered && depth<24?(23-depth)/2:0;
  r=158+broad*4+fine-shadow;
  g=25+broad*2+fine/2-shadow/2;
  b=30+broad+fine/2-shadow/2;
  if(manual_phase!=0 && manual_phase!=63 && covered && depth<2)begin
   r=r+8;g=g+2;b=b+1;
  end
  cloth={r[7:0],g[7:0],b[7:0]};
  amount=fade_alpha>=16?16:fade_alpha;
  out_background=24'h101c30;
  if(manual_active)begin
   out_background=cloth;
   if(manual_phase==63)amount=16;
   else if(manual_phase==0 || covered)amount=0;
   else if(edge_depth_ref>=32)amount=16;
   else amount=edge_depth_ref/2;
  end
  out_alpha=amount;
  if(!valid)out_rgb=rgb;
  else if(manual_active && manual_phase==0)out_rgb=cloth;
  else if(manual_active && manual_phase==63)out_rgb=rgb;
  else out_rgb={mix(rgb[23:16],out_background[23:16],amount),
                mix(rgb[15:8],out_background[15:8],amount),
                mix(rgb[7:0],out_background[7:0],amount)};
 end
endmodule

