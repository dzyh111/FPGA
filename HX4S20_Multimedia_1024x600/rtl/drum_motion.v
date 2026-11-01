// Recording-cued drum gesture. Preparatory movement is visual anticipation,
// not another sound/event: only onset may touch the skin or count a stroke.
// Geometry advances on adopted video frames that consumed PCM samples.
module drum_motion(
 input wire clk,input wire rst,input wire stream_reset,input wire enable,
 input wire frame_tick,input wire advance,input wire onset,
 input wire [3:0] level,input wire [8:0] cue_index,
 input wire [10:0] window_sample,input wire ahead_onset,
 output reg [5:0] left_age,output reg [5:0] right_age,
 output reg left_strong,output reg right_strong,
 output reg [2:0] stroke_count,
 output reg [4:0] left_lift,output reg [4:0] right_lift
);
 reg preparing,prepare_right;
 reg [8:0] prepare_index,last_index;
 wire stroke_right=stroke_count[0]^stroke_count[2];
 wire [2:0] next_stroke_count=stroke_count+1'b1;
 wire next_stroke_right=next_stroke_count[0]^next_stroke_count[2];
 wire double_stroke=level>=13 && stroke_count==7;
 wire [5:0] next_left_age=left_age==63 ? 6'd63 : left_age+1'b1;
 wire [5:0] next_right_age=right_age==63 ? 6'd63 : right_age+1'b1;
 wire [8:0] one_ahead=cue_index+9'd1;
 wire [8:0] two_ahead=cue_index+9'd2;
 wire wrapped=cue_index<last_index;
 wire prepare_valid=preparing && !wrapped &&
    (prepare_index==cue_index || prepare_index==one_ahead || prepare_index==two_ahead);
 reg [4:0] prepare_lift;

 // Two 1500-sample windows give at most 62.5 ms anticipation. These bands
 // approximate remaining played samples without a divider/multiplier. The
 // 4-pixel slew limit fills intermediate positions between the coarse bands.
 // At a very short inter-onset interval preparation may be incomplete; the
 // real onset still forces contact rather than delaying the sound/gesture.
 always @*begin
  prepare_lift=2; // Hover above the skin; only a real onset may set lift zero.
  if(prepare_index==two_ahead)prepare_lift=window_sample<750 ? 16 : 8;
 end

 function [4:0] rebound;
  input [5:0] elapsed;
  input strong_hit;
  reg [4:0] height;
  begin
   case(elapsed)
    0:height=0;1:height=3;2:height=7;3:height=11;
    4:height=15;5:height=19;6:height=22;7:height=25;
    8:height=27;9:height=29;10,11:height=30;
    12:height=29;13:height=28;14:height=26;15:height=24;
    16:height=22;17:height=21;default:height=20;
   endcase
   rebound=strong_hit ? height : height-(height>>2);
  end
 endfunction
 function [4:0] ease_to;
  input [4:0] current_height,target_height;
  begin
   if({1'b0,current_height}+6'd4<{1'b0,target_height})ease_to=current_height+5'd4;
   else if({1'b0,target_height}+6'd4<{1'b0,current_height})ease_to=current_height-5'd4;
   else ease_to=target_height;
  end
 endfunction

 always @(posedge clk or posedge rst)begin
  if(rst)begin
   left_age<=63;right_age<=63;left_strong<=0;right_strong<=0;
   stroke_count<=0;left_lift<=15;right_lift<=15;
   preparing<=0;prepare_right<=0;prepare_index<=0;last_index<=0;
  end else if(stream_reset || !enable)begin
   left_age<=63;right_age<=63;left_strong<=0;right_strong<=0;
   stroke_count<=0;left_lift<=15;right_lift<=15;
   preparing<=0;prepare_right<=0;prepare_index<=0;last_index<=0;
  end else if(frame_tick && advance)begin
   last_index<=cue_index;
   left_age<=next_left_age;right_age<=next_right_age;
   left_lift<=ease_to(left_lift,rebound(next_left_age,left_strong));
   right_lift<=ease_to(right_lift,rebound(next_right_age,right_strong));
   if(prepare_valid)begin
    if(prepare_right)right_lift<=ease_to(right_lift,prepare_lift);
    else left_lift<=ease_to(left_lift,prepare_lift);
   end else begin
    preparing<=0;
    // Latch one target, never retarget it as the look-ahead address advances.
    // Do not wrap a scene's final two windows into the next scene's cues.
    if(!preparing && !wrapped && ahead_onset && cue_index<510)begin
     preparing<=1;prepare_index<=two_ahead;prepare_right<=stroke_right;
     if(stroke_right)right_lift<=ease_to(right_lift,window_sample<750 ? 5'd16 : 5'd8);
     else left_lift<=ease_to(left_lift,window_sample<750 ? 5'd16 : 5'd8);
    end
   end
   if(onset)begin
    stroke_count<=next_stroke_count;
    // A contact may coincide with a different future look-ahead event. Keep
    // that known future target, but assign the NEXT stroke's side. Otherwise
    // a 1500-sample window could pass before the next 60-Hz adoption frame.
    prepare_right<=next_stroke_right;
    if(prepare_valid && prepare_index!=cue_index)preparing<=1;
    else if(!wrapped && ahead_onset && cue_index<510)begin
     preparing<=1;prepare_index<=two_ahead;
    end else preparing<=0;
    if(!stroke_right || double_stroke)begin
     left_age<=0;left_lift<=0;left_strong<=level>=10;
    end
    if(stroke_right || double_stroke)begin
     right_age<=0;right_lift<=0;right_strong<=level>=10;
    end
   end
  end
 end
endmodule
