// Stroke-ordered handwriting, not a whole-character fade or rectangular wipe.
// Four Xingkai titles; explicit pen lifts, a moving masked brush and persistent
// ink canvas. No audio-driven stripes. Lossless dictionary-coded glyph ROM.
// Font/path sources and adaptations: media_tools/calligraphy/asset_report.json.
// Arm at a frame boundary before clearing (8192 clocks); subsequent brush
// work uses <400 clocks/frame, inside this design's vertical blank interval.
// Display only: two 72x72 characters stacked vertically, with a 12px gap.
// Reuse the original 128x64 canvas/paths; no extra RAM or multiplier.
// Pixel valid/xy/RGB latency is exactly THREE clocks, like the removed overlay.
module calligraphy_title #(parameter TITLE_X=44,parameter TITLE_Y=64)(
 input clk,input rst,input frame_tick,input enable,input [2:0] scene,
 input valid,input [10:0] x,input [10:0] y,input [23:0] rgb,
 output reg out_valid,output reg [10:0] out_x,output reg [10:0] out_y,
 output reg [23:0] out_rgb
);
`include "calligraphy_bounds.vh"
 (* ram_style="block" *) reg [8:0] glyph_index_rom[0:2047];
 (* ram_style="block" *) reg [15:0] glyph_dictionary_rom[0:511];
 (* ram_style="block" *) reg [13:0] path_rom[0:511];
 (* ram_style="block" *) reg ink_canvas[0:8191];
 initial begin
`ifdef __ICARUS__
  $readmemh("rtl/calligraphy_glyph_index.hex",glyph_index_rom);
  $readmemh("rtl/calligraphy_glyph_dictionary.hex",glyph_dictionary_rom);
  $readmemh("rtl/calligraphy_paths.hex",path_rom);
`else
  $readmemh("calligraphy_glyph_index.hex",glyph_index_rom);
  $readmemh("calligraphy_glyph_dictionary.hex",glyph_dictionary_rom);
  $readmemh("calligraphy_paths.hex",path_rom);
`endif
 end
