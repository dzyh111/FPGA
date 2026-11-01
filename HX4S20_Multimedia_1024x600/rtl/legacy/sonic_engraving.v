// A whole-phrase audio painting, not another instantaneous waveform.
// One 512x16 BRAM stores 16 seconds of REAL, pre-mute consumed PCM features:
// {peak[3:0], zero crossings[6:0], attack, attack age[3:0]} per 1500 samples.
// No photo/frame-buffer writes. A frame-latched visible prefix prevents tearing;
// unread/stale RAM is masked rather than reset (preserves BRAM inference).
// Art styles are illustrative, not pitch/instrument/performer recognition.
// RGB/valid/coordinates have exactly THREE clocks of latency.
module sonic_engraving(
 input clk,input rst,input frame_tick,input enable,input stream_reset,
 input [2:0] scene,input sample_valid,input signed [23:0] sample,
 input valid,input [10:0] x,input [10:0] y,input [23:0] rgb,
 output reg out_valid,output reg [10:0] out_x,output reg [10:0] out_y,
 output reg [23:0] out_rgb
);
 reg [2:0] saved_scene;
 reg [10:0] sample_count;
 reg [3:0] peak,previous_peak,attack_age;
 reg [6:0] crossings;
 reg previous_sign;
 reg [9:0] written_count,visible_count;
 reg clear_pending,word_pending;
 reg [15:0] pending_word;
 wire [23:0] magnitude=sample[23] ? ~sample+24'd1 : sample;
 wire [3:0] amplitude=magnitude[23]?4'd15:magnitude[22:19];
 wire [3:0] next_peak=amplitude>peak?amplitude:peak;
 wire crossing=sample_count!=0 && previous_sign!=sample[23];
 wire [6:0] next_crossings=crossing && crossings!=127?crossings+1'b1:crossings;
 wire attack={1'b0,next_peak}>={1'b0,previous_peak}+5'd3;
 wire [3:0] next_age=attack?4'd0:(attack_age==15?4'd15:attack_age+1'b1);
 wire legal_scene=scene>=1 && scene<=4;
 wire clear_stream=stream_reset || !enable || !legal_scene || scene!=saved_scene;
 wire write_word=word_pending && !clear_pending && written_count<512 && !clear_stream;
 (* ram_style="block" *) reg [15:0] history [0:511];
 reg [15:0] feature_q;
 always @(posedge clk)begin
  feature_q<=history[x[9:1]];
  if(!rst && write_word)history[written_count[8:0]]<=pending_word;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   saved_scene<=0;sample_count<=0;peak<=0;previous_peak<=0;crossings<=0;
   previous_sign<=0;attack_age<=15;written_count<=0;visible_count<=0;
   clear_pending<=1;word_pending<=0;pending_word<=0;
  end else begin
   saved_scene<=scene;
   if(clear_stream)begin
    sample_count<=0;peak<=0;previous_peak<=0;crossings<=0;previous_sign<=0;
    attack_age<=15;written_count<=0;clear_pending<=1;
    if(frame_tick)visible_count<=0;
    word_pending<=0;
   end else begin
    if(frame_tick)begin
     visible_count<=clear_pending?10'd0:written_count;
     clear_pending<=0;
    end
    if(write_word)begin written_count<=written_count+1'b1;word_pending<=0;end
    if(sample_valid)begin
     previous_sign<=sample[23];
     if(written_count==512)begin
      // The next consumed sample starts a new phrase. Do not overwrite a
      // displayed column until its old prefix was hidden at a frame boundary.
      written_count<=0;clear_pending<=1;sample_count<=1;peak<=amplitude;
      crossings<=0;previous_peak<=0;attack_age<=15;word_pending<=0;
     end else if(sample_count==1499)begin
      pending_word<={next_peak,next_crossings,attack,next_age};word_pending<=1;
      sample_count<=0;peak<=0;crossings<=0;previous_peak<=next_peak;attack_age<=next_age;
     end else begin
      sample_count<=sample_count+1'b1;peak<=next_peak;crossings<=next_crossings;
     end
    end
   end
  end
 end

 reg valid_d,ready_d;
 reg [10:0] x_d,y_d;
 reg [23:0] rgb_d;
 reg [2:0] scene_d;
 reg [9:0] previous_center;
 wire [3:0] energy=feature_q[15:12];
 wire [6:0] roughness=feature_q[11:5];
 wire [9:0] center=10'd484-{5'd0,energy,1'b0}-{7'd0,roughness[5:3]};
 wire [9:0] before_center=x_d[9:1]==0?center:previous_center;
 wire [10:0] center_sum={1'b0,center}+{1'b0,before_center};
 wire [9:0] halfway=center_sum[10:1];
 wire [9:0] segment_a=x_d[0]?halfway:before_center;
 wire [9:0] segment_b=x_d[0]?center:halfway;
 reg valid_2,ready_2;
 reg [10:0] x_2,y_2;
 reg [23:0] rgb_2;
 reg [2:0] scene_2;
 reg [9:0] low_2,high_2;
 reg [3:0] energy_2,age_2;
 reg [6:0] roughness_2;
 reg attack_2;
 reg [10:0] distance;
 reg core,halo;
 reg [23:0] ink,color;
 wire [10:0] stamp_y=11'd480-{7'd0,roughness_2[3:0]};
 wire [10:0] stamp_distance=y_2>stamp_y?y_2-stamp_y:stamp_y-y_2;
 function [23:0] blend;
  input [23:0] bg,fg;input strong_ink;
  reg [7:0] r,g,b;
  begin
   if(strong_ink)begin
    r=(bg[23:16]>>1)+(fg[23:16]>>1);
    g=(bg[15:8]>>1)+(fg[15:8]>>1);
    b=(bg[7:0]>>1)+(fg[7:0]>>1);
   end else begin
    r=bg[23:16]-(bg[23:16]>>2)+(fg[23:16]>>2);
    g=bg[15:8]-(bg[15:8]>>2)+(fg[15:8]>>2);
    b=bg[7:0]-(bg[7:0]>>2)+(fg[7:0]>>2);
   end
   blend={r,g,b};
  end
 endfunction
 always @*begin
  distance=y_2<low_2?low_2-y_2:(y_2>high_2?y_2-high_2:11'd0);
  core=0;halo=0;ink=24'hbdd9cc;
  if(ready_2 && energy_2!=0)case(scene_2)
   1:begin // Fine strings with a softer parallel ink after-image.
    ink=24'hbfe8d0;core=distance==0;
    halo=distance<=1 || (y_2>=low_2+8 && y_2<=high_2+8);
   end
   2:begin // Connected, pressure-sensitive brush strokes.
    ink=24'hf2cca0;core=distance<=1;
    halo=distance<=({8'd0,energy_2[3:2]}+2);
   end
   3:begin // Two airy dotted paths, texture comes from the played signal.
    ink=24'hbcecff;core=distance==0 && x_2[2:1]!=roughness_2[1:0];
    halo=distance<=1 || (y_2>=low_2+10 && y_2<=high_2+10 && x_2[2]);
   end
   4:begin // Attack deposits vermilion dots with short tapering tails.
    ink=24'hf3ac83;
    halo=age_2<4 && stamp_distance<=((4-age_2)<<1);
    core=attack_2 && stamp_distance<=2;
   end
  endcase
  color=rgb_2;
  if(core || halo)color=blend(rgb_2,ink,core);
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   valid_d<=0;ready_d<=0;x_d<=0;y_d<=0;rgb_d<=0;scene_d<=0;previous_center<=484;
   valid_2<=0;ready_2<=0;x_2<=0;y_2<=0;rgb_2<=0;scene_2<=0;
   low_2<=0;high_2<=0;energy_2<=0;roughness_2<=0;age_2<=15;attack_2<=0;
   out_valid<=0;out_x<=0;out_y<=0;out_rgb<=0;
  end else begin
   valid_d<=valid;x_d<=x;y_d<=y;rgb_d<=rgb;scene_d<=scene;
   ready_d<=enable && legal_scene &&
             x<1024 && y>=432 && y<508 && {1'b0,x[9:1]}<visible_count;
   if(valid_d && x_d<1024 && x_d[0])previous_center<=center;
   valid_2<=valid_d;x_2<=x_d;y_2<=y_d;rgb_2<=rgb_d;scene_2<=scene_d;
   ready_2<=ready_d;energy_2<=energy;roughness_2<=roughness;
   age_2<=feature_q[3:0];attack_2<=feature_q[4];
   low_2<=segment_a<segment_b?segment_a:segment_b;
   high_2<=segment_a>segment_b?segment_a:segment_b;
   out_valid<=valid_2;out_x<=x_2;out_y<=y_2;out_rgb<=color;
  end
 end
endmodule
