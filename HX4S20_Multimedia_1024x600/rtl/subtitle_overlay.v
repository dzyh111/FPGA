// Characters are SD-clock written. One 64-glyph cache is replaced while the
// picture is hidden; font_ready publishes a complete scene-local font page.
// Visibility and progress are separate so SW2 cannot stall automatic playback.
module subtitle_overlay #(parameter ENABLE_FONT24=0,parameter TRANSITION_PALETTE=0,parameter WAVEFORM_ON_TOP=0)(
 input wr_clk,input wr_en,input [8:0] wr_addr,input [7:0] wr_data,
 input font_wr_en,input [9:0] font_wr_addr,input [17:0] font_wr_data,
 input font_ready,input font_quiet_request,
 input clk,input rst,input frame_tick,input enable,input show_picture,
 input intro_pause,input intro_restart,
 input [1:0] image_index,input [7:0] len0,len1,len2,len3,
 input valid,input sof,input last,input [23:0] rgb,
 input [23:0] subtitle_paper_rgb,input [23:0] subtitle_ink_rgb,
 input waveform_line,input waveform_halo,input [23:0] waveform_rgb,
 output reg intro_done,output reg [1:0] intro_done_index,output intro_restart_ack,
 output font_cache_idle,output reg font_quiet_ack,
 output reg out_valid,output reg out_sof,output reg out_last,output reg [23:0] out_rgb
);
 `include "font5x7.vh"
 `include "subtitle_punctuation24.vh"
 (* ram_style="block" *) reg [7:0] chars[0:511];
 // 1024 x 18 still uses two native 9K BRAMs. SUB2 uses their parity bits
 // for 32 native 24x24 glyphs; SUB1 retains the original 64 16x16 glyphs.
 // Legacy glyphs initialize the cache; SUBS.BIN replaces the complete page.
 (* ram_style="block" *) reg [17:0] font[0:1023];
 initial begin
`ifdef __ICARUS__
  $readmemh("rtl/subtitle_cache_init.mem",font);
`else
  $readmemh("subtitle_cache_init.mem",font);
