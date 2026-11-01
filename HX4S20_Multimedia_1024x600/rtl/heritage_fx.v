// Lightweight, sample-clocked performance illustration. The note/gesture map
// is artistic, not an inference of the performer's actual fingering/bow hand.
`include "heritage_geometry.vh"
module heritage_fx(
 input clk,input rst,input frame_tick,input enable,input stream_reset,
 input [2:0] scene,input sample_consumed,input [31:0] sample_position,
 input valid,input [10:0] x,input [10:0] y,input [23:0] rgb,
 output reg out_valid,output reg [10:0] out_x,output reg [10:0] out_y,
 output reg [23:0] out_rgb,
 output reg signed [5:0] bow_offset,output reg signed [2:0] bow_tilt,
 output reg signed [5:0] bow_angle,
 output wire [4:0] drum_offset,output wire [4:0] drum_right_offset
);
`include "fx_wave_bounds.vh"
 reg [10:0] window_sample;
 reg [8:0] cue_index;
 wire [1:0] cue_scene=scene-1'b1;
 wire [10:0] cue_addr={cue_scene,cue_index};
 wire [7:0] cue_data;
 reg [10:0] cue_addr_d,last_cue,ahead_addr_d;
 reg cue_ready,moved,hit_pending;
 reg [3:0] level;
 reg [2:0] note;
 reg [3:0] pending_level;
 reg [2:0] pending_note;
 reg [5:0] age;
 reg [8:0] bow_phase;
 reg [7:0] level_q;
 reg [7:0] flow_phase;
 reg [3:0] hole_glow[0:5];
 integer h;
 wire [5:0] target_holes=holes_for(pending_note);
 wire [5:0] drum_left_age,drum_right_age;
 wire drum_left_strong,drum_right_strong;
 wire [2:0] stroke_count;
 wire signed [8:0] level_delta=$signed({1'b0,pending_level,4'b0})-$signed({1'b0,level_q});
 wire signed [8:0] level_step=level_delta>0 ? ((level_delta+1)>>>1) : (level_delta>>>1);
 wire [7:0] next_level=level_q+level_step;
 wire signed [7:0] bow_curve=sine_curve(bow_phase[8:3]);
 wire signed [7:0] angle_curve=sine_curve(bow_phase[8:3]+6'd10);
 wire [8:0] ahead_index=cue_index+9'd2;
 wire [7:0] ahead_data;
 heritage_cue_rom u_cue(.clk(clk),.addr(cue_addr),.data(cue_data),
  .ahead_addr({cue_scene,ahead_index}),.ahead_data(ahead_data));
 drum_motion u_drum(.clk(clk),.rst(rst),.stream_reset(stream_reset),
  .enable(enable && scene==4),.frame_tick(frame_tick),.advance(moved),
  .onset(hit_pending),.level(pending_level),.cue_index(cue_index),
  .window_sample(window_sample),
  .ahead_onset(cue_ready && ahead_addr_d=={cue_scene,ahead_index} && ahead_data[3]),
  .left_age(drum_left_age),.right_age(drum_right_age),
  .left_strong(drum_left_strong),.right_strong(drum_right_strong),
  .stroke_count(stroke_count),.left_lift(drum_offset),.right_lift(drum_right_offset));

 always @(posedge clk or posedge rst)begin
  if(rst)begin
   window_sample<=0;cue_index<=0;cue_addr_d<=0;last_cue<=11'h7ff;ahead_addr_d<=0;
   cue_ready<=0;moved<=0;hit_pending<=0;level<=0;note<=0;age<=63;
   pending_level<=0;pending_note<=0;
   bow_phase<=0;bow_offset<=0;bow_tilt<=0;bow_angle<=0;
   level_q<=0;flow_phase<=0;
   for(h=0;h<6;h=h+1)hole_glow[h]<=0;
  end else begin
   cue_addr_d<=cue_addr;ahead_addr_d<={cue_scene,ahead_index};
   if(stream_reset || !enable)begin
    window_sample<=0;cue_index<=0;cue_ready<=0;last_cue<=11'h7ff;
    moved<=0;hit_pending<=0;level<=0;note<=0;age<=63;
    pending_level<=0;pending_note<=0;
    bow_phase<=0;bow_offset<=0;bow_tilt<=0;bow_angle<=0;
    level_q<=0;flow_phase<=0;
    for(h=0;h<6;h=h+1)hole_glow[h]<=0;
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
      // Half-error easing removes the former 32-Hz brightness steps. Only
      // adopted video frames change geometry; pause/underflow freeze easing.
      level_q<=next_level;level<=next_level[7:4];note<=pending_note;
      flow_phase<=flow_phase+1'b1;
      // Restore the six photographed finger-hole accents. This cue-art map
      // illustrates a phrase; it is not a claim to recover actual fingering.
      for(h=0;h<6;h=h+1)begin
       if(target_holes[h] && pending_level>=2)begin
        if(hole_glow[h]<12)hole_glow[h]<=hole_glow[h]+3;
        else hole_glow[h]<=15;
       end else if(hole_glow[h]!=0)hole_glow[h]<=hole_glow[h]-1'b1;
      end
      if(hit_pending)begin age<=0;hit_pending<=0;end
      else if(age!=63)age<=age+1'b1;
      // Travel/angle vary with the played phrase, but stop in silent windows.
      if(next_level>=32)begin
       // Long, eased bow strokes rather than a fast integer triangle.
       bow_phase<=bow_phase+9'd3+{7'd0,next_level[7:6]};
       bow_offset<=bow_curve>>>2; // +/-24 px (previously +/-6), eased reversal.
       bow_angle<=angle_curve>>>2; // Continuous signed slope / 1024.
       bow_tilt<=angle_curve>>>6;  // Coarse diagnostic, not sprite geometry.
      end
     end
    end
   end
  end
 end

 // Quarter-wave arithmetic LUT: 64 smooth phase positions, no BRAM/DSP.
 function signed [7:0] sine_curve;
  input [5:0] phase;
  reg [3:0] k;reg [6:0] v;
  begin
   k=phase[4]?~phase[3:0]:phase[3:0];
   case(k)
    0:v=0;1:v=10;2:v=19;3:v=28;4:v=37;5:v=45;6:v=53;7:v=61;
    8:v=68;9:v=74;10:v=80;11:v=85;12:v=89;13:v=92;14:v=94;15:v=96;
   endcase
   sine_curve=phase[5]?-$signed({1'b0,v}):$signed({1'b0,v});
  end
 endfunction

 function [5:0] holes_for;
  input [2:0] n;
  begin case(n)
   0:holes_for=6'b111111;1:holes_for=6'b011111;
   2:holes_for=6'b001111;3:holes_for=6'b000111;
   4:holes_for=6'b000011;5:holes_for=6'b000001;
   default:holes_for=0;
  endcase end
 endfunction

 // A small eighth note: oblique oval head, two-pixel stem, short flag.
 // Coordinates are relative to its head at the actual blowing hole; integer
 // shifts/comparisons only, so the sprites add neither DSP nor font BRAM.
 function note_shape;
  input signed [11:0] px,py;
  reg signed [11:0] head_x;
  begin
   head_x=px+(py>>>1);
   note_shape=(py>=-3 && py<=3 && head_x>=-5 && head_x<=5 &&
               ((py>=-2 && py<=2) || (head_x>=-3 && head_x<=3))) ||
              (px>=4 && px<=5 && py>=-20 && py<=0) ||
              (px>=6 && px<=11 && py>=-20+((px-6)>>>1) &&
               py<=-17+((px-6)>>>1));
  end
 endfunction

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
 // Eight opacity steps. Signed shift/add is exact floor((8-a)*bg+a*fg)/8;
 // no per-channel multiplier, no large 75/50/25 percent brightness jumps.
 function [7:0] mix_channel;
  input [7:0] bg,fg;input [2:0] a;
  reg signed [8:0] delta,result;
  reg signed [11:0] term0,term1,term2,product;
  begin
   delta=$signed({1'b0,fg})-$signed({1'b0,bg});
   term0=a[0]?{{3{delta[8]}},delta}:12'sd0;
   term1=a[1]?{{2{delta[8]}},delta,1'b0}:12'sd0;
   term2=a[2]?{delta[8],delta,2'b0}:12'sd0;
   product=(term0+term1)+term2;
   // Integer bg commutes with floor: bg + floor(a*(fg-bg)/8).
   // Add bg only after truncating the signed product, shortening carry chains.
   result=$signed({1'b0,bg})+$signed(product[11:3]);
   mix_channel=result[7:0];
  end
 endfunction
 function [23:0] mix8;
  input [23:0] bg,fg;input [2:0] a;
  begin mix8={mix_channel(bg[23:16],fg[23:16],a),
              mix_channel(bg[15:8],fg[15:8],a),mix_channel(bg[7:0],fg[7:0],a)};end
 endfunction

 // Pixel stage 1 ends after absolute differences and simple shape tests.
 // Snapshot control with the pixel: frame_tick may change age/level at this edge.
 reg valid_d,enable_d,stretch_y_d,string_light_d,music_note_d;
 reg [10:0] x_d,y_d,dx_d,dy_d;
 reg [23:0] rgb_d;
 reg [2:0] scene_d;
 reg [3:0] level_d,hole_glow_d;
 reg [2:0] music_alpha_d;
 reg [5:0] age_d;
 reg [10:0] string_y,pluck_y,dx,dy,target_x,target_y,hole_x,hole_y;
 reg [2:0] hole_no;
 reg [10:0] string_base;
 wire [16:0] times48=({x,5'd0}+{x,4'd0});
 wire [12:0] times3={2'd0,x}+{1'd0,x,1'b0};
 reg signed [17:0] string_fine;
 wire [16:0] string_product=times48+string_fine;
 reg stretch_y;
 reg string_light,music_note;
 reg [2:0] music_alpha;
 reg [5:0] music_age;
 reg signed [11:0] music_x,music_y;
 integer music_index;
 reg [11:0] distance;
 reg [2:0] opacity,echo_opacity;
 reg [23:0] selected_ink;
 reg [2:0] selected_alpha;
 reg solid_ink;
 // True circular/elliptic annuli, not visibly faceted octagonal distance.
 // Three small parallel products share across all mutually exclusive scenes.
 wire [6:0] ring_dy=stretch_y_d?{dy_d[5:0],1'b0}:dy_d[6:0];
 wire [13:0] ring_x2=dx_d[6:0]*dx_d[6:0];
 wire [13:0] ring_y2=ring_dy*ring_dy;
 wire [14:0] ring_distance2={1'b0,ring_x2}+{1'b0,ring_y2};
 wire [63:0] qin_bounds=qin_wave_bounds(age_d[4:0]);
 wire [31:0] main_bounds=scene_d==4?drum_wave_bounds(age_d[4:0]):qin_bounds[63:32];
 wire round_ring=dx_d<128 && (stretch_y_d?dy_d<64:dy_d<128) &&
                  ring_distance2>=main_bounds[31:16] && ring_distance2<=main_bounds[15:0];
 wire echo_ring=dx_d<128 && dy_d<64 && age_d>=6 &&
                  ring_distance2>=qin_bounds[31:16] && ring_distance2<=qin_bounds[15:0];
 always @*begin
  target_x=0;target_y=0;stretch_y=0;
  // Fit the photographed bright strings, not evenly spaced imaginary lines.
  // Coefficients measured over x=180..880; choices 6/7 reuse visible strings.
  string_base=338;string_fine=-$signed({5'd0,times3});pluck_y=274;
  case(note)
   1,7:begin string_base=343;string_fine=-$signed({5'd0,times3});pluck_y=279;end
   2:begin string_base=351;string_fine=-$signed({6'd0,x,1'b0});pluck_y=286;end
   3,6:begin string_base=362;string_fine=0;pluck_y=294;end
   4:begin string_base=374;string_fine=$signed({7'd0,x});pluck_y=305;end
   5:begin string_base=388;string_fine=$signed({5'd0,times3});pluck_y=316;end
  endcase
  string_y=string_base-string_product[16:8];
  hole_no=0;hole_x=446;hole_y=288;
  if(x<477)begin hole_no=0;hole_x=446;hole_y=288;end
  else if(x<539)begin hole_no=1;hole_x=508;hole_y=280;end
  else if(x<599)begin hole_no=2;hole_x=568;hole_y=273;end
  else if(x<659)begin hole_no=3;hole_x=628;hole_y=266;end
  else if(x<719)begin hole_no=4;hole_x=689;hole_y=259;end
  else begin hole_no=5;hole_x=746;hole_y=252;end
  // Select a centre BEFORE doing the distance arithmetic. Mutually exclusive
  // scenes share one pair of absolute differences and one ring metric.
  case(scene)
   1:begin target_x=`QIN_PLUCK_X;target_y=pluck_y;stretch_y=1;end
   2:begin
    target_x=`ERHU_CONTACT_X;
    // Exact floor correction at the string for |offset*angle|<1024.
    target_y=`ERHU_CONTACT_Y+((bow_offset[5]^bow_angle[5]) && bow_offset!=0 && bow_angle!=0);
   end
   3:begin target_x=hole_x;target_y=hole_y;end
   4:begin
    target_x=x>=512?`DRUM_RIGHT_X:`DRUM_LEFT_X;
    target_y=x>=512?`DRUM_RIGHT_Y:`DRUM_LEFT_Y;stretch_y=1;
   end
  endcase
  dx=difference(x,target_x);dy=difference(y,target_y);
  string_light=x>=180 && x<880 && level>=2 && age<32 && difference(y,string_y)<=1;
  // Three staggered little notes float up from the measured blowing hole
  // (113,332), not from the membrane hole or the six finger holes. At 60Hz
  // they rise 1/2 pixels per adopted audio frame and fade before wrapping.
  music_note=0;music_alpha=0;music_age=0;music_x=0;music_y=0;
  for(music_index=0;music_index<3;music_index=music_index+1)begin
   case(music_index)
    0:music_age=flow_phase[5:0];
    1:music_age=flow_phase[5:0]+6'd21;
    default:music_age=flow_phase[5:0]+6'd42;
   endcase
   music_x=$signed({1'b0,x})-12'sd113-$signed({7'd0,music_age[5:1]});
   music_y=$signed({1'b0,y})-12'sd332+$signed({6'd0,music_age})+
           $signed({7'd0,music_age[5:1]});
   if(level>=1 && music_age<60 && note_shape(music_x,music_y))begin
    music_note=1;
    music_alpha=music_age<40?7:(music_age<48?5:(music_age<56?3:1));
   end
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   valid_d<=0;enable_d<=0;stretch_y_d<=0;string_light_d<=0;
   music_note_d<=0;music_alpha_d<=0;hole_glow_d<=0;x_d<=0;y_d<=0;rgb_d<=0;
   dx_d<=0;dy_d<=0;scene_d<=0;level_d<=0;age_d<=0;
  end else begin
   valid_d<=valid;enable_d<=enable;stretch_y_d<=stretch_y;
   string_light_d<=string_light;music_note_d<=music_note;music_alpha_d<=music_alpha;
   hole_glow_d<=hole_glow[hole_no];x_d<=x;y_d<=y;rgb_d<=rgb;
   dx_d<=dx;dy_d<=dy;scene_d<=scene;level_d<=level;
   age_d<=scene==4 ? (x>=512?drum_right_age:drum_left_age) : age;
  end
 end
 // Pixel stage 2: shared ring metric and ink selection. Separate from blend.
 always @*begin
  selected_ink=0;selected_alpha=0;solid_ink=0;
  opacity=age_d<28?3'd7-age_d[4:2]:3'd0;
  echo_opacity=opacity>2?opacity-2:0;
  distance=round_distance(dx_d,stretch_y_d?(dy_d<<1):dy_d);
  if(enable_d)case(scene_d)
   1:begin
    if(string_light_d)begin selected_ink=24'hffce72;selected_alpha=opacity;end
    if(age_d<28 && round_ring && y_d<390)begin selected_ink=24'h5deaff;selected_alpha=opacity;end
    if(age_d<28 && echo_ring && y_d<390)begin selected_ink=24'h57e3d8;selected_alpha=echo_opacity;end
    if(age_d<7 && dx_d+dy_d<10)begin
     selected_ink=24'hb6fff1;selected_alpha=4;solid_ink=age_d<3;
    end
   end
   2:begin
    if(level_d>=2 && distance<level_d+8)begin selected_ink=24'hb6ece2;selected_alpha=4;end
    if(level_d>=7 && distance<4)begin selected_ink=24'he6fff4;solid_ink=1;end
   end
   3:begin
    if(hole_glow_d>=2 && dx_d<32 && dy_d<32 &&
       ring_distance2>=49 && ring_distance2<=400)begin
     selected_ink=24'h75dfff;selected_alpha=4;
    end
    if(hole_glow_d>=8 && dx_d<32 && dy_d<32 &&
       ring_distance2>=100 && ring_distance2<=169)begin
     selected_ink=24'hd5faff;solid_ink=1;
    end
    if(music_note_d)begin
     selected_ink=24'ha52635;selected_alpha=music_alpha_d;
    end
   end
   4:begin
    // The two photographed stick tips strike (377,224) and (661,229).
    // Each ring uses that stick's own onset age, matching independent contact.
    if(age_d<28 && round_ring &&
       x_d>225 && x_d<800 && y_d>150 && y_d<320)begin selected_ink=24'hffba63;selected_alpha=opacity;end
    if(age_d<3 && dx_d+dy_d<11)begin selected_ink=24'hfff1cb;solid_ink=1;end
   end
   default:begin selected_ink=0;selected_alpha=0;solid_ink=0;end
  endcase
 end
 reg valid_mix,solid_mix;
 reg [10:0] x_mix,y_mix;
 reg [23:0] bg_mix,ink_mix;
 reg [2:0] alpha_mix;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   valid_mix<=0;solid_mix<=0;x_mix<=0;y_mix<=0;bg_mix<=0;ink_mix<=0;alpha_mix<=0;
  end else begin
   valid_mix<=valid_d;x_mix<=x_d;y_mix<=y_d;bg_mix<=rgb_d;
   solid_mix<=solid_ink;ink_mix<=selected_ink;alpha_mix<=selected_alpha;
  end
 end
 // Pixel stage 3: one shared shift/add RGB mixer. All coordinates/valid
 // travel with the selected ink, including disabled/ordinary-scene bypass.
 always @(posedge clk or posedge rst)begin
  if(rst)begin out_valid<=0;out_x<=0;out_y<=0;out_rgb<=0;end
  else begin
   out_valid<=valid_mix;out_x<=x_mix;out_y<=y_mix;
   out_rgb<=solid_mix?ink_mix:mix8(bg_mix,ink_mix,alpha_mix);
  end
 end
endmodule
