`timescale 1ns/1ps
// Independent landmark regression for the photographed instruments. Fixtures
// isolate raster geometry; the real-cue regression separately proves that
// neither drum is struck without a consumed recording-derived onset.
module tb_fx_alignment;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,valid=1;
 reg [2:0] scene=0,fixture_note=0;
 reg [10:0] x=0,y=0;
 reg [23:0] rgb=24'h204060;
 reg [5:0] fixture_age=63,fixture_left_age=63,fixture_right_age=63;
 reg [3:0] fixture_level=0;
 reg [7:0] fixture_flow=0;
 reg signed [5:0] fixture_offset=0,fixture_angle=0;
 reg [4:0] fixture_left_lift=0,fixture_right_lift=0;
 wire signed [5:0] bow_offset,bow_angle;
 wire signed [2:0] bow_tilt;
 wire [4:0] drum_offset,drum_right_offset;
 wire fx_valid,motion_valid;
 wire [10:0] fx_x,fx_y,motion_x,motion_y;
 wire [23:0] fx_rgb,motion_rgb;
 heritage_fx fx(.clk(clk),.rst(rst),.frame_tick(1'b0),.enable(1'b1),
  .stream_reset(1'b0),.scene(scene),.sample_consumed(1'b0),.sample_position(32'd0),
  .valid(valid),.x(x),.y(y),.rgb(rgb),.out_valid(fx_valid),
  .out_x(fx_x),.out_y(fx_y),.out_rgb(fx_rgb),.bow_offset(bow_offset),
  .bow_tilt(bow_tilt),.bow_angle(bow_angle),.drum_offset(drum_offset),
  .drum_right_offset(drum_right_offset));
 heritage_motion_layer motion(.clk(clk),.rst(rst),.scene(scene),
  .bow_offset(bow_offset),.bow_angle(bow_angle),.drum_offset(drum_offset),
  .drum_right_offset(drum_right_offset),.valid(valid),.x(x),.y(y),.rgb(rgb),
  .out_valid(motion_valid),.out_x(motion_x),.out_y(motion_y),.out_rgb(motion_rgb));
 integer checks=0,n,a,b,px,py,base,slope,pluck,contact_y,product;
 integer flute_changed[0:2],flow_index,note_core_count=0,halo_count=0;
 reg [23:0] flow_colors[0:2];
 integer pluck_map[0:7];
 integer base_map[0:7];
 integer slope_map[0:7];
 integer hole_x[0:5],hole_y[0:5];
 function [23:0] mix_reference;
  input [23:0] background,foreground;input integer alpha;
  integer r,g,b;
  begin
   r=((8-alpha)*background[23:16]+alpha*foreground[23:16])/8;
   g=((8-alpha)*background[15:8]+alpha*foreground[15:8])/8;
   b=((8-alpha)*background[7:0]+alpha*foreground[7:0])/8;
   mix_reference={r[7:0],g[7:0],b[7:0]};
  end
 endfunction
 function [23:0] flute_reference;
  input integer xx,yy,phase,strength;
  integer i,elapsed,head_x,head_y,local_x,local_y,slanted_x,alpha;
  reg hit;
  reg [23:0] value;
  begin
   value=24'h204060;
   for(i=0;i<3;i=i+1)begin
    elapsed=(phase+i*21)%64;
    head_x=113+elapsed/2;head_y=332-elapsed-elapsed/2;
    local_x=xx-head_x;local_y=yy-head_y;
    slanted_x=local_x+(local_y>>>1);
    // Independent integer silhouette: filled note-head, upright stem, flag.
    hit=(local_y>=-3 && local_y<=3 && slanted_x>=-5 && slanted_x<=5 &&
         ((local_y>=-2 && local_y<=2) || (slanted_x>=-3 && slanted_x<=3))) ||
        (local_x>=4 && local_x<=5 && local_y>=-20 && local_y<=0) ||
        (local_x>=6 && local_x<=11 && local_y>=-20+((local_x-6)>>>1) &&
         local_y<=-17+((local_x-6)>>>1));
    if(strength>=1 && elapsed<60 && hit)begin
     if(elapsed<40)alpha=7;else if(elapsed<48)alpha=5;
     else if(elapsed<56)alpha=3;else alpha=1;
     value=mix_reference(24'h204060,24'ha52635,alpha);
    end
   end
   flute_reference=value;
  end
 endfunction
 task pixel;
  input integer sc,xx,yy;
  begin
   @(negedge clk);scene=sc;x=xx;y=yy;
   repeat(4)@(negedge clk);
   if(!fx_valid || !motion_valid || {fx_x,fx_y}!=={x,y} ||
      {motion_x,motion_y}!=={x,y})
    $fatal(1,"landmark pipeline lost valid/coordinates at scene %0d %0d,%0d",sc,xx,yy);
   checks=checks+1;
  end
 endtask
 task expect_color;
  input [23:0] expected;
  input [255:0] reason;
  begin
   if(fx_rgb!==expected)
    $fatal(1,"%0s: scene %0d pixel %0d,%0d got %h expected %h",reason,scene,x,y,fx_rgb,expected);
  end
 endtask
 initial begin
  pluck_map[0]=274;pluck_map[1]=279;pluck_map[2]=286;pluck_map[3]=294;
  pluck_map[4]=305;pluck_map[5]=316;pluck_map[6]=294;pluck_map[7]=279;
  base_map[0]=338;base_map[1]=343;base_map[2]=351;base_map[3]=362;
  base_map[4]=374;base_map[5]=388;base_map[6]=362;base_map[7]=343;
  slope_map[0]=45;slope_map[1]=45;slope_map[2]=46;slope_map[3]=48;
  slope_map[4]=49;slope_map[5]=51;slope_map[6]=48;slope_map[7]=45;
  hole_x[0]=446;hole_y[0]=288;hole_x[1]=508;hole_y[1]=280;
  hole_x[2]=568;hole_y[2]=273;hole_x[3]=628;hole_y[3]=266;
  hole_x[4]=689;hole_y[4]=259;hole_x[5]=746;hole_y[5]=252;
  repeat(4)@(negedge clk);rst=0;
  force fx.level=fixture_level;force fx.note=fixture_note;force fx.age=fixture_age;
  force fx.drum_left_age=fixture_left_age;force fx.drum_right_age=fixture_right_age;
  force fx.bow_offset=fixture_offset;force fx.bow_angle=fixture_angle;
  force fx.drum_offset=fixture_left_lift;force fx.drum_right_offset=fixture_right_lift;
  force fx.flow_phase=fixture_flow;
  fixture_level=12;
  // Eight cues follow measured string equations; repeated choices reuse one
  // of the visible strings rather than adding invented evenly spaced lines.
  for(n=0;n<8;n=n+1)begin
   fixture_note=n;fixture_age=0;pluck=pluck_map[n];
   pixel(1,365,pluck);expect_color(24'hb6fff1,"guqin pluck centre");
   if(fx.target_x!==11'd365 || fx.target_y!==pluck)
    $fatal(1,"guqin note %0d pluck landmark moved",n);
   fixture_age=10;base=base_map[n];slope=slope_map[n];
   for(a=0;a<3;a=a+1)begin
    case(a)0:px=180;1:px=530;default:px=879;endcase
    py=base-(px*slope)/256;
    pixel(1,px,py);expect_color(mix_reference(rgb,24'hffce72,5),"guqin measured string");
    pixel(1,px,py+3);expect_color(rgb,"guqin off-string gap");
   end
  end
  fixture_age=63;
  // Motion samples source_y=y+floor(offset*angle/1024) at x=523.
  // The contact glow must move by the inverse integer-floor correction.
  for(a=-24;a<=24;a=a+12)for(b=-24;b<=24;b=b+12)begin
   fixture_offset=a;fixture_angle=b;product=a*b;
   contact_y=393-(product>>>10);
   pixel(2,523,contact_y);expect_color(24'he6fff4,"erhu string contact");
   if(fx.target_x!==11'd523 || fx.target_y!==contact_y ||
      $signed(motion.source_y_d)!==393 || $signed(motion.source_x)!==(523-a))
    $fatal(1,"bow contact offset=%0d angle=%0d light=%0d source=%0d,%0d",
      a,b,fx.target_y,$signed(motion.source_x),$signed(motion.source_y_d));
   pixel(2,523,contact_y+4);expect_color(24'h6b96a1,"erhu core edge");
  end
  // Restore the original six calibrated annuli. Their black centres remain
  // photographic; the phrase-cue art map must not move any measured hole.
  fixture_offset=0;fixture_angle=0;
  fixture_level=12;fixture_flow=0;
  for(n=0;n<6;n=n+1)fx.hole_glow[n]=15;
  for(n=0;n<6;n=n+1)begin
   pixel(3,hole_x[n],hole_y[n]);expect_color(rgb,"flute black hole centre");
   if(fx.target_x!==hole_x[n] || fx.target_y!==hole_y[n])
    $fatal(1,"flute measured hole target moved");
   for(a=-21;a<=21;a=a+1)for(b=-21;b<=21;b=b+1)begin
    pixel(3,hole_x[n]+a,hole_y[n]+b);
    if(a*a+b*b>=100 && a*a+b*b<=169)
     expect_color(24'hd5faff,"flute bright inner annulus");
    else if(a*a+b*b>=49 && a*a+b*b<=400)begin
     expect_color(mix_reference(rgb,24'h75dfff,4),"flute soft outer annulus");
     halo_count=halo_count+1;
    end else expect_color(rgb,"flute annulus exact edges and black centre");
   end
  end
  for(n=0;n<6;n=n+1)fx.hole_glow[n]=0;
  for(px=12;px<=100;px=px+4)for(py=200;py<=350;py=py+5)begin
   pixel(3,px,py);expect_color(rgb,"former long flute jet removed");
  end
  // The removed long wave never returns. Notes are local to the blowing hole.
  for(py=150;py<286;py=py+4)for(px=250;px<850;px=px+4)begin
   pixel(3,px,py);expect_color(rgb,"continuous wave removed");
  end
  // Independently raster all three floating notes and their 7/5/3/1 alpha
  // decay at three distinct phases. No note touches the membrane/finger holes.
  for(flow_index=0;flow_index<3;flow_index=flow_index+1)begin
   case(flow_index)0:fixture_flow=0;1:fixture_flow=17;default:fixture_flow=43;endcase
   flute_changed[flow_index]=0;
   for(py=212;py<344;py=py+1)for(px=100;px<160;px=px+1)begin
    pixel(3,px,py);
    expect_color(flute_reference(px,py,fixture_flow,12),"flute floating note independent raster");
    if(fx_rgb!=rgb)flute_changed[flow_index]=flute_changed[flow_index]+1;
    if(fx_rgb==mix_reference(rgb,24'ha52635,7))note_core_count=note_core_count+1;
   end
   pixel(3,113,332);flow_colors[flow_index]=fx_rgb;
  end
  if(flute_changed[0]<250 || flute_changed[1]<250 || flute_changed[2]<250 ||
     note_core_count<400 || halo_count<1000)
   $fatal(1,"flute illustration absent: changed=%0d/%0d/%0d cores=%0d halos=%0d",
    flute_changed[0],flute_changed[1],flute_changed[2],note_core_count,halo_count);
  if(flow_colors[0]===flow_colors[1] && flow_colors[1]===flow_colors[2])
   $fatal(1,"flute phases produced no visible movement");
  fixture_level=1;fixture_flow=0;
  pixel(3,113,332);expect_color(mix_reference(rgb,24'ha52635,7),"quiet flute source note visible");
  fixture_level=0;
  for(py=212;py<344;py=py+2)for(px=100;px<160;px=px+2)begin
   pixel(3,px,py);expect_color(rgb,"silent flute illustration off");
  end
  // Independent impact ages centre flashes on the actual two stick tips.
  for(a=0;a<2;a=a+1)begin
   px=a==0?377:661;py=a==0?224:229;
   fixture_left_age=a==0?0:63;fixture_right_age=a==1?0:63;
   fixture_left_lift=0;fixture_right_lift=0;
   pixel(4,px,py);expect_color(24'hfff1cb,"drum photographed impact");
   if(fx.target_x!==px || fx.target_y!==py ||
      $signed(motion.source_y_d)!==py)
    $fatal(1,"drum impact landmark differs from sprite pivot");
   pixel(4,a==0?661:377,a==0?229:224);expect_color(rgb,"unstruck drum stays quiet");
   // At the pivot, a 30px lifted sprite maps exactly back to its source tip.
   fixture_left_lift=a==0?30:0;fixture_right_lift=a==1?30:0;
   fixture_left_age=63;fixture_right_age=63;
   pixel(4,px,py-30);expect_color(rgb,"lifted drum has no fake impact");
   if($signed(motion.source_y_d)!==py)
    $fatal(1,"enlarged drum lift no longer pivots at photographed tip");
  end
  $display("PASS FX alignment: %0d probes; measured strings/bow/drum, restored six hole annuli (%0d halo probes), source-note raster %0d/%0d/%0d with %0d dense ink probes, removed long wave and quiet/silent gates",checks,halo_count,flute_changed[0],flute_changed[1],flute_changed[2],note_core_count);
  $finish;
 end
 initial begin #20000000;$fatal(1,"FX alignment timeout");end
endmodule
