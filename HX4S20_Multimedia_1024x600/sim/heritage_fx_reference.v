// Lightweight, sample-clocked performance illustration. The note/gesture map
// is artistic, not an inference of the performer's actual fingering/bow hand.
module heritage_fx_reference(
 input clk,input rst,input frame_tick,input enable,input stream_reset,
 input [2:0] scene,input sample_consumed,input [31:0] sample_position,
 input valid,input [10:0] x,input [10:0] y,input [23:0] rgb,
 output reg out_valid,output reg [10:0] out_x,output reg [10:0] out_y,
 output reg [23:0] out_rgb,
 output reg signed [4:0] bow_offset,output reg [3:0] drum_offset
);
 reg [10:0] window_sample;
 reg [8:0] cue_index;
 wire [1:0] cue_scene=scene-1'b1;
 wire [10:0] cue_addr={cue_scene,cue_index};
 wire [7:0] cue_data;
 reg [10:0] cue_addr_d,last_cue;
 reg cue_ready,moved,hit_pending;
 reg [3:0] level;
 reg [2:0] note;
 reg [3:0] pending_level;
 reg [2:0] pending_note;
 reg [5:0] age;
 reg [4:0] bow_phase;
 reg [2:0] sparkle;
 heritage_cue_rom u_cue(.clk(clk),.addr(cue_addr),.data(cue_data));

 always @(posedge clk or posedge rst)begin
  if(rst)begin
   window_sample<=0;cue_index<=0;cue_addr_d<=0;last_cue<=11'h7ff;
   cue_ready<=0;moved<=0;hit_pending<=0;level<=0;note<=0;age<=63;
   pending_level<=0;pending_note<=0;
   bow_phase<=0;sparkle<=0;bow_offset<=0;drum_offset<=0;
  end else begin
   cue_addr_d<=cue_addr;
   if(stream_reset || !enable)begin
    window_sample<=0;cue_index<=0;cue_ready<=0;last_cue<=11'h7ff;
    moved<=0;hit_pending<=0;level<=0;note<=0;age<=63;
    pending_level<=0;pending_note<=0;
    bow_phase<=0;sparkle<=0;bow_offset<=0;drum_offset<=0;
   end else begin
    cue_ready<=1;
    if(sample_consumed)begin
     moved<=1;
     if(sample_position==0)begin window_sample<=0;cue_index<=0;end
     else if(window_sample==1499)begin window_sample<=0;cue_index<=cue_index+1'b1;end
     else window_sample<=window_sample+1'b1;
    end
    // One event per cue window, even if two video frames see the same cue.
    if(cue_ready && cue_addr_d!=last_cue)begin
     last_cue<=cue_addr_d;pending_level<=cue_data[7:4];pending_note<=cue_data[2:0];
     if(cue_data[3])hit_pending<=1;
    end
    if(frame_tick)begin
     moved<=sample_consumed;
     if(moved)begin
      level<=pending_level;note<=pending_note;
      sparkle<=sparkle+1'b1;
      if(hit_pending)begin age<=0;hit_pending<=0;end
      else if(age!=63)age<=age+1'b1;
      if(level>=2)bow_phase<=bow_phase+1'b1;
      // Triangular travel, only +/- 6 pixels: keeps bow on the string.
      if(bow_phase[4])bow_offset<=5'sd11-$signed({1'b0,bow_phase[4:1]});
      else bow_offset<=$signed({1'b0,bow_phase[4:1]})-5'sd4;
      // Rest at +8 raised. An onset puts the tip onto the membrane.
      if(hit_pending)drum_offset<=0;
      else if(age<8)drum_offset<=age[3:0]+1'b1;
      else drum_offset<=8;
     end
    end
   end
  end
 end

 function [10:0] difference;
  input [10:0] a,b;
  begin difference=a>b?a-b:b-a;end
 endfunction
 // Eight-sided distance approximates a round ring without DSPs/square roots.
 function [11:0] round_distance;
  input [10:0] dx,dy;
  begin round_distance=dx>dy ? {1'b0,dx}+{2'b0,dy[10:1]} :
                                               {1'b0,dy}+{2'b0,dx[10:1]};end
 endfunction
 function [23:0] tint;
  input [23:0] bg,fg;
  begin tint={((bg[23:16]>>1)+(fg[23:16]>>1)),
              ((bg[15:8]>>1)+(fg[15:8]>>1)),
              ((bg[7:0]>>1)+(fg[7:0]>>1))};end
 endfunction

 reg [10:0] string_y,pluck_y,hole_x,hole_y,dx,dy;
 reg [11:0] distance,radius;
 reg [23:0] color;
 reg light,core;
 reg [6:0] hole_mask;
 reg [2:0] hole_no;
 always @*begin
  color=rgb;light=0;core=0;
  dx=0;dy=0;distance=0;radius=0;
  // String convergence follows the photographed 1024x600 guqin.
  string_y=11'd350-(x>>2)+(x>>4)+note*10-note*x[9:7];
  pluck_y=11'd197+{note,2'b00};
  hole_no=0;hole_x=446;hole_y=288;
  hole_mask=7'b1111111;
  case(note)
   0:hole_mask=7'b0111111;1:hole_mask=7'b0011111;
   2:hole_mask=7'b0001111;3:hole_mask=7'b0000111;
   4:hole_mask=7'b0000011;5:hole_mask=7'b0000001;
   default:hole_mask=0;
  endcase
  if(enable)case(scene)
   1:begin
    if(x>=145 && x<947 && level>=2 && age<30 &&
       difference(y,string_y+(sparkle[0] && age<10))<=1) light=1;
    dx=difference(x,11'd820);dy=difference(y,pluck_y);
    distance=round_distance(dx,dy<<1);radius={age,2'b00}+8;
    if(age<24 && distance>=radius && distance<=radius+2 && y<390)light=1;
    if(age<7 && dx+dy<7)core=1;
    if(light)color=tint(rgb,24'hffdf7d);
    if(core)color=24'hfff5ce;
   end
   2:begin
    dx=difference(x,11'd523);dy=difference(y,11'd393);
    distance=round_distance(dx,dy);
    if(level>=2 && distance<level+5)color=tint(rgb,24'hb6ece2);
    if(level>=7 && distance<3)color=24'he6fff4;
   end
   3:begin
    if(x<477)begin hole_no=0;hole_x=446;hole_y=288;end
    else if(x<539)begin hole_no=1;hole_x=508;hole_y=280;end
    else if(x<599)begin hole_no=2;hole_x=568;hole_y=273;end
    else if(x<659)begin hole_no=3;hole_x=628;hole_y=266;end
    else if(x<719)begin hole_no=4;hole_x=689;hole_y=259;end
    else begin hole_no=5;hole_x=746;hole_y=252;end
    dx=difference(x,hole_x);dy=difference(y,hole_y);
    distance=round_distance(dx,dy);
    if(level>=2 && hole_mask[hole_no] && distance>=8 && distance<=13)
     color=tint(rgb,24'hc2efff);
    // Subtle moving breath streaks immediately above the blowing end.
    if(level>=3 && x>=80 && x<255 && y>=290 && y<316 &&
      ((x[5:0]+{sparkle,3'b0}+y[5:0])&6'h3f)<2)
     color=tint(rgb,24'hc0dfe9);
   end
   4:begin
    // The two photographed stick tips strike (378,225) and (662,230).
    dx=difference(x,11'd378);dy=difference(y,11'd225);
    // Both sticks share a compact lift animation, hence both tips get rings.
    if(x>=512)begin dx=difference(x,11'd662);dy=difference(y,11'd230);end
    distance=round_distance(dx,dy<<1);radius={age,2'b00}+5;
    if(age<19 && distance>=radius && distance<=radius+3 &&
       x>225 && x<800 && y>150 && y<320)color=tint(rgb,24'hffcc87);
    if(age<3 && dx+dy<8)color=24'hfff1cb;
   end
   default:color=rgb;
  endcase
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin out_valid<=0;out_x<=0;out_y<=0;out_rgb<=0;end
  else begin out_valid<=valid;out_x<=x;out_y<=y;out_rgb<=color;end
 end
endmodule