`ifdef __ICARUS__
 // Simulation-only independent uncompressed reference for every final pixel.
 reg glyph_rom[0:32767];
 initial $readmemh("rtl/calligraphy_glyphs.hex",glyph_rom);
`endif
 localparam CLEAR=0,FETCH=1,FETCH_WAIT=2,LOAD=3,IDLE=4,DRAW=5,DRAIN=6,ARM=7;
 reg [2:0] state,saved_scene;
 reg [1:0] scene_code,budget;
 reg [12:0] clear_address;
 reg [8:0] path_address,last_address;
 reg [13:0] path_q;
 reg ready,done,pen_visible;
 reg [6:0] pen_x,target_x;
 reg [5:0] pen_y,target_y;
 reg [3:0] pause_frames,scan_i,scan_j;
 reg [1:0] drain_cycle;
 wire legal_scene=scene>=1 && scene<=4;
 wire same_scene=scene==saved_scene;
 wire [6:0] moved_x=pen_x<target_x?pen_x+1'b1:(pen_x>target_x?pen_x-1'b1:pen_x);
 wire [5:0] moved_y=pen_y<target_y?pen_y+1'b1:(pen_y>target_y?pen_y-1'b1:pen_y);
 wire [3:0] abs_i=scan_i>4?scan_i-4:4-scan_i;
 wire [3:0] abs_j=scan_j>4?scan_j-4:4-scan_j;
 wire circle=(abs_i==4?abs_j==0:(abs_j==4?abs_i==0:
                  (abs_i==3?abs_j<=2:(abs_j==3?abs_i<=2:1'b1))));
 wire signed [8:0] brush_x=$signed({2'd0,pen_x})+$signed({5'd0,scan_i})-9'sd4;
 wire signed [8:0] brush_y=$signed({3'd0,pen_y})+$signed({5'd0,scan_j})-9'sd4;
 wire brush_request=state==DRAW && circle && brush_x>=0 && brush_x<128 && brush_y>=0 && brush_y<64 && brush_x[6]==pen_x[6];
 wire [14:0] glyph_address={scene_code,brush_x[6],brush_y[5:0],brush_x[5:0]};
 reg [8:0] glyph_index_q;
 reg [15:0] glyph_word_q;
 reg [3:0] glyph_bit_q,glyph_bit_qq;
 wire glyph_q=glyph_word_q[glyph_bit_qq];
 reg brush_valid_0,brush_valid;
 reg [12:0] brush_address_0,brush_address;
 // Guqin's far-left dark furniture would hide the lower ink character.
 // Keep it in the upper-left, just 80px right of the other scene titles.
 wire [10:0] title_origin_x=scene==1?TITLE_X+80:(scene==4?TITLE_X+20:TITLE_X);
 // Bright white drum ink sits on the far-left tree trunk; no plaque/frame.
 wire [10:0] title_origin_y=scene==4?TITLE_Y-32:(scene==3?TITLE_Y+48:TITLE_Y);
 wire [10:0] local_x=x-title_origin_x,local_y=y-title_origin_y;
 wire second_character=local_y>=84;
 wire [6:0] glyph_screen_y=second_character?local_y-84:local_y;
 function [5:0] from72;
  input [6:0] p;reg [3:0] skip;
  begin
   // Exactly floor(p*8/9) for 0..71. Threshold/subtract avoids a divider.
   if(p==0)skip=0;else if(p<=9)skip=1;else if(p<=18)skip=2;
   else if(p<=27)skip=3;else if(p<=36)skip=4;else if(p<=45)skip=5;
   else if(p<=54)skip=6;else if(p<=63)skip=7;else skip=8;
   from72=p-skip;
  end
 endfunction
 wire [5:0] glyph_x=from72(local_x[6:0]),glyph_y=from72(glyph_screen_y);
 wire [6:0] canvas_x={second_character,glyph_x};
 wire title_area=x>=title_origin_x && x<title_origin_x+72 && y>=title_origin_y &&
                 (local_y<72 || (local_y>=84 && local_y<156));
 wire [12:0] display_address={glyph_y,canvas_x};
 reg canvas_q;
 // No memory reset: one writer plus one independent video read infer BRAMs.
 always @(posedge clk)begin
  path_q<=path_rom[path_address];
  glyph_index_q<=glyph_index_rom[glyph_address[14:4]];
  glyph_word_q<=glyph_dictionary_rom[glyph_index_q];
  glyph_bit_q<=glyph_address[3:0];glyph_bit_qq<=glyph_bit_q;
  brush_valid_0<=brush_request;brush_valid<=brush_valid_0;
  brush_address_0<={brush_y[5:0],brush_x[6:0]};brush_address<=brush_address_0;
  canvas_q<=ink_canvas[display_address];
  if(!rst && enable && legal_scene && same_scene)begin
   if(state==CLEAR)ink_canvas[clear_address]<=0;
   else if((state==DRAW || state==DRAIN) && brush_valid && glyph_q)
    ink_canvas[brush_address]<=1;
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=ARM;saved_scene<=0;scene_code<=0;budget<=0;clear_address<=0;
   path_address<=0;last_address<=0;ready<=0;done<=0;pen_visible<=0;
   pen_x<=0;pen_y<=0;target_x<=0;target_y<=0;pause_frames<=0;
   scan_i<=0;scan_j<=0;drain_cycle<=0;
  end else begin
   saved_scene<=scene;
   if(!enable || !legal_scene || !same_scene)begin
    state<=ARM;clear_address<=0;ready<=0;done<=0;budget<=0;pen_visible<=0;
    path_address<=title_start(scene);last_address<=title_end(scene);
    scene_code<=scene-1'b1;pause_frames<=0;
   end else begin
    if(frame_tick)begin
     if(pause_frames!=0)begin pause_frames<=pause_frames-1'b1;budget<=0;end
     else budget<=2;
    end
    case(state)
     ARM:if(frame_tick)begin state<=CLEAR;clear_address<=0;budget<=0;end
     CLEAR:begin
      if(clear_address==8191)begin ready<=1;state<=FETCH;end
      else clear_address<=clear_address+1'b1;
     end
     FETCH:state<=FETCH_WAIT;
     FETCH_WAIT:state<=LOAD;
     LOAD:begin
      target_x<=path_q[12:6];target_y<=path_q[5:0];
      if(path_q[13])begin
       // Lift, relocate WITHOUT connecting ink, then put the brush down.
       pause_frames<=path_q[12]!=pen_x[6]?6:2;
       pen_x<=path_q[12:6];pen_y<=path_q[5:0];pen_visible<=0;budget<=0;
      end
      state<=IDLE;
     end
     IDLE:if(!done && pause_frames==0 && budget!=0)begin
      pen_x<=moved_x;pen_y<=moved_y;pen_visible<=1;
      scan_i<=0;scan_j<=0;budget<=budget-1'b1;state<=DRAW;
     end
     DRAW:begin
      if(scan_i==8)begin
       scan_i<=0;
       if(scan_j==8)begin state<=DRAIN;drain_cycle<=0;end
       else scan_j<=scan_j+1'b1;
      end else scan_i<=scan_i+1'b1;
     end
     DRAIN:if(drain_cycle<2)drain_cycle<=drain_cycle+1'b1;else begin
      if(pen_x==target_x && pen_y==target_y)begin
       if(path_address==last_address)begin done<=1;pen_visible<=0;state<=IDLE;end
       else begin path_address<=path_address+1'b1;state<=FETCH;end
      end else state<=IDLE;
     end
     default:begin state<=ARM;ready<=0;budget<=0;end
    endcase
   end
  end
 end

 reg valid_d,area_d,wet_d;
 reg [10:0] x_d,y_d;
 reg [23:0] rgb_d,ink_d;
 reg valid_2,hit_2,wet_2;
 reg [10:0] x_2,y_2;
 reg [23:0] rgb_2,ink_2;
 wire [7:0] pen_dx=canvas_x>pen_x?canvas_x-pen_x:pen_x-canvas_x;
 wire [6:0] pen_dy=glyph_y>pen_y?glyph_y-pen_y:pen_y-glyph_y;
 function [23:0] ink_color;
  input [2:0] instrument;
  begin case(instrument)
   1:ink_color=24'h720e2d;2:ink_color=24'hffcc69;
   3:ink_color=24'h123987;default:ink_color=24'hffffff;
  endcase end
 endfunction
 function [23:0] blend_ink;
  input [23:0] bg,fg;input wet;
  reg [7:0] r,g,b;
  begin
   if(wet)begin
    r=(bg[23:16]>>2)+(fg[23:16]>>1)+(fg[23:16]>>2);
    g=(bg[15:8]>>2)+(fg[15:8]>>1)+(fg[15:8]>>2);
    b=(bg[7:0]>>2)+(fg[7:0]>>1)+(fg[7:0]>>2);
   end else begin
    r=(bg[23:16]>>3)+(fg[23:16]>>1)+(fg[23:16]>>2)+(fg[23:16]>>3);
    g=(bg[15:8]>>3)+(fg[15:8]>>1)+(fg[15:8]>>2)+(fg[15:8]>>3);
    b=(bg[7:0]>>3)+(fg[7:0]>>1)+(fg[7:0]>>2)+(fg[7:0]>>3);
   end
   blend_ink={r,g,b};
  end
 endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   valid_d<=0;area_d<=0;wet_d<=0;x_d<=0;y_d<=0;rgb_d<=0;ink_d<=0;
   valid_2<=0;hit_2<=0;wet_2<=0;x_2<=0;y_2<=0;rgb_2<=0;ink_2<=0;
   out_valid<=0;out_x<=0;out_y<=0;out_rgb<=0;
  end else begin
   valid_d<=valid;x_d<=x;y_d<=y;
   rgb_d<=rgb;
   ink_d<=ink_color(scene);
   area_d<=enable && legal_scene && same_scene && ready && title_area;
   wet_d<=pen_visible && pen_dx+pen_dy<=6;
   valid_2<=valid_d;x_2<=x_d;y_2<=y_d;rgb_2<=rgb_d;ink_2<=ink_d;
   hit_2<=area_d && canvas_q;wet_2<=wet_d;
   out_valid<=valid_2;out_x<=x_2;out_y<=y_2;
   out_rgb<=hit_2?blend_ink(rgb_2,ink_2,wet_2):rgb_2;
  end
 end
endmodule
