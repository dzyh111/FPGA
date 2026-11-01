// Display-time percentage zoom of an existing 1024x600 RGB565 SDRAM frame.
// The reader supplies one complete selected source row for each image row.
// Cropped source words are drained in horizontal blanking; vertical repeats
// are fetched from SDRAM again. No extra line RAM or TF-card reload is needed.
// Request at T, synchronous NOREG FIFO data after T, output at T+1, matching
// video_pixels_rgb565. Source XY follows the artwork; screen XY follows OSD.
module video_zoom_rgb565(
 input clk,input rst,input frame_tick,input line_start,input active,
 input display_enabled,input cover_active,input [2:0] zoom_index,
 input [10:0] x,input [10:0] y,input [31:0] read_data,
 output read_en,output reg valid,
 output reg [10:0] src_x,src_y,screen_x,screen_y,
 output reg [23:0] rgb
);
 reg [10:0] left_edge,top_edge,image_width,image_height,start_x,start_y;
 reg [2:0] denominator,increment,start_x_rem;
 wire [2:0] effective_zoom=cover_active?3'd2:zoom_index;
 always @* begin
  left_edge=0;top_edge=0;image_width=1024;image_height=600;
  start_x=0;start_y=0;denominator=1;increment=1;start_x_rem=0;
  case(effective_zoom)
   0:begin left_edge=256;top_edge=150;image_width=512;image_height=300;
     increment=2;end
   1:begin left_edge=128;top_edge=75;image_width=768;image_height=450;
     denominator=3;increment=4;end
   3:begin start_x=102;start_y=60;denominator=5;increment=4;start_x_rem=2;end
   4:begin start_x=170;start_y=100;denominator=3;increment=2;start_x_rem=2;end
   default:;
  endcase
 end
 reg [10:0] source_x,source_y;
 reg [2:0] x_rem,y_rem;
 wire [3:0] x_sum={1'b0,x_rem}+{1'b0,increment};
 wire [3:0] y_sum={1'b0,y_rem}+{1'b0,increment};
 // Evaluate candidate remainders in parallel and reuse their borrow bits.
 // Five-bit differences cover the full sum 0..15 and 2*denominator 0..14;
 // bit 4 is exactly unsigned borrow, so no compare/select precedes subtraction.
 wire [4:0] x_minus_one={1'b0,x_sum}-{2'b0,denominator};
 wire [4:0] x_minus_two={1'b0,x_sum}-{1'b0,denominator,1'b0};
 wire [4:0] y_minus_one={1'b0,y_sum}-{2'b0,denominator};
 wire [4:0] y_minus_two={1'b0,y_sum}-{1'b0,denominator,1'b0};
 wire [1:0] x_step=!x_minus_two[4]?2'd2:!x_minus_one[4]?2'd1:2'd0;
 wire [1:0] y_step=!y_minus_two[4]?2'd2:!y_minus_one[4]?2'd1:2'd0;
 wire [3:0] next_x_rem=!x_minus_two[4]?x_minus_two[3:0]:
                       !x_minus_one[4]?x_minus_one[3:0]:x_sum;
 wire [3:0] next_y_rem=!y_minus_two[4]?y_minus_two[3:0]:
                       !y_minus_one[4]?y_minus_one[3:0]:y_sum;
 wire image_row=display_enabled && y>=top_edge && y<top_edge+image_height;
 wire image_pixel=active && image_row && x>=left_edge && x<left_edge+image_width;
 reg [9:0] words_consumed;
 reg [9:0] last_word;
 reg word_valid;
 wire need_word=image_pixel && (!word_valid || source_x[10:1]!=last_word);
 // x wraps to 1888..2047 in the 160 clocks before active x=0. Begin
 // draining one clock after line_start so its synchronous clear wins.
 wire prefix_word=image_row && !line_start && !active && x>=11'd1888 &&
                  words_consumed<{1'b0,start_x[10:1]};
 wire suffix_word=image_row && !active && x>=11'd1024 && x<11'd1888 &&
                  words_consumed<10'd512;
 assign read_en=need_word || prefix_word || suffix_word;
 reg active_d,image_d,half_d;
 reg [10:0] src_x_d,src_y_d,screen_x_d,screen_y_d;
 wire [15:0] selected=half_d?read_data[15:0]:read_data[31:16];
 wire [23:0] expanded={{selected[15:11],selected[15:13]},
                       {selected[10:5],selected[10:9]},
                       {selected[4:0],selected[4:2]}};
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   source_x<=0;source_y<=0;x_rem<=0;y_rem<=0;
   words_consumed<=0;last_word<=0;word_valid<=0;
   active_d<=0;image_d<=0;half_d<=0;
   src_x_d<=2047;src_y_d<=2047;screen_x_d<=0;screen_y_d<=0;
   valid<=0;src_x<=2047;src_y<=2047;screen_x<=0;screen_y<=0;rgb<=0;
  end else begin
   active_d<=active;image_d<=image_pixel;half_d<=source_x[0];
   src_x_d<=image_pixel?source_x:11'd2047;
   src_y_d<=image_pixel?source_y:11'd2047;
   screen_x_d<=x;screen_y_d<=y;
   valid<=active_d;src_x<=src_x_d;src_y<=src_y_d;
   screen_x<=screen_x_d;screen_y<=screen_y_d;
   rgb<=image_d?expanded:24'h101c30;
   if(frame_tick)begin
    source_y<=start_y;y_rem<=0;
   end
   if(line_start)begin
    source_x<=start_x;x_rem<=start_x_rem;
    words_consumed<=0;last_word<=0;word_valid<=0;
    // This also adopts a zoom latched by the top on frame_tick. Geometry
    // has settled for the entire vertical blank before this first row.
    if(y==top_edge)begin source_y<=start_y;y_rem<=0;end
    else if(image_row)begin source_y<=source_y+y_step;y_rem<=next_y_rem[2:0];end
   end else begin
    if(read_en)words_consumed<=words_consumed+1'b1;
    if(need_word)begin last_word<=source_x[10:1];word_valid<=1;end
    if(image_pixel)begin source_x<=source_x+x_step;x_rem<=next_x_rem[2:0];end
   end
  end
 end
endmodule
