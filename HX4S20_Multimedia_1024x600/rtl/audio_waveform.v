// Real PCM waveform, not a synthetic oscillator or a frequency spectrum.
// A snapshot is 256 columns x 2 consecutive consumed PCM samples (10.667 ms
// at 48 kHz). Each column retains both extrema, so a one-sample transient is
// never lost by decimation. Four display pixels join neighbouring midpoints.
// One 512x14 simple-dual-port RAM holds two complete snapshots (7168 bits).
// The capture bank becomes visible ONLY at frame_tick; no live-bank tearing.
// A completed capture waits for that boundary. Pause/underflow stop sampling
// and therefore freeze the last visible snapshot. Feed PRE-MUTE samples and
// sample_consumed, not the unconditional HDMI 48 kHz packet-valid signal.
// Pixel outputs are delayed by exactly FOUR clk edges relative to valid/x/y.
module audio_waveform #(parameter CENTER_Y=552)(
 input clk,input rst,input stream_reset,input frame_tick,
 input sample_valid,input signed [23:0] sample,input [2:0] scene,
 input valid,input [10:0] x,input [10:0] y,
 output reg line_hit,output reg halo_hit,output reg [23:0] line_rgb
);
 // Constant x5/16 scaling maps signed 24-bit full scale to -40..39 pixels.
 // Shifts/addition deliberately avoid DSP multipliers and live gain pumping.
 wire signed [10:0] pcm8={{3{sample[23]}},sample[23:16]};
 wire signed [10:0] scaled=(pcm8<<<2)+pcm8;
 wire signed [6:0] amplitude=scaled>>>4;
 reg signed [6:0] first_sample;
 reg sample_phase,write_bank,display_bank,capture_pending,display_ready;
 reg [7:0] write_column;
 wire signed [6:0] pair_min=first_sample<amplitude?first_sample:amplitude;
 wire signed [6:0] pair_max=first_sample>amplitude?first_sample:amplitude;
 (* ram_style="block" *) reg [13:0] wave_ram[0:511];
 reg [13:0] wave_q;

 // No RAM reset/initialisation: display_ready masks the unread bank until
 // every one of its 256 words has been written. This permits BRAM inference.
 always @(posedge clk)begin
  wave_q<=wave_ram[{display_bank,x[9:2]}];
  if(!rst && !stream_reset && sample_valid && !capture_pending && sample_phase)
   wave_ram[{write_bank,write_column}]<={pair_min,pair_max};
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   first_sample<=0;sample_phase<=0;write_bank<=1;display_bank<=0;
   write_column<=0;capture_pending<=0;display_ready<=0;
  end else if(stream_reset)begin
   first_sample<=0;sample_phase<=0;write_bank<=1;display_bank<=0;
   write_column<=0;capture_pending<=0;display_ready<=0;
  end else begin
   if(frame_tick && capture_pending)begin
    display_bank<=write_bank;write_bank<=~write_bank;
    capture_pending<=0;display_ready<=1;
   end
   if(sample_valid && !capture_pending)begin
    if(!sample_phase)begin first_sample<=amplitude;sample_phase<=1;end
    else begin
     sample_phase<=0;
     if(write_column==255)begin write_column<=0;capture_pending<=1;end
     else write_column<=write_column+1'b1;
    end
   end
  end
 end

 reg valid_d,ready_d;
 reg [10:0] x_d,y_d;
 reg [2:0] scene_d;
 reg signed [7:0] previous_mid;
 wire signed [6:0] column_min=ready_d?$signed(wave_q[13:7]):7'sd0;
 wire signed [6:0] column_max=ready_d?$signed(wave_q[6:0]):7'sd0;
 wire signed [7:0] column_sum={column_min[6],column_min}+{column_max[6],column_max};
 wire signed [7:0] column_mid=column_sum>>>1;
 // x==0 starts a fresh scan line, never connecting its left edge to the
 // preceding row's right edge. All other columns use the previous midpoint.
 wire signed [8:0] point_from=x_d[9:2]==0?
     {column_mid[7],column_mid}:{previous_mid[7],previous_mid};
 wire signed [8:0] point_to={column_mid[7],column_mid};
 wire signed [8:0] delta=point_to-point_from;
 // Stage 2 stops RAM -> midpoint -> delta before interpolation. The centre
 // subtraction runs in PARALLEL from coordinates, not after the min/max mux.
 reg valid_2,in_bounds_2;
 reg [1:0] phase_2;
 reg signed [8:0] from_2,to_2,delta_2;
 reg signed [6:0] min_2,max_2;
 reg signed [11:0] relative_y_2;
 reg [23:0] color_2;
 wire signed [8:0] quarter=delta_2>>>2;
 wire signed [8:0] half_delta=delta_2>>>1;
 reg signed [8:0] segment_a,segment_b,segment_min,segment_max;
 // Stage 3 stops the interpolation/range mux before final pixel comparison.
 reg valid_3,in_bounds_3;
 reg signed [8:0] min_3,max_3;
 reg signed [11:0] relative_y_3;
 reg [23:0] color_3;
 wire signed [9:0] core_min={min_3[8],min_3}-10'sd1;
 wire signed [9:0] core_max={max_3[8],max_3}+10'sd1;
 wire signed [9:0] halo_min={min_3[8],min_3}-10'sd3;
 wire signed [9:0] halo_max={max_3[8],max_3}+10'sd3;
 always @* begin
  // Each short vertical segment includes the preceding interpolated point;
  // even a large slope cannot leave holes between adjacent pixel columns.
  case(phase_2)
   0:begin segment_a=from_2;segment_b=from_2+quarter;end
   1:begin segment_a=from_2+quarter;segment_b=from_2+half_delta;end
   2:begin segment_a=from_2+half_delta;segment_b=to_2-quarter;end
   default:begin segment_a=to_2-quarter;segment_b=to_2;end
  endcase
  segment_min=segment_a<segment_b?segment_a:segment_b;
  segment_max=segment_a>segment_b?segment_a:segment_b;
  // The two source samples may straddle their midpoint; retain their full
  // range at the column endpoint rather than silently discarding a peak.
  if(phase_2==3)begin
   if($signed(min_2)<segment_min)segment_min={{2{min_2[6]}},min_2};
   if($signed(max_2)>segment_max)segment_max={{2{max_2[6]}},max_2};
  end
 end

 // Restrained per-instrument gradients, all combinational shifts/additions.
 // No texture ROM, colour multiplier, or random visual energy is introduced.
 function [23:0] palette;
  input [2:0] instrument;input [4:0] t;
  reg [7:0] r,g,b;
  begin
   case(instrument)
    1:begin r=8'd88+{2'b0,t,1'b0};g=8'd184+{3'b0,t};b=8'd156-{3'b0,t};end
    2:begin r=8'd224+{3'b0,t};g=8'd146+{2'b0,t,1'b0};b=8'd76+{3'b0,t};end
    3:begin r=8'd94+{2'b0,t,1'b0};g=8'd182+{3'b0,t};b=8'd218+{3'b0,t};end
    4:begin r=8'd224+{3'b0,t};g=8'd94+{1'b0,t,2'b0};b=8'd78+{3'b0,t};end
    default:begin r=8'd100+{2'b0,t,1'b0};g=8'd174+{3'b0,t};b=8'd218+{3'b0,t};end
   endcase
   palette={r,g,b};
  end
 endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   valid_d<=0;ready_d<=0;x_d<=0;y_d<=0;scene_d<=0;previous_mid<=0;
   valid_2<=0;in_bounds_2<=0;phase_2<=0;from_2<=0;to_2<=0;delta_2<=0;
   min_2<=0;max_2<=0;relative_y_2<=0;color_2<=0;
   valid_3<=0;in_bounds_3<=0;min_3<=0;max_3<=0;relative_y_3<=0;color_3<=0;
   line_hit<=0;halo_hit<=0;line_rgb<=0;
  end else if(stream_reset)begin
   valid_d<=0;ready_d<=0;x_d<=0;y_d<=0;scene_d<=0;previous_mid<=0;
   valid_2<=0;in_bounds_2<=0;phase_2<=0;from_2<=0;to_2<=0;delta_2<=0;
   min_2<=0;max_2<=0;relative_y_2<=0;color_2<=0;
   valid_3<=0;in_bounds_3<=0;min_3<=0;max_3<=0;relative_y_3<=0;color_3<=0;
   line_hit<=0;halo_hit<=0;line_rgb<=0;
  end else begin
   valid_d<=valid;ready_d<=display_ready;x_d<=x;y_d<=y;scene_d<=scene;
   if(valid_d && x_d<1024 && x_d[1:0]==3)previous_mid<=column_mid;
   valid_2<=valid_d;in_bounds_2<=x_d<1024 && y_d<600;
   phase_2<=x_d[1:0];from_2<=point_from;to_2<=point_to;delta_2<=delta;
   min_2<=column_min;max_2<=column_max;
   relative_y_2<=CENTER_Y-$signed({1'b0,y_d});
   color_2<=palette(scene_d,x_d[9:5]);
   valid_3<=valid_2;in_bounds_3<=in_bounds_2;
   min_3<=segment_min;max_3<=segment_max;relative_y_3<=relative_y_2;color_3<=color_2;
   line_hit<=valid_3 && in_bounds_3 && relative_y_3>=core_min && relative_y_3<=core_max;
   halo_hit<=valid_3 && in_bounds_3 && relative_y_3>=halo_min && relative_y_3<=halo_max;
   line_rgb<=color_3;
  end
 end
endmodule
