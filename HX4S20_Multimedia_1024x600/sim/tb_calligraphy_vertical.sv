`timescale 1ns/1ps
// Independent reference for the 9/8-size, two-character vertical title.
// The source canvas stays 128x64 (left and right characters). The display is
// 72x72, a 12-pixel gap, then 72x72; no new font or image memory is required.
module tb_calligraphy_vertical;
 reg clk=0;
 always #5 clk=~clk;
 reg rst=1,frame_tick=0,enable=0,valid=0;
 reg [2:0] scene=0;
 reg [10:0] x=0,y=0;
 reg [23:0] rgb=0;
 wire out_valid;
 wire [10:0] out_x,out_y;
 wire [23:0] out_rgb;
 calligraphy_title dut(.*);

 reg reference_live=0,reference_pen_visible=0;
 integer reference_pen_x=0,reference_pen_y=0;
 reg expected_valid[0:2];
 reg [10:0] expected_x[0:2],expected_y[0:2];
 reg [23:0] expected_rgb[0:2];
 integer checks=0,hits=0,gaps=0,wet_hits=0,dry_hits=0;
 integer sample_scene,sample_local_x,sample_local_y;
 integer sample_glyph_x,sample_glyph_y,sample_character,sample_address;
 integer pipeline_index,channel_index,bg_byte,fg_byte,result_byte;
 integer distance_x,distance_y;
 reg sample_area,sample_hit,sample_wet;
 reg [23:0] sample_ink,sample_rgb;

 // A deliberately nonuniform address function detects swapped coordinates,
 // incorrect character selection, scale errors and inadvertent gap pixels.
 function automatic pattern_bit;
  input integer address;
  integer value;
  begin
   value=(address*73) ^ (address>>2) ^ (address>>7) ^ 32'h6d59;
   pattern_bit=(value%13)<6;
  end
 endfunction

 always @(posedge clk)begin
  if(rst)begin
   for(pipeline_index=0;pipeline_index<3;pipeline_index=pipeline_index+1)begin
    expected_valid[pipeline_index]=0;
    expected_x[pipeline_index]=0;expected_y[pipeline_index]=0;
    expected_rgb[pipeline_index]=0;
   end
  end else begin
   for(pipeline_index=2;pipeline_index>0;pipeline_index=pipeline_index-1)begin
    expected_valid[pipeline_index]=expected_valid[pipeline_index-1];
    expected_x[pipeline_index]=expected_x[pipeline_index-1];
    expected_y[pipeline_index]=expected_y[pipeline_index-1];
    expected_rgb[pipeline_index]=expected_rgb[pipeline_index-1];
   end
   sample_scene=scene;
   sample_local_x=$signed({1'b0,x})-(sample_scene==1?124:(sample_scene==4?64:44));
   sample_local_y=$signed({1'b0,y})-(sample_scene==4?32:(sample_scene==3?112:64));
   sample_area=sample_local_x>=0 && sample_local_x<72 &&
               ((sample_local_y>=0 && sample_local_y<72) ||
                (sample_local_y>=84 && sample_local_y<156));
   sample_character=sample_local_y>=84?1:0;
   sample_glyph_x=(sample_local_x*8)/9;
   sample_glyph_y=((sample_local_y-84*sample_character)*8)/9;
   sample_address=sample_glyph_y*128+sample_glyph_x+64*sample_character;
   sample_hit=enable && sample_scene>=1 && sample_scene<=4 &&
              reference_live && sample_area && pattern_bit(sample_address);
   distance_x=sample_glyph_x+64*sample_character-reference_pen_x;
   distance_y=sample_glyph_y-reference_pen_y;
   if(distance_x<0)distance_x=-distance_x;
   if(distance_y<0)distance_y=-distance_y;
   sample_wet=reference_pen_visible && distance_x+distance_y<=6;
   case(sample_scene)
    1:sample_ink=24'h720e2d;
    2:sample_ink=24'hffcc69;
    3:sample_ink=24'h123987;
    default:sample_ink=24'hffffff;
   endcase
   sample_rgb=rgb;
   if(sample_hit)begin
    // Calculate each channel independently with integer divisions. This is
    // intentionally not a copy of the DUT's packed-vector shift expression.
    for(channel_index=0;channel_index<3;channel_index=channel_index+1)begin
     bg_byte=(sample_rgb>>(8*channel_index)) & 255;
     fg_byte=(sample_ink>>(8*channel_index)) & 255;
     if(sample_wet)
      result_byte=bg_byte/4+fg_byte/2+fg_byte/4;
     else
      result_byte=bg_byte/8+fg_byte/2+fg_byte/4+fg_byte/8;
     sample_rgb[8*channel_index+:8]=result_byte;
    end
    hits=hits+1;
    if(sample_wet)wet_hits=wet_hits+1;else dry_hits=dry_hits+1;
   end
   if(sample_local_x>=0 && sample_local_x<72 && sample_local_y>=72 && sample_local_y<84)
    gaps=gaps+1;
   expected_valid[0]=valid;expected_x[0]=x;expected_y[0]=y;
   expected_rgb[0]=sample_rgb;
   #1;
   if(out_valid!==expected_valid[2] || out_x!==expected_x[2] || out_y!==expected_y[2])
    $fatal(1,"vertical title three-stage valid/xy mismatch at %0t",$time);
   if(out_rgb!==expected_rgb[2])
    $fatal(1,"vertical title RGB mismatch at %0t: scene=%0d pixel=(%0d,%0d) got=%h expected=%h",
           $time,scene,out_x,out_y,out_rgb,expected_rgb[2]);
   checks=checks+1;
  end
 end

 task step;
  begin @(posedge clk);#2;@(negedge clk);end
 endtask

 task fixture;
  input integer instrument;
  input integer wet;
  integer address;
  begin
   // The isolated display contract does not run the writer. Deposit a complete
   // but nonuniform canvas, then leave its state IDLE/done with frame_tick low.
   enable=0;reference_live=0;scene=instrument;
   repeat(4)step;
   dut.saved_scene=instrument;
   dut.scene_code=instrument-1;
   dut.state=4;dut.ready=1;dut.done=1;dut.budget=0;
   dut.pen_visible=wet;dut.pen_x=89;dut.pen_y=31;
   for(address=0;address<8192;address=address+1)
    dut.ink_canvas[address]=pattern_bit(address);
   reference_pen_visible=wet;reference_pen_x=89;reference_pen_y=31;
   reference_live=1;enable=1;
  end
 endtask

 task pixel;
  input integer px,py;
  begin
   x=px;y=py;valid=$urandom_range(0,1);rgb=$urandom;
   step;
  end
 endtask

 integer instrument,wet_mode,px,py,origin,origin_y,cycle;
 initial begin
  repeat(4)step;
  rst=0;
  // Every displayed position, all 864 gap pixels, and a two-pixel perimeter,
  // with two wet/dry modes for every instrument. Random source colors ensure
  // 7/8 and 3/4 opacity and channel rounding are actually distinguished.
  for(instrument=1;instrument<=4;instrument=instrument+1)begin
   origin=instrument==1?124:(instrument==4?64:44);
   origin_y=instrument==4?32:(instrument==3?112:64);
   for(wet_mode=0;wet_mode<2;wet_mode=wet_mode+1)begin
    fixture(instrument,wet_mode);
    for(py=(instrument==4?-10:-2);py<(instrument==4?166:158);py=py+1)
     for(px=(instrument==4?-12:-2);px<(instrument==4?84:74);px=px+1)
      pixel(origin+px,origin_y+py);
   end
  end

  // Disabled titles and scene zero (cover) must leave all pixels unchanged.
  enable=0;reference_live=0;
  for(cycle=0;cycle<1000;cycle=cycle+1)
   pixel($urandom_range(0,1023),$urandom_range(0,599));
  scene=0;enable=1;
  for(cycle=0;cycle<1000;cycle=cycle+1)
   pixel($urandom_range(40,200),$urandom_range(50,230));
  // Illegal scene codes also bypass; they cannot index another instrument.
  scene=7;
  for(cycle=0;cycle<257;cycle=cycle+1)
   pixel($urandom_range(40,200),$urandom_range(50,230));
  repeat(4)step;
  if(checks<99000 || hits<30000 || gaps<6900 || wet_hits<100 || dry_hits<30000)
   $fatal(1,"insufficient vertical-title coverage checks=%0d hits=%0d gap=%0d wet=%0d dry=%0d",
          checks,hits,gaps,wet_hits,dry_hits);
  $display("PASS vertical calligraphy: %0d pipeline samples, %0d ink hits (%0d dry/%0d wet), %0d gap probes; all four scenes, exact 72x72 inverse mapping, 12px gap, boundaries and bypass",
           checks,hits,dry_hits,wet_hits,gaps);
  $finish;
 end
 initial begin #5000000;$fatal(1,"vertical calligraphy timeout");end
endmodule