`endif
 end
 always @(posedge wr_clk)begin
  if(wr_en)chars[wr_addr]<=wr_data;
  if(font_wr_en)font[font_wr_addr]<=font_wr_data;
 end
 reg [1:0] index0,index1,index_d;
 reg [31:0] lengths0,lengths1;
 reg en0,en1,en_d,pic0,pic1,pic_d,ready0,ready1,ready_d;
 (* ASYNC_REG="TRUE" *) reg quiet0,quiet1;
 reg quiet_seen,quiet_target;
 reg [1:0] quiet_drain;
 reg restart_d,scroll_half;
 assign intro_restart_ack=restart_d;
 assign font_cache_idle=!ready_d || !pic_d;
 reg [7:0] length_d;
 reg [12:0] scroll;
 reg [10:0] x,y;
 wire [10:0] px=sof?0:x;
 wire [10:0] py=sof?0:y;
 wire [13:0] text_x={3'b0,px}+{1'b0,scroll};
 wire [12:0] text_end=13'd1024+{length_d,5'b0};
 // AUTO can fade once the trailing cell edge reaches x=576, 64 pixels
 // before screen centre. Keep the full scroll extent for manual playback.
 wire [12:0] intro_ready_scroll=13'd448+{length_d,5'b0};
 wire [12:0] next_scroll=scroll+(scroll_half?13'd2:13'd1);
 // Keep the inset four-pixel artwork border visible after this final layer.
 // Text and paper share the same viewport, so entering/leaving glyphs cannot
 // paint over the side border. The full scroll and AUTO timing stay intact.
 wire subtitle_window=px>=6 && px<1018 && py>=552 && py<594;
 wire text_area=valid && subtitle_window && py>=560 && py<592 && text_x>=1024 &&
    text_x<{1'b0,text_end} && en_d && pic_d && ready_d;
 wire strip=valid && subtitle_window && en_d && pic_d && ready_d && length_d!=0;
 wire [13:0] local_x=text_x-14'd1024;
 wire [8:0] address={index_d,local_x[11:5]};
 reg [7:0] code;
 reg [3:0] row0,col0,col1;
 reg [17:0] font_q;
 reg chinese_q,large_chinese_q,punctuation_q,punctuation_pixel_q,format_q;
 // SUB2 tags carry their own layout through the synchronous character RAM.
 // SUB1 keeps 80..BF; native 24-point glyphs use E0..FF, punctuation C0/C1.
 // No separate asynchronous format mailbox or extra pixel stage is needed.
 wire code_native24=ENABLE_FONT24 && code[7:5]==3'b111;
 wire code_punctuation24=ENABLE_FONT24 && (code==8'hc0 || code==8'hc1);
 // Each four output rows cover three native rows. Three native rows are
 // exactly four 18-bit words. Prepare the word/bit indices beside chars RAM,
 // so the character -> font address path remains simple concatenation.
 wire [4:0] row32=py-11'd560;
 wire [6:0] col_times_three={text_x[4:0],1'b0}+{2'b0,text_x[4:0]};
 wire [4:0] native_col=col_times_three[6:2];
 wire [1:0] row_fraction=row32[1]?(row32[0]?2'd2:2'd1):2'd0;
 wire [5:0] native_offset={1'b0,native_col}+{2'b0,row_fraction,2'b0}+{3'b0,row_fraction,1'b0};
 wire offset_high=native_offset>=6'd18;
 wire [4:0] native_word={row32[4:2],2'b0}+{3'b0,row_fraction}+{4'b0,offset_high};
 wire [5:0] native_bit=offset_high?native_offset-6'd18:native_offset;
 wire [4:0] native_row={1'b0,row32[4:2],1'b0}+{2'b0,row32[4:2]}+{3'b0,row_fraction};
 reg [4:0] word0,bit0,bit1,native_row0,native_col0;
 wire [23:0] punctuation_row=subtitle_punctuation24(code[0],native_row0);
 wire [4:0] font_bit_index=5'd17-bit1;
 wire [4:0] punctuation_bit_index=5'd23-native_col0;
 wire [4:0] ascii_pixels;
 wire [15:0] ascii_expanded={2'b00,{2{ascii_pixels[4]}},{2{ascii_pixels[3]}},
                            {2{ascii_pixels[2]}},{2{ascii_pixels[1]}},{2{ascii_pixels[0]}},4'b0};
 wire [15:0] selected_font=chinese_q?font_q[15:0]:ascii_expanded;
 wire selected_pixel=format_q?
   (punctuation_q?punctuation_pixel_q:(large_chinese_q?font_q[font_bit_index]:ascii_expanded[15-col1])):
   selected_font[15-col1];
 ascii_font_rom u_ascii(.clk(clk),.code(code[6:0]),.row(row0[3:1]),.pixels(ascii_pixels));
 reg [23:0] rgb0,rgb1;
 reg [23:0] paper0,paper1,ink0,ink1;
 reg wave_line0,wave_line1,wave_halo0,wave_halo1;
 reg [23:0] wave_rgb0,wave_rgb1;
 wire [23:0] paper=TRANSITION_PALETTE?paper1:24'hffffff;
 wire [23:0] ink=TRANSITION_PALETTE?ink1:24'h101820;
 function [7:0] paper_mix;
  input [7:0] under,paper_color;
  begin paper_mix=paper_color-(paper_color>>2)+(under>>2);end
 endfunction
 reg v0,s0,l0,v1,s1,l1,area0,area1,strip0,strip1;
 wire [23:0] caption_rgb=area1 && selected_pixel?ink:
   (strip1?{paper_mix(rgb1[23:16],paper[23:16]),
     paper_mix(rgb1[15:8],paper[15:8]),paper_mix(rgb1[7:0],paper[7:0])}:rgb1);
 always @(posedge clk)begin
  code<=chars[address];row0<=(py-560)>>1;col0<=text_x[4:1];
  word0<=native_word;bit0<=native_bit[4:0];bit1<=bit0;
  native_row0<=native_row;native_col0<=native_col;
  font_q<=font[code_native24?{code[4:0],word0}:{code[5:0],row0}];
  chinese_q<=code[7:6]==2'b10;
  large_chinese_q<=code_native24;
  punctuation_q<=code_punctuation24;
  punctuation_pixel_q<=punctuation_row[punctuation_bit_index];
  format_q<=code_native24 || code_punctuation24;
  col1<=col0;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   index0<=0;index1<=0;index_d<=0;lengths0<=0;lengths1<=0;
   en0<=0;en1<=0;en_d<=0;pic0<=0;pic1<=0;pic_d<=0;
   ready0<=0;ready1<=0;ready_d<=0;length_d<=0;scroll<=512;
   restart_d<=0;scroll_half<=0;intro_done<=0;intro_done_index<=0;
   quiet0<=0;quiet1<=0;quiet_seen<=0;quiet_target<=0;quiet_drain<=0;font_quiet_ack<=0;
   x<=0;y<=0;rgb0<=0;rgb1<=0;v0<=0;s0<=0;l0<=0;v1<=0;s1<=0;l1<=0;
   paper0<=24'hffffff;paper1<=24'hffffff;ink0<=24'h101820;ink1<=24'h101820;
   wave_line0<=0;wave_line1<=0;wave_halo0<=0;wave_halo1<=0;wave_rgb0<=0;wave_rgb1<=0;
   area0<=0;area1<=0;strip0<=0;strip1<=0;
   out_valid<=0;out_sof<=0;out_last<=0;out_rgb<=0;
  end else begin
   index0<=image_index;index1<=index0;lengths0<={len3,len2,len1,len0};lengths1<=lengths0;
   en0<=enable;en1<=en0;pic0<=show_picture;pic1<=pic0;
   ready0<=font_ready;ready1<=ready0;
   quiet0<=font_quiet_request;quiet1<=quiet0;
   // The loader must wait for this token, not merely a possibly stale idle
   // level. Three clocks drain the last pixels after frame-latched masking.
   if(quiet_drain!=0)begin
    quiet_drain<=quiet_drain-1'b1;
    if(quiet_drain==1)font_quiet_ack<=quiet_target;
   end
   if(frame_tick)begin
    index_d<=index1;en_d<=en1;pic_d<=pic1;ready_d<=ready1;
    restart_d<=intro_restart;
    if(quiet_seen!=quiet1)begin
     ready_d<=0;quiet_seen<=quiet1;quiet_target<=quiet1;quiet_drain<=3;
    end
    case(index1)0:length_d<=lengths1[7:0];1:length_d<=lengths1[15:8];
      2:length_d<=lengths1[23:16];3:length_d<=lengths1[31:24];endcase
    // AUTO readiness is a stable, scene-tagged level. SD must observe it cleared
    // after a commit before arming the next completion event.
    if(index_d!=index1 || !pic1 || !pic_d || !ready1 || !ready_d ||
       restart_d!=intro_restart || quiet_seen!=quiet1)begin
     scroll<=512;scroll_half<=0;intro_done<=0;intro_done_index<=index1;
    end else if(!intro_pause)begin
     if(length_d==0)intro_done<=1;
     else begin
      scroll_half<=!scroll_half;
      if(next_scroll>=intro_ready_scroll)begin
       intro_done<=1;intro_done_index<=index_d;
      end
      if(next_scroll>=text_end)begin
       scroll<=0;
      end else scroll<=next_scroll;
     end
    end
   end
   if(valid)begin
    if(last)begin x<=0;y<=py==599?0:py+1'b1;end
    else begin x<=px+1'b1;y<=py;end
   end
   rgb0<=rgb;rgb1<=rgb0;v0<=valid;s0<=sof;l0<=last;v1<=v0;s1<=s0;l1<=l0;
   paper0<=subtitle_paper_rgb;paper1<=paper0;ink0<=subtitle_ink_rgb;ink1<=ink0;
   wave_line0<=waveform_line;wave_line1<=wave_line0;
   wave_halo0<=waveform_halo;wave_halo1<=wave_halo0;
   wave_rgb0<=waveform_rgb;wave_rgb1<=wave_rgb0;
   area0<=text_area;area1<=area0;strip0<=strip;strip1<=strip0;
   out_valid<=v1;out_sof<=s1;out_last<=l1;
   // Reuse the same trace geometry above both caption paper and lettering.
   // Masks and colour share the original three-clock subtitle pipeline.
   if(WAVEFORM_ON_TOP && wave_line1)out_rgb<=wave_rgb1;
   else if(WAVEFORM_ON_TOP && wave_halo1)out_rgb<={
     ((caption_rgb[23:16]>>1)+(wave_rgb1[23:16]>>1)),
     ((caption_rgb[15:8]>>1)+(wave_rgb1[15:8]>>1)),
     ((caption_rgb[7:0]>>1)+(wave_rgb1[7:0]>>1))};
   else out_rgb<=caption_rgb;
  end
 end
endmodule
