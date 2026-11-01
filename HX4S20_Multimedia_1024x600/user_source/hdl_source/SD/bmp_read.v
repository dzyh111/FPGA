module bmp_read #(
    // Cover failures are optional-media errors. At the board's 40 MHz this
    // is one second per sector/ACK, before the controller's two-second stall.
    parameter [26:0] COVER_TIMEOUT_CYCLES = 27'd40000000
)(
    input                       clk,
    input                       rst,
    output                      ready,

    // FAT32 root directory: find up to four BMP files.
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [2:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [2:0]            scan_found_total,
    output reg [7:0]            scan_found_duration,
    output reg [1:0]            scan_found_scale,
    output reg [2:0]            scan_found_scene,
    // Optional cover is NOT a playlist entry. Opaque load handle 4.
    output reg                  cover_found,
    // Sticky until reset/scan_start; a failed cover must not discard images.
    output reg                  cover_error,
    input                       cover_cancel,
    output reg                  subtitle_wr_en,
    output reg [8:0]            subtitle_wr_addr,
    output reg [7:0]            subtitle_wr_data,
    output reg [7:0]            subtitle_len0,
    output reg [7:0]            subtitle_len1,
    output reg [7:0]            subtitle_len2,
    output reg [7:0]            subtitle_len3,
    input [2:0]                 font_scene_request,
    input [1:0]                 font_index_request,
    input                       font_cache_idle,
    input                       font_quiet_ack,
    output reg                  font_quiet_request,
    output reg                  font_wr_en,
    output reg [9:0]            font_wr_addr,
    output reg [17:0]           font_wr_data,
    output reg                  font_ready,
    output reg                  font_format24,
    output reg [2:0]            font_loaded_scene,
    output reg [1:0]            font_loaded_index,
    output                      packed_subtitles,

    input                       audio_stream_enable,
    input                       audio_fifo_afull,
    input [2:0]                 audio_scene,
    input                       audio_restart,
    output reg                  audio_reset_busy,
    output reg [31:0]           audio_sample_total,
    output reg                  audio_file_present,
    output reg                  audio_format_error,
    output reg                  audio_pcm_wr,
    output reg [31:0]           audio_pcm_word,

    // load_sector is a file index returned by scan_found_sector.
    input                       load_start,
    input  [31:0]               load_sector,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg [15:0]           source_width,
    output reg [15:0]           source_height,
    output reg                  image_start,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data
);

// Read-only FAT32 root-directory reader. load_sector is an opaque file index,
// retained for compatibility with the playback controller. No physical scan.
localparam IDLE=0, START=1, RX=2, BOOT=3, GEOM=4, ROOT=5,
           DIR=6, NEXT_DIR=7, FAT_DIR=8, HDR=9, ACK=10,
           PIX=11, NEXT_PIX=12, FAT_PIX=13, FAIL=14,
           PREP_FILES=15,PLAY_TEXT=16,AFTER_PLAY=17,SUB_TEXT=18,
           AFTER_SUB=19,EMIT_FILES=20,NEXT_TEXT=21,FAT_TEXT=22,END_TEXT=23,
           VALIDATE_START=24,VALIDATE_HDR=25,AFTER_VALIDATE=26,
           WAV_HDR=27,AUDIO_DATA=28,AUDIO_NEXT=29,FAT_AUDIO=30,AUDIO_READY=31,
           PACK_READ=32,PACK_SEEK=33,PACK_NEXT=34,FAT_PACK=35,PACK_WAIT=36;
reg [5:0] state, after_rx;
reg [9:0] count;
reg [7:0] h[0:63];
// Keep only FAT directory bytes that are actually consumed. This replaces the
// old 31-byte array with 19 bytes and reduces a congested directory mux.
reg [87:0] ent_name;
reg [7:0] ent_attr,ent_c20,ent_c21,ent_c26,ent_c27,ent_s28,ent_s29,ent_s30;
reg [15:0] signature;
reg [31:0] partition, part_candidate;
reg [7:0] part_type;
reg [31:0] fat_base, data_base, fat_size, total_sectors, max_cluster;
reg [7:0] spc;
reg [3:0] cluster_shift;
reg [31:0] cluster, next_cluster;
reg [7:0] cluster_sector;
reg [31:0] file_cluster[0:3];
// BMP candidates are admitted only for entry_size <= 3149824 (< 2^22).
// Audio file sizes, FAT clusters and disk addresses deliberately stay 32 bit.
reg [21:0] file_size[0:3];
reg [7:0] file_duration[0:3];
reg [1:0] file_scale[0:3];
reg [2:0] file_source_line[0:3];
reg [2:0] file_scene[0:3];
// Names are only needed during directory collection and playlist resolution.
// Low 72 bits occupy eight 9-bit words per candidate in one native 9K RAM.
// The high 16 bits stay in FFs so all eight exact comparisons finish before
// the next SPI byte (34 clocks versus the physical minimum of 36 clocks).
reg [15:0] candidate_name_head[0:7];
reg [2:0] candidate_scene[0:7];
reg name_write_busy;
reg [2:0] name_write_candidate,name_write_word;
reg [71:0] name_write_shift;
reg name_match_busy,name_match_issuing,name_match_finish,name_match_eof;
reg [2:0] name_request_candidate,name_response_candidate;
reg [1:0] name_request_phase,name_response_phase;
reg name_response_valid,name_candidate_equal;
reg [31:0] candidate_cluster[0:7];
reg [21:0] candidate_size[0:7];
reg [3:0] candidate_count;
reg playlist_found,text_found;
// SUB1 uses 64 16x16 glyphs; SUB2 packs 32 24x24 glyphs into the same
// 1024-word cache using its two native 9-bit lanes. No extra font BRAM.
reg pack_found,pack_initialized,pack_verified,pack_initial,pack_header_ok;
reg pack_format24;
reg [31:0] pack_cluster;
reg [1:0] pack_record,pack_target_index;
reg [2:0] pack_sector;
reg [4:0] pack_skip;
reg [5:0] pack_next_state;
reg [7:0] pack_low;
reg [7:0] pack_middle;
reg [1:0] pack_byte_phase;
reg [9:0] pack_font_address;
(* ASYNC_REG="TRUE" *) reg [1:0] font_idle_sync;
(* ASYNC_REG="TRUE" *) reg [1:0] font_quiet_sync;
always @(posedge clk or posedge rst)begin
 if(rst)begin font_idle_sync<=0;font_quiet_sync<=0;end
 else begin
  font_idle_sync<={font_idle_sync[0],font_cache_idle};
  font_quiet_sync<={font_quiet_sync[0],font_quiet_ack};
 end
end
reg [31:0] cover_cluster;
reg [21:0] cover_size;
reg cover_loading,cover_cancel_armed,cover_read_draining;
reg [4:0] audio_found;
reg [31:0] scene_audio_cluster[0:4],scene_audio_size[0:4];
reg audio_abort_pending;
reg [31:0] playlist_cluster,playlist_size,text_cluster,text_size;
reg [31:0] audio_cluster,audio_file_size;
reg [31:0] audio_file_pos,audio_data_offset,audio_data_remaining,wav_data_size;
reg [31:0] wav_tag;
reg [1:0] wav_size_phase,audio_byte_phase;
reg wav_tag_found,wav_size_capture;
reg [31:0] audio_word_build;
reg [2:0] playlist_count,emit_index;
reg [2:0] playlist_line,validate_index,valid_count;
reg [7:0] pl_name[0:10];
reg [3:0] pl_base_pos;
reg [1:0] pl_ext_pos;
reg pl_in_ext;
reg [1:0] pl_field,pl_mode;
reg [63:0] pl_mode_text;
reg [3:0] pl_mode_len;
reg [7:0] pl_duration;
reg [2:0] subtitle_line;
reg [7:0] subtitle_chars;
reg [31:0] text_bytes,text_limit;
reg text_kind;
reg [1:0] utf_need;
reg [7:0] utf_b0,utf_b1;
reg [21:0] selected_size,byte_count,pixel_end;
reg [12:0] pixel_offset; // valid_bmp accepts the inclusive range 54..4096.
reg [1:0] byte_phase;
reg [11:0] row_stride,row_data_bytes,row_byte_count; // width <=1024: stride <=3072.
reg [10:0] row_count; // Includes the terminal height count 1024.
reg dir_end;
reg [12:0] dir_budget;
reg [26:0] watchdog;
wire [7:0] din=sd_sec_read_data;
wire [7:0] ent0=ent_name[87:80],ent1=ent_name[79:72],ent2=ent_name[71:64],ent3=ent_name[63:56];
wire [7:0] ent4=ent_name[55:48],ent5=ent_name[47:40],ent6=ent_name[39:32],ent7=ent_name[31:24];
wire [7:0] ent8=ent_name[23:16],ent9=ent_name[15:8],ent10=ent_name[7:0];
wire [31:0] entry_cluster={ent_c21,ent_c20,ent_c27,ent_c26} & 32'h0fffffff;
wire [31:0] entry_size={din,ent_s30,ent_s29,ent_s28};
wire entry_regular=ent0!=0 && ent0!=8'he5 && (ent_attr&8'h1e)==0;
wire entry_bmp=entry_regular &&
              (ent8=="B" || ent8=="b") &&
              (ent9=="M" || ent9=="m") &&
              (ent10=="P" || ent10=="p");
wire entry_cover=entry_regular && ent_name=="COVER   BMP";
wire load_is_cover=load_sector==32'd4 && cover_found;
wire load_is_valid=load_is_cover || load_sector<scan_found_total;
wire [31:0] selected_image_cluster=load_is_cover?cover_cluster:file_cluster[load_sector[1:0]];
wire [21:0] selected_image_size=load_is_cover?cover_size:file_size[load_sector[1:0]];
wire entry_logo=((ent0=="L"||ent0=="l")&&(ent1=="O"||ent1=="o")&&
                 (ent2=="G"||ent2=="g")&&(ent3=="O"||ent3=="o")) ||
                entry_size==32'd404302;
wire entry_playlist=entry_regular && ent0=="P"&&ent1=="L"&&ent2=="A"&&ent3=="Y"&&
 ent4=="L"&&ent5=="I"&&ent6=="S"&&ent7=="T"&&ent8=="T"&&ent9=="X"&&ent10=="T";
wire entry_text=entry_regular &&
 ((ent0=="T"&&ent1=="E"&&ent2=="X"&&ent3=="T"&&ent4==" ")||
  (ent0=="H"&&ent1=="E"&&ent2=="L"&&ent3=="L"&&ent4=="O"))&&
 ent5==" "&&ent6==" "&&ent7==" "&&ent8=="T"&&ent9=="X"&&ent10=="T";
wire entry_pack=entry_regular && ent_name=="SUBS    BIN" &&
                (entry_size==32'd10240 || entry_size==32'd14336);
wire [2:0] pack_last_sector=pack_format24?3'd6:3'd4;
wire [1:0] requested_pack_record=font_scene_request[1:0]-2'd1;
wire [4:0] requested_pack_skip=pack_format24?
               ({requested_pack_record,3'b000}-{3'b000,requested_pack_record}):
               ({1'b0,requested_pack_record,2'b00}+{3'b000,requested_pack_record});
wire pack_rx=after_rx==PACK_READ || after_rx==PACK_SEEK || after_rx==FAT_PACK;
assign packed_subtitles=pack_found && pack_verified;
wire [2:0] pack_scene={1'b0,pack_record}+3'd1;
wire pack_match0=playlist_count>0 && file_scene[0]==pack_scene;
wire pack_match1=playlist_count>1 && file_scene[1]==pack_scene;
wire pack_match2=playlist_count>2 && file_scene[2]==pack_scene;
wire pack_match3=playlist_count>3 && file_scene[3]==pack_scene;
wire pack_map_valid=pack_match0 || pack_match1 || pack_match2 || pack_match3;
wire [1:0] pack_index=pack_initial ? (pack_match0?2'd0:pack_match1?2'd1:pack_match2?2'd2:2'd3):pack_target_index;
wire pack_wanted=pack_verified && font_scene_request>=1 && font_scene_request<=4 &&
                 (!font_ready || font_loaded_scene!=font_scene_request || font_loaded_index!=font_index_request);
wire entry_audio=entry_regular && (ent_name=="111     WAV" || ent_name=="GUQIN   WAV" ||
 ent_name=="ERHU    WAV" || ent_name=="DIZI    WAV" || ent_name=="TANGGU  WAV");
wire [2:0] entry_audio_scene=ent_name=="GUQIN   WAV"?3'd1:ent_name=="ERHU    WAV"?3'd2:
 ent_name=="DIZI    WAV"?3'd3:ent_name=="TANGGU  WAV"?3'd4:3'd0;
wire [2:0] selected_audio_scene=audio_scene<=4?audio_scene:3'd0;
wire selected_audio_found=audio_found[selected_audio_scene];
wire [31:0] selected_audio_cluster=scene_audio_cluster[selected_audio_scene];
wire [31:0] selected_audio_size=scene_audio_size[selected_audio_scene];
wire audio_rx=(after_rx==WAV_HDR || after_rx==AUDIO_DATA || after_rx==FAT_AUDIO);
wire [87:0] entry_name=ent_name;
wire [87:0] parsed_name={pl_name[0],pl_name[1],pl_name[2],pl_name[3],pl_name[4],pl_name[5],
 pl_name[6],pl_name[7],pl_name[8],pl_name[9],pl_name[10]};
reg playlist_match_valid;
reg [2:0] playlist_match_index;
wire [5:0] name_read_addr_a={name_request_candidate,name_request_phase,1'b0};
wire [5:0] name_read_addr_b={name_request_candidate,name_request_phase,1'b1};
wire [5:0] name_ram_addr_a=name_write_busy?{name_write_candidate,name_write_word}:name_read_addr_a;
wire [8:0] name_ram_q_a,name_ram_q_b;
candidate_name_ram name_store(
 .clk(clk),.we(name_write_busy),.addr_a(name_ram_addr_a),.addr_b(name_read_addr_b),
 .din(name_write_shift[8:0]),.q_a(name_ram_q_a),.q_b(name_ram_q_b)
);
wire subtitle_match0=playlist_count>0 && file_source_line[0]==subtitle_line;
wire subtitle_match1=playlist_count>1 && file_source_line[1]==subtitle_line;
wire subtitle_match2=playlist_count>2 && file_source_line[2]==subtitle_line;
wire subtitle_match3=playlist_count>3 && file_source_line[3]==subtitle_line;
wire subtitle_map_valid=subtitle_match0||subtitle_match1||subtitle_match2||subtitle_match3;
wire [1:0] subtitle_target=subtitle_match0?0:subtitle_match1?1:subtitle_match2?2:3;
function [3:0] log_spc;
 input [7:0] n;
 begin case(n)
 1:log_spc=0;2:log_spc=1;4:log_spc=2;8:log_spc=3;
 16:log_spc=4;32:log_spc=5;64:log_spc=6;128:log_spc=7;
 default:log_spc=15;endcase end
endfunction
wire valid_bpb=signature==16'haa55 && {h[12],h[11]}==512 &&
 log_spc(h[13])!=15 && {h[15],h[14]}!=0 && (h[16]==1 || h[16]==2) &&
 {h[18],h[17]}==0 && {h[20],h[19]}==0 && {h[23],h[22]}==0 && {h[39],h[38],h[37],h[36]}!=0 &&
 {h[43],h[42]}==0 && {h[47],h[46],h[45],h[44]}>=2;
wire [31:0] header_width={h[21],h[20],h[19],h[18]};
wire [31:0] header_height={h[25],h[24],h[23],h[22]};
wire [31:0] header_row_bytes=header_width*3;
wire [31:0] header_stride=(header_row_bytes+3)&32'hfffffffc;
wire valid_bmp=h[0]=="B" && h[1]=="M" && {h[17],h[16],h[15],h[14]}==40 &&
 header_width>=1 && header_width<=1024 && header_height>=1 && header_height<=1024 &&
 {h[27],h[26]}==1 && {h[29],h[28]}==24 && {h[33],h[32],h[31],h[30]}==0 &&
 {h[13],h[12],h[11],h[10]}>=54 && {h[13],h[12],h[11],h[10]}<=4096 &&
 selected_size>{h[13],h[12],h[11],h[10]};
wire valid_cluster=next_cluster>=2 && next_cluster<max_cluster && next_cluster<32'h0ffffff0;
wire transaction_timeout=cover_loading ? watchdog>=COVER_TIMEOUT_CYCLES-1'b1 : &watchdog;
// A timed-out SD command may still finish later. Do not interpret its late
// bytes as a new image/audio header. The cached frames remain usable while
// waiting for the transport; an absent/unresponsive card cannot supply audio.
assign ready=(state==IDLE || state==AUDIO_READY) && !cover_read_draining;
wire valid_wav_header=h[0]=="R"&&h[1]=="I"&&h[2]=="F"&&h[3]=="F"&&
 h[8]=="W"&&h[9]=="A"&&h[10]=="V"&&h[11]=="E"&&
 h[12]=="f"&&h[13]=="m"&&h[14]=="t"&&h[15]==" "&&
 {h[21],h[20]}==16'd1 && {h[23],h[22]}==16'd2 &&
 {h[27],h[26],h[25],h[24]}==32'd48000 &&
 {h[33],h[32]}==16'd4 && {h[35],h[34]}==16'd16;
function [7:0] upper_ascii;
 input [7:0] c;
 begin upper_ascii=(c>="a"&&c<="z")?c-8'd32:c;end
endfunction
// A scene follows its image basename, not its playlist position. Ordinary
// images therefore keep the original 111.WAV playback behaviour.
function [2:0] scene_from_name;
 input [87:0] name;
 begin
  case(name)
   "GUQIN   BMP":scene_from_name=1;
   "ERHU    BMP":scene_from_name=2;
   "DIZI    BMP":scene_from_name=3;
   "TANGGU  BMP":scene_from_name=4;
   default:scene_from_name=0;
  endcase
 end
endfunction
function [7:0] subtitle_glyph;
 input [7:0] b0,b1,b2;
 begin
  // Keep this order identical to tools/make_subtitle_font.ps1. Only the
  // fixed 32-glyph subset is decoded; unknown UTF8 remains one '?' slot.
  case({b0,b1,b2})
   24'he4bda0:subtitle_glyph=8'h80; // 你
   24'he5a5bd:subtitle_glyph=8'h81; // 好
   24'he59180:subtitle_glyph=8'h82; // 呀
   24'he5afb9:subtitle_glyph=8'h83; // 对
   24'he4b88d:subtitle_glyph=8'h84; // 不
   24'he8b5b7:subtitle_glyph=8'h85; // 起
   24'hefbc81:subtitle_glyph=8'h86; // ！
   24'he58fa4:subtitle_glyph=8'h87; // 古
   24'he790b4:subtitle_glyph=8'h88; // 琴
   24'he4b883:subtitle_glyph=8'h89; // 七
   24'he5bca6:subtitle_glyph=8'h8a; // 弦
   24'he6b885:subtitle_glyph=8'h8b; // 清
   24'he99fb3:subtitle_glyph=8'h8c; // 音
   24'he889b2:subtitle_glyph=8'h8d; // 色
   24'he99b85:subtitle_glyph=8'h8e; // 雅
   24'he4ba8c:subtitle_glyph=8'h8f; // 二
   24'he883a1:subtitle_glyph=8'h90; // 胡
   24'he4b8a4:subtitle_glyph=8'h91; // 两
   24'he4b880:subtitle_glyph=8'h92; // 一
   24'he5bc93:subtitle_glyph=8'h93; // 弓
   24'he7ac9b:subtitle_glyph=8'h94; // 笛
   24'he5ad90:subtitle_glyph=8'h95; // 子
   24'he7abb9:subtitle_glyph=8'h96; // 竹
   24'he7aea1:subtitle_glyph=8'h97; // 管
   24'he4baae:subtitle_glyph=8'h98; // 亮
   24'he5a082:subtitle_glyph=8'h99; // 堂
   24'he9bc93:subtitle_glyph=8'h9a; // 鼓
   24'he58f8c:subtitle_glyph=8'h9b; // 双
   24'he6a78c:subtitle_glyph=8'h9c; // 槌
   24'he587bb:subtitle_glyph=8'h9d; // 击
   24'he6b591:subtitle_glyph=8'h9e; // 浑
   24'he58e9a:subtitle_glyph=8'h9f; // 厚
   default:subtitle_glyph="?";
  endcase
 end
endfunction
task clear_playlist_line;
 integer k;
 begin
  for(k=0;k<11;k=k+1)pl_name[k]<=8'h20;
  pl_base_pos<=0;pl_ext_pos<=0;pl_in_ext<=0;pl_field<=0;pl_mode<=0;pl_duration<=0;
  pl_mode_text<=0;pl_mode_len<=0;
 end
endtask
task commit_playlist_line;
 begin
  if(playlist_count<4 && pl_base_pos!=0 && playlist_match_valid)begin
   file_cluster[playlist_count]<=candidate_cluster[playlist_match_index];
   file_size[playlist_count]<=candidate_size[playlist_match_index];
   file_duration[playlist_count]<=pl_duration==0?5:pl_duration;
   file_scale[playlist_count]<=pl_mode_text=="ORIGINAL"?1:pl_mode_text=="FILL"?3:2;
   file_source_line[playlist_count]<=playlist_line;
   // A successful match proves parsed_name == the selected candidate name.
   file_scene[playlist_count]<=scene_from_name(parsed_name);
   playlist_count<=playlist_count+1'b1;
  end
 end
endtask
task start_playlist_match;
 input at_eof;
 begin
  name_match_busy<=1;name_match_issuing<=1;name_match_finish<=0;name_match_eof<=at_eof;
  name_request_candidate<=0;name_request_phase<=0;name_response_valid<=0;
  name_candidate_equal<=1;playlist_match_valid<=0;playlist_match_index<=0;
 end
endtask
task read_sector;
 input [31:0] lba; input [5:0] continuation;
 begin sd_sec_read_addr<=lba;after_rx<=continuation;state<=START;end
endtask
task start_pack_font;
 begin
  font_ready<=0;pack_initial<=0;pack_header_ok<=0;
  font_quiet_request<=~font_quiet_request;
  pack_record<=font_scene_request[1:0]-2'd1;pack_target_index<=font_index_request;
  pack_sector<=0;pack_skip<=requested_pack_skip;
  pack_byte_phase<=0;pack_font_address<=0;
  cluster<=pack_cluster;cluster_sector<=0;
  // Font transactions replace, rather than interleave with, a WAV sector.
  // The controller already holds audio reset throughout an image commit.
  audio_reset_busy<=1;audio_abort_pending<=1;
  // ready_d is frame-latched in video. Do not overwrite a glyph until that
  // domain acknowledges the old page is no longer being displayed.
  state<=PACK_WAIT;
 end
endtask
task fail_pack;
 begin
  font_ready<=0;pack_verified<=0;pack_initialized<=1;
  // Corrupt optional subtitles must not turn valid pictures into FAIL/white.
  subtitle_len0<=0;subtitle_len1<=0;subtitle_len2<=0;subtitle_len3<=0;
  state<=pack_initial?AFTER_SUB:IDLE;
 end
endtask
// All FAT data-sector requests are mutually exclusive states. Select the
// cluster before the 32-bit subtract/barrel shift/add, rather than duplicating
// that arithmetic for image, WAV, playlist, text and font-pack sources.
// This is combinational sharing only: request cycles and ACK latency do not change.
reg [31:0] request_cluster;
always @* begin
 request_cluster=cluster;
 case(state)
  IDLE:request_cluster=load_start?selected_image_cluster:selected_audio_cluster;
  AUDIO_READY:request_cluster=load_start?selected_image_cluster:cluster;
  FAT_DIR,FAT_PIX,FAT_TEXT,FAT_AUDIO,FAT_PACK:request_cluster=next_cluster;
  PREP_FILES:request_cluster=playlist_cluster;
  VALIDATE_START:request_cluster=file_cluster[validate_index];
  AFTER_VALIDATE:request_cluster=text_cluster;
  AFTER_SUB,PACK_WAIT:request_cluster=pack_cluster;
  WAV_HDR,AUDIO_DATA:request_cluster=audio_cluster;
  default:;
 endcase
end
wire [31:0] cluster_lba=data_base+((request_cluster-32'd2)<<cluster_shift);
wire [31:0] next_sector_lba=cluster_lba+{24'd0,cluster_sector}+32'd1;

integer i;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  state<=IDLE;after_rx<=IDLE;sd_sec_read<=0;sd_sec_read_addr<=0;
  count<=0;scan_done<=0;scan_found_valid<=0;scan_found_sector<=0;scan_found_total<=0;
  scan_found_duration<=5;scan_found_scale<=2;scan_found_scene<=0;
  subtitle_wr_en<=0;subtitle_wr_addr<=0;subtitle_wr_data<=0;
  subtitle_len0<=0;subtitle_len1<=0;subtitle_len2<=0;subtitle_len3<=0;
  pack_found<=0;pack_initialized<=0;pack_verified<=0;pack_initial<=0;pack_header_ok<=0;
  pack_format24<=0;pack_middle<=0;pack_byte_phase<=0;pack_font_address<=0;
  pack_cluster<=0;pack_record<=0;pack_target_index<=0;pack_sector<=0;pack_skip<=0;pack_next_state<=PACK_READ;pack_low<=0;
  font_wr_en<=0;font_wr_addr<=0;font_wr_data<=0;font_ready<=1;font_format24<=0;font_loaded_scene<=0;font_loaded_index<=0;
  font_quiet_request<=0;
  state_code<=0;write_req<=0;bmp_data_wr_en<=0;bmp_data<=0;
  source_width<=0;source_height<=0;image_start<=0;
  partition<=0;part_candidate<=0;part_type<=0;signature<=0;
  fat_base<=0;data_base<=0;fat_size<=0;total_sectors<=0;max_cluster<=0;
  cluster<=0;next_cluster<=0;cluster_sector<=0;spc<=0;cluster_shift<=0;
  selected_size<=0;byte_count<=0;pixel_offset<=0;pixel_end<=0;byte_phase<=0;
  row_stride<=0;row_data_bytes<=0;row_byte_count<=0;row_count<=0;
  dir_end<=0;dir_budget<=0;watchdog<=0;
  for(i=0;i<64;i=i+1) h[i]<=0;
  ent_name<=0;ent_attr<=0;ent_c20<=0;ent_c21<=0;ent_c26<=0;ent_c27<=0;
  ent_s28<=0;ent_s29<=0;ent_s30<=0;
  candidate_count<=0;playlist_found<=0;text_found<=0;playlist_cluster<=0;playlist_size<=0;
  cover_found<=0;cover_error<=0;cover_cluster<=0;cover_size<=0;
  cover_loading<=0;cover_cancel_armed<=0;cover_read_draining<=0;
  text_cluster<=0;text_size<=0;playlist_count<=0;emit_index<=0;
  audio_found<=0;audio_cluster<=0;audio_file_size<=0;audio_file_present<=0;
  audio_reset_busy<=1;audio_abort_pending<=1;audio_sample_total<=0;
  audio_format_error<=0;audio_pcm_wr<=0;audio_pcm_word<=0;
  audio_file_pos<=0;audio_data_offset<=0;audio_data_remaining<=0;wav_data_size<=0;
  wav_tag<=0;wav_size_phase<=0;audio_byte_phase<=0;wav_tag_found<=0;wav_size_capture<=0;
  audio_word_build<=0;
  playlist_line<=0;validate_index<=0;valid_count<=0;
  pl_base_pos<=0;pl_ext_pos<=0;pl_in_ext<=0;pl_field<=0;pl_mode<=0;pl_duration<=0;
  subtitle_line<=0;subtitle_chars<=0;utf_need<=0;utf_b0<=0;utf_b1<=0;
  text_bytes<=0;text_limit<=0;text_kind<=0;
  pl_mode_text<=0;pl_mode_len<=0;
  for(i=0;i<11;i=i+1)pl_name[i]<=8'h20;
  for(i=0;i<4;i=i+1) begin file_cluster[i]<=0;file_size[i]<=0;file_duration[i]<=5;file_scale[i]<=2;file_source_line[i]<=i;file_scene[i]<=0;end
  for(i=0;i<5;i=i+1)begin scene_audio_cluster[i]<=0;scene_audio_size[i]<=0;end
  for(i=0;i<8;i=i+1)begin candidate_name_head[i]<=0;candidate_scene[i]<=0;candidate_cluster[i]<=0;candidate_size[i]<=0;end
  name_write_busy<=0;name_write_candidate<=0;name_write_word<=0;name_write_shift<=0;
  name_match_busy<=0;name_match_issuing<=0;name_match_finish<=0;name_match_eof<=0;
  name_request_candidate<=0;name_request_phase<=0;name_response_candidate<=0;name_response_phase<=0;
  name_response_valid<=0;name_candidate_equal<=0;playlist_match_valid<=0;playlist_match_index<=0;
 end else begin
  scan_found_valid<=0;bmp_data_wr_en<=0;image_start<=0;subtitle_wr_en<=0;audio_pcm_wr<=0;font_wr_en<=0;
  if(cover_read_draining && sd_sec_read_end)cover_read_draining<=0;
  // Fastest SPI data-valid spacing is 36 clocks. A name takes 8 directory
  // write clocks, and all 8 candidates resolve in 34 clocks. RAM is not reset.
  if(name_write_busy)begin
   if(name_write_word==7)name_write_busy<=0;
   else begin name_write_word<=name_write_word+1'b1;name_write_shift<={9'b0,name_write_shift[71:9]};end
  end
  name_response_valid<=name_match_issuing;
  if(name_match_issuing)begin
   name_response_candidate<=name_request_candidate;name_response_phase<=name_request_phase;
   if(name_request_phase==3)begin
    name_request_phase<=0;
    if(name_request_candidate==7)name_match_issuing<=0;
    else name_request_candidate<=name_request_candidate+1'b1;
   end else name_request_phase<=name_request_phase+1'b1;
  end
  if(name_response_valid)begin
   case(name_response_phase)
    0:name_candidate_equal<=name_ram_q_a==parsed_name[8:0] && name_ram_q_b==parsed_name[17:9];
    1:name_candidate_equal<=name_candidate_equal && name_ram_q_a==parsed_name[26:18] && name_ram_q_b==parsed_name[35:27];
    2:name_candidate_equal<=name_candidate_equal && name_ram_q_a==parsed_name[44:36] && name_ram_q_b==parsed_name[53:45];
    default:begin
     // Ascending traversal deliberately retains highest-index duplicate wins.
     if(name_response_candidate<candidate_count && name_candidate_equal &&
        name_ram_q_a==parsed_name[62:54] && name_ram_q_b==parsed_name[71:63] &&
        candidate_name_head[name_response_candidate]==parsed_name[87:72])begin
      playlist_match_valid<=1;playlist_match_index<=name_response_candidate;
     end
     if(name_response_candidate==7)name_match_finish<=1;
    end
   endcase
  end
  if(name_match_finish)begin
   commit_playlist_line;
   if(!name_match_eof && pl_base_pos!=0 && playlist_line<4)playlist_line<=playlist_line+1'b1;
   clear_playlist_line;
   name_match_busy<=0;name_match_finish<=0;
   if(name_match_eof)state<=AFTER_PLAY;
  end
  // Cancellation never aborts the SD SPI transaction halfway. Suppress its
  // PCM bytes immediately, drain the old sector, then release the FIFO reset.
  if(audio_restart)begin
   audio_reset_busy<=1;audio_abort_pending<=1;audio_sample_total<=0;
  end
  if(audio_abort_pending && state==IDLE && !audio_restart)begin
   audio_abort_pending<=0;audio_reset_busy<=0;
  end
  case(state)
  IDLE: begin
   state_code<=scan_done ? 4'd6:4'd1;
   cover_loading<=0;
   if(cover_read_draining)begin
    // Only a reset or the outstanding transaction's end releases this wait.
    sd_sec_read<=0;
   end else if(sd_init_done && scan_start) begin
    scan_done<=0;scan_found_total<=0;partition<=0;part_candidate<=0;
    dir_end<=0;dir_budget<=0;candidate_count<=0;playlist_found<=0;text_found<=0;
    pack_found<=0;pack_initialized<=0;pack_verified<=0;pack_format24<=0;
    font_ready<=1;font_format24<=0;font_loaded_scene<=0;
    cover_found<=0;cover_error<=0;cover_cluster<=0;cover_size<=0;
    cover_cancel_armed<=0;
    name_write_busy<=0;name_match_busy<=0;name_match_issuing<=0;name_match_finish<=0;name_response_valid<=0;
    playlist_count<=0;playlist_line<=0;emit_index<=0;subtitle_line<=0;subtitle_chars<=0;utf_need<=0;
    audio_found<=0;audio_file_present<=0;audio_format_error<=0;
    subtitle_len0<=0;subtitle_len1<=0;subtitle_len2<=0;subtitle_len3<=0;
    clear_playlist_line;read_sector(0,BOOT);
   end else if(sd_init_done && load_start) begin
    cover_loading<=load_sector==32'd4;
    cover_cancel_armed<=load_sector==32'd4;
    if(load_is_valid) begin
     cluster<=selected_image_cluster;
     selected_size<=selected_image_size;
     cluster_sector<=0;byte_count<=0;byte_phase<=0;
     read_sector(cluster_lba,HDR);
    end else state<=FAIL;
   end else if(sd_init_done && scan_done && pack_wanted)begin
    start_pack_font;
   end else if(sd_init_done && scan_done && audio_stream_enable && selected_audio_found &&
               !audio_fifo_afull && !audio_restart && !audio_abort_pending)begin
    cover_cancel_armed<=0;
    audio_cluster<=selected_audio_cluster;audio_file_size<=selected_audio_size;
    cluster<=selected_audio_cluster;cluster_sector<=0;wav_tag<=0;wav_tag_found<=0;wav_size_capture<=0;
    wav_size_phase<=0;wav_data_size<=0;audio_format_error<=0;
    audio_file_present<=1;
    read_sector(cluster_lba,WAV_HDR);
   end else if(scan_done && !selected_audio_found)begin
    audio_file_present<=0;audio_format_error<=0;
   end
  end
  START: begin count<=0;watchdog<=0;sd_sec_read<=1;state<=RX;end
  RX: begin
   watchdog<=watchdog+1'b1;
   if(transaction_timeout) begin
    sd_sec_read<=0;
    if(pack_rx)fail_pack;else state<=FAIL;
    if((cover_loading || pack_rx) && !sd_sec_read_end)cover_read_draining<=1;
   end
   if(sd_sec_read_data_valid) begin
    count<=count+1'b1;
    if(count<64) h[count[5:0]]<=din;
    if(count==510)signature[7:0]<=din;
    if(count==511)signature[15:8]<=din;
    // Four primary MBR entries. Pick the first FAT32 partition.
    if(after_rx==BOOT && partition==0 && count>=446 && count<510) begin
     case((count-446)&15)
      4:part_type<=din;
      8:part_candidate[7:0]<=din;
      9:part_candidate[15:8]<=din;
      10:part_candidate[23:16]<=din;
      11:begin
       part_candidate[31:24]<=din;
       if(part_type==8'h0b || part_type==8'h0c)
        partition<={din,part_candidate[23:0]};
      end
     endcase
    end
    if(after_rx==DIR) begin
     case(count[4:0])
      0:ent_name[87:80]<=din;1:ent_name[79:72]<=din;2:ent_name[71:64]<=din;
      3:ent_name[63:56]<=din;4:ent_name[55:48]<=din;5:ent_name[47:40]<=din;
      6:ent_name[39:32]<=din;7:ent_name[31:24]<=din;8:ent_name[23:16]<=din;
      9:ent_name[15:8]<=din;10:ent_name[7:0]<=din;11:ent_attr<=din;
      20:ent_c20<=din;21:ent_c21<=din;26:ent_c26<=din;27:ent_c27<=din;
      28:ent_s28<=din;29:ent_s29<=din;30:ent_s30<=din;default:;
     endcase
     if(count[4:0]==31 && !dir_end) begin
      if(ent0==0) dir_end<=1;
      else if(entry_pack && entry_cluster>=2 && entry_cluster<max_cluster)begin
       pack_found<=1;pack_cluster<=entry_cluster;pack_format24<=entry_size==32'd14336;
      end else if(entry_playlist && entry_cluster>=2 && entry_cluster<max_cluster && entry_size<=4096)begin
       playlist_found<=1;playlist_cluster<=entry_cluster;playlist_size<=entry_size;
      end else if(entry_text && entry_cluster>=2 && entry_cluster<max_cluster && entry_size<=4096)begin
       // TEXT.TXT has priority over HELLO.TXT if both are present.
       if(!text_found || ent0=="T")begin text_found<=1;text_cluster<=entry_cluster;text_size<=entry_size;end
      end else if(entry_audio && entry_cluster>=2 && entry_cluster<max_cluster && entry_size>44)begin
       audio_found[entry_audio_scene]<=1;
       scene_audio_cluster[entry_audio_scene]<=entry_cluster;scene_audio_size[entry_audio_scene]<=entry_size;
      end else if(entry_cover && entry_cluster>=2 && entry_cluster<max_cluster &&
                  entry_size>=58 && entry_size<=3149824)begin
       cover_found<=1;cover_cluster<=entry_cluster;cover_size<=entry_size[21:0];
      end else if(entry_bmp && !entry_cover && !entry_logo && entry_cluster>=2 && entry_cluster<max_cluster &&
              entry_size>=58 && entry_size<=3149824 && candidate_count<8) begin
       name_write_busy<=1;name_write_candidate<=candidate_count[2:0];name_write_word<=0;
       name_write_shift<=entry_name[71:0];candidate_name_head[candidate_count]<=entry_name[87:72];
       candidate_scene[candidate_count]<=scene_from_name(entry_name);
       candidate_cluster[candidate_count]<=entry_cluster;
       candidate_size[candidate_count]<=entry_size[21:0];
       candidate_count<=candidate_count+1'b1;
      end
     end
    end
    if(after_rx==WAV_HDR && !audio_restart && !audio_abort_pending)begin
      wav_tag<={wav_tag[23:0],din};
      if(!wav_tag_found && {wav_tag[23:0],din}==32'h64617461)begin
        wav_tag_found<=1;wav_size_capture<=1;wav_size_phase<=0;
        audio_data_offset<=count+10'd5;wav_data_size<=0;
      end else if(wav_size_capture)begin
        case(wav_size_phase)
          0:begin wav_data_size[7:0]<=din;wav_size_phase<=1;end
          1:begin wav_data_size[15:8]<=din;wav_size_phase<=2;end
          2:begin wav_data_size[23:16]<=din;wav_size_phase<=3;end
          default:begin wav_data_size[31:24]<=din;wav_size_capture<=0;end
        endcase
      end
    end
    if(after_rx==AUDIO_DATA && !audio_restart && !audio_abort_pending)begin
      audio_file_pos<=audio_file_pos+1'b1;
      if(audio_file_pos>=audio_data_offset && audio_data_remaining!=0)begin
        audio_data_remaining<=audio_data_remaining-1'b1;
        case(audio_byte_phase)
          0:begin audio_word_build[7:0]<=din;audio_byte_phase<=1;end
          1:begin audio_word_build[15:8]<=din;audio_byte_phase<=2;end
          2:begin audio_word_build[23:16]<=din;audio_byte_phase<=3;end
          default:begin
            audio_pcm_word<={din,audio_word_build[23:0]};audio_pcm_wr<=1;audio_byte_phase<=0;
          end
        endcase
      end
    end
    if((after_rx==PLAY_TEXT || after_rx==SUB_TEXT) && text_bytes<text_limit)text_bytes<=text_bytes+1'b1;
    if(after_rx==PLAY_TEXT && text_bytes<text_limit)begin
      if(din==8'h0a)begin
        start_playlist_match(1'b0);
      end else if(din!=8'h0d)begin
        case(pl_field)
          0:begin
            if(din==",")pl_field<=1;
            else if(din==".")pl_in_ext<=1;
            else if(!pl_in_ext && pl_base_pos<8)begin pl_name[pl_base_pos]<=upper_ascii(din);pl_base_pos<=pl_base_pos+1'b1;end
            else if(pl_in_ext && pl_ext_pos<3)begin pl_name[8+pl_ext_pos]<=upper_ascii(din);pl_ext_pos<=pl_ext_pos+1'b1;end
          end
          1:begin
            if(din==",")pl_field<=2;
            else if(din>="0"&&din<="9")begin
              if(pl_duration>25 || (pl_duration==25 && din>"5"))pl_duration<=255;
              else pl_duration<=pl_duration*10+(din-"0");
            end
          end
          default:begin
            if(pl_mode_len<8)begin
              pl_mode_text<={pl_mode_text[55:0],upper_ascii(din)};
              pl_mode_len<=pl_mode_len+1'b1;
            end
          end
        endcase
      end
    end
    if(after_rx==SUB_TEXT && text_bytes<text_limit && subtitle_line<4)begin
      if(din==8'h0a)begin
        if(subtitle_map_valid)case(subtitle_target)0:subtitle_len0<=subtitle_chars;1:subtitle_len1<=subtitle_chars;
          2:subtitle_len2<=subtitle_chars;default:subtitle_len3<=subtitle_chars;endcase
        subtitle_line<=subtitle_line+1'b1;
        subtitle_chars<=0;utf_need<=0;
      end else if(din!=8'h0d && subtitle_line<4 && subtitle_chars<128)begin
        if(utf_need==0)begin
          if(din<8'h80)begin
            subtitle_wr_en<=subtitle_map_valid;subtitle_wr_addr<={subtitle_target,subtitle_chars[6:0]};
            subtitle_wr_data<=din;subtitle_chars<=subtitle_chars+1'b1;
          end else if(din>=8'hc2 && din<=8'hf4)begin
            utf_b0<=din;utf_b1<=0;
            if(din<8'he0)utf_need<=1;
            else if(din<8'hf0)utf_need<=2;
            else utf_need<=3;
          end else begin
            subtitle_wr_en<=subtitle_map_valid;subtitle_wr_addr<={subtitle_target,subtitle_chars[6:0]};
            subtitle_wr_data<="?";subtitle_chars<=subtitle_chars+1'b1;
          end
        end else if(utf_need>1)begin utf_b1<=din;utf_need<=utf_need-1'b1;end
        else begin
          // UTF8 BOM is not a displayed character. Unsupported codepoints
          // consume one character slot, including two/four-byte sequences.
          if(!(text_bytes==2 && utf_b0==8'hef && utf_b1==8'hbb && din==8'hbf))begin
            subtitle_wr_en<=subtitle_map_valid;subtitle_wr_addr<={subtitle_target,subtitle_chars[6:0]};
            subtitle_wr_data<=subtitle_glyph(utf_b0,utf_b1,din);
            subtitle_chars<=subtitle_chars+1'b1;
          end
          utf_need<=0;
        end
      end
    end
    if(after_rx==PACK_READ)begin
     if(pack_sector==0)begin
      if(count==15)pack_header_ok<=h[0]=="S" && h[1]=="U" && h[2]=="B" &&
                h[3]==(pack_format24?"2":"1") && h[4]=={5'd0,pack_scene} &&
                h[5]>=1 && h[5]<=128 && h[6]<=(pack_format24?8'd32:8'd64);
      if(pack_header_ok && count>=16 && count<144 && count-16<h[5] && pack_map_valid)begin
       // SUB2 reserves C0/C1 for full-width punctuation. Other high codes
       // must address one of the declared native glyph slots without alias.
       if(pack_format24 && din[7] && din!=8'hc0 && din!=8'hc1 &&
          (din[7:5]!=3'b111 || {3'b000,din[4:0]}>=h[6]))pack_header_ok<=0;
       else begin
        subtitle_wr_en<=1;subtitle_wr_addr<={pack_index,(count[6:0]-7'd16)};subtitle_wr_data<=din;
       end
      end
     end else if(pack_header_ok)begin
      if(pack_format24)begin
       // 512 is not divisible by three: retain phase across data sectors,
       // cluster/FAT traversal and their intervening transactions.
       case(pack_byte_phase)
        0:begin pack_low<=din;pack_byte_phase<=1;end
        1:begin pack_middle<=din;pack_byte_phase<=2;end
        default:begin
         pack_byte_phase<=0;pack_font_address<=pack_font_address+1'b1;
         if(din[7:2]!=0)pack_header_ok<=0;
         else if(!pack_initial || pack_record==0)begin
          font_wr_en<=1;font_wr_addr<=pack_font_address;
          font_wr_data<={din[1:0],pack_middle,pack_low};
         end
        end
       endcase
      end else if(!pack_initial || pack_record==0)begin
       if(!count[0])pack_low<=din;
       else begin font_wr_en<=1;font_wr_addr<={(pack_sector[1:0]-2'd1),count[8:1]};font_wr_data<={2'b00,din,pack_low};end
      end
     end
    end
    if(after_rx==FAT_DIR || after_rx==FAT_PIX || after_rx==FAT_TEXT || after_rx==FAT_AUDIO || after_rx==FAT_PACK) begin
     if(count[8:2]==cluster[6:0]) begin
      case(count[1:0])
       0:next_cluster[7:0]<=din;1:next_cluster[15:8]<=din;
       2:next_cluster[23:16]<=din;3:next_cluster[31:24]<={4'b0,din[3:0]};
      endcase
     end
    end
    if(after_rx==PIX) begin
     byte_count<=byte_count+1'b1;
     if(byte_count>=pixel_offset && byte_count<pixel_end) begin
      if(row_byte_count<row_data_bytes)begin
       case(byte_phase)
        0:begin bmp_data[7:0]<=din;byte_phase<=1;end
        1:begin bmp_data[15:8]<=din;byte_phase<=2;end
        2:begin bmp_data[23:16]<=din;byte_phase<=0;bmp_data_wr_en<=1;end
       endcase
      end
      if(row_byte_count==row_stride-1)begin
       row_byte_count<=0;byte_phase<=0;row_count<=row_count+1'b1;
       // Stop after the height declared by the BMP header, ignoring trailers.
       if(row_count+1>=source_height)pixel_end<=byte_count+1'b1;
      end
      else row_byte_count<=row_byte_count+1'b1;
     end
    end
   end
   if(sd_sec_read_end) begin
    sd_sec_read<=0;
    if(audio_rx && (audio_restart || audio_abort_pending))state<=IDLE;
    else if(count!=512)begin if(pack_rx)fail_pack;else state<=FAIL;end
    else state<=after_rx;
   end
  end
  BOOT: begin
   state_code<=2;
   if(valid_bpb) begin partition<=0;state<=GEOM;end
   else if(signature==16'haa55 && partition!=0) read_sector(partition,GEOM);
   else state<=FAIL;
  end
  GEOM: begin
   if(!valid_bpb) state<=FAIL;
   else begin
    spc<=h[13];cluster_shift<=log_spc(h[13]);fat_size<={h[39],h[38],h[37],h[36]};
    total_sectors<={h[35],h[34],h[33],h[32]};
    fat_base<=partition+{16'b0,{h[15],h[14]}};
    // Honor the selected FAT when FAT mirroring is disabled.
    if(h[40][7] && h[40][3:0]==1 && h[16]==2)
     fat_base<=partition+{16'b0,{h[15],h[14]}}+{h[39],h[38],h[37],h[36]};
    data_base<=partition+{16'b0,{h[15],h[14]}}+(h[16]==2 ? ({h[39],h[38],h[37],h[36]}<<1):{h[39],h[38],h[37],h[36]});
    cluster<={h[47],h[46],h[45],h[44]};cluster_sector<=0;state<=ROOT;
   end
  end
  ROOT: begin
   max_cluster<=((total_sectors-(data_base-partition))>>cluster_shift)+2;
   if(total_sectors<=(data_base-partition) || fat_size==0)state<=FAIL;
   else read_sector(cluster_lba,DIR);
  end
  DIR: begin
   dir_budget<=dir_budget+1'b1;
   if(dir_end)state<=PREP_FILES;
   else if(dir_budget==4095)state<=FAIL;
   else state<=NEXT_DIR;
  end
  NEXT_DIR: begin
   if(cluster_sector+1<spc) begin
    cluster_sector<=cluster_sector+1'b1;
    read_sector(next_sector_lba,DIR);
   end else read_sector(fat_base+(cluster>>7),FAT_DIR);
  end
  FAT_DIR: begin
   if(next_cluster>=32'h0ffffff8) begin
    state<=PREP_FILES;
   end else if(!valid_cluster) state<=FAIL;
   else begin
    cluster<=next_cluster;cluster_sector<=0;
    read_sector(cluster_lba,DIR);
   end
  end
  PREP_FILES: begin
   playlist_count<=0;playlist_line<=0;emit_index<=0;clear_playlist_line;
   if(playlist_found)begin
    cluster<=playlist_cluster;cluster_sector<=0;text_bytes<=0;text_limit<=playlist_size;text_kind<=0;
    read_sector(cluster_lba,PLAY_TEXT);
   end
   else begin
    for(i=0;i<4;i=i+1)begin
      if(i<candidate_count && i<scan_target_count)begin
        file_cluster[i]<=candidate_cluster[i];file_size[i]<=candidate_size[i];
        file_duration[i]<=5;file_scale[i]<=2;
        file_source_line[i]<=i;
        file_scene[i]<=candidate_scene[i];
      end
    end
    if(candidate_count>scan_target_count)playlist_count<=scan_target_count;
    else if(candidate_count>4)playlist_count<=4;
    else playlist_count<=candidate_count[2:0];
    state<=AFTER_PLAY;
   end
  end
  PLAY_TEXT: begin
   if(text_bytes>=text_limit)begin
    if(!name_match_busy)start_playlist_match(1'b1);
   end
   else state<=NEXT_TEXT;
  end
  AFTER_PLAY: begin
   validate_index<=0;valid_count<=0;state<=VALIDATE_START;
  end
  VALIDATE_START:begin
   if(validate_index<playlist_count)begin
    cluster<=file_cluster[validate_index];selected_size<=file_size[validate_index];
    read_sector(cluster_lba,VALIDATE_HDR);
   end else begin playlist_count<=valid_count;state<=AFTER_VALIDATE;end
  end
  VALIDATE_HDR:begin
   if(valid_bmp)begin
    file_cluster[valid_count]<=file_cluster[validate_index];file_size[valid_count]<=file_size[validate_index];
    file_duration[valid_count]<=file_duration[validate_index];file_scale[valid_count]<=file_scale[validate_index];
    file_source_line[valid_count]<=file_source_line[validate_index];valid_count<=valid_count+1'b1;
    file_scene[valid_count]<=file_scene[validate_index];
   end
   validate_index<=validate_index+1'b1;state<=VALIDATE_START;
  end
  AFTER_VALIDATE: begin
   subtitle_line<=0;subtitle_chars<=0;utf_need<=0;
   if(text_found)begin
    cluster<=text_cluster;cluster_sector<=0;text_bytes<=0;text_limit<=text_size;text_kind<=1;
    read_sector(cluster_lba,SUB_TEXT);
   end
   else state<=AFTER_SUB;
  end
  SUB_TEXT: begin
   if(text_bytes>=text_limit || subtitle_line>=4)state<=END_TEXT;
   else state<=NEXT_TEXT;
  end
  NEXT_TEXT: begin
   if(cluster_sector+1<spc)begin
    cluster_sector<=cluster_sector+1'b1;
    read_sector(next_sector_lba,text_kind?SUB_TEXT:PLAY_TEXT);
   end else read_sector(fat_base+(cluster>>7),FAT_TEXT);
  end
  FAT_TEXT: begin
   if(!valid_cluster)state<=FAIL;
   else begin
    cluster<=next_cluster;cluster_sector<=0;
    read_sector(cluster_lba,text_kind?SUB_TEXT:PLAY_TEXT);
   end
  end
  END_TEXT: begin
   // Finalize a last line even when the file has no trailing newline.
   if(subtitle_chars!=0 && subtitle_line<4 && subtitle_map_valid)begin
    case(subtitle_target)0:subtitle_len0<=subtitle_chars;1:subtitle_len1<=subtitle_chars;
      2:subtitle_len2<=subtitle_chars;default:subtitle_len3<=subtitle_chars;endcase
   end
   state<=AFTER_SUB;
  end
  AFTER_SUB: begin
   if(pack_found && !pack_initialized && playlist_count!=0)begin
    pack_initial<=1;pack_record<=0;pack_sector<=0;pack_header_ok<=0;
    pack_byte_phase<=0;pack_font_address<=0;
    font_ready<=0;cluster<=pack_cluster;cluster_sector<=0;
    read_sector(cluster_lba,PACK_READ);
   end else begin
    scan_found_total<=playlist_count;emit_index<=0;
    if(playlist_count==0)begin scan_done<=1;state<=FAIL;end
    else state<=EMIT_FILES;
   end
  end
  PACK_WAIT:begin
   if(font_idle_sync[1] && font_quiet_sync[1]==font_quiet_request)
    read_sector(cluster_lba,pack_skip==0?PACK_READ:PACK_SEEK);
  end
  PACK_READ:begin
   if(!pack_header_ok)fail_pack;
   else begin
    if(pack_sector==0)begin
     if(pack_initial)begin
      if(pack_match0)subtitle_len0<=h[5];if(pack_match1)subtitle_len1<=h[5];
      if(pack_match2)subtitle_len2<=h[5];if(pack_match3)subtitle_len3<=h[5];
     end else case(pack_target_index)
      0:subtitle_len0<=h[5];1:subtitle_len1<=h[5];2:subtitle_len2<=h[5];3:subtitle_len3<=h[5];endcase
    end
    if(pack_sector==pack_last_sector)begin
     if(pack_initial && pack_record!=3)begin
      pack_record<=pack_record+1'b1;pack_sector<=0;pack_header_ok<=0;
      pack_next_state<=PACK_READ;state<=PACK_NEXT;
     end else begin
      if(pack_initial)begin
       pack_initialized<=1;pack_verified<=1;state<=AFTER_SUB;
       font_loaded_scene<=1;font_loaded_index<=0;
      end else begin
       font_loaded_scene<=pack_scene;font_loaded_index<=pack_target_index;state<=IDLE;
      end
      font_ready<=1;font_format24<=pack_format24;
     end
    end else begin pack_sector<=pack_sector+1'b1;pack_next_state<=PACK_READ;state<=PACK_NEXT;end
   end
  end
  PACK_SEEK:begin
   pack_skip<=pack_skip-1'b1;pack_next_state<=pack_skip==1?PACK_READ:PACK_SEEK;state<=PACK_NEXT;
  end
  PACK_NEXT:begin
   if(cluster_sector+1<spc)begin
    cluster_sector<=cluster_sector+1'b1;
    read_sector(next_sector_lba,pack_next_state);
   end else read_sector(fat_base+(cluster>>7),FAT_PACK);
  end
  FAT_PACK:begin
   if(!valid_cluster)fail_pack;
   else begin cluster<=next_cluster;cluster_sector<=0;
    read_sector(cluster_lba,pack_next_state);end
  end
  EMIT_FILES: begin
   if(emit_index<playlist_count)begin
    scan_found_sector<={29'b0,emit_index};scan_found_duration<=file_duration[emit_index];
    scan_found_scale<=file_scale[emit_index];scan_found_scene<=file_scene[emit_index];
    scan_found_valid<=1;emit_index<=emit_index+1'b1;
   end else begin scan_done<=1;audio_file_present<=selected_audio_found;state<=IDLE;end
  end
  HDR: begin
   if(!valid_bmp)state<=FAIL;
   else begin
    source_width<=header_width[15:0];source_height<=header_height[15:0];
    row_data_bytes<=header_row_bytes[11:0];row_stride<=header_stride[11:0];row_byte_count<=0;row_count<=0;
    pixel_offset<={h[11][4:0],h[10]};pixel_end<=selected_size;
    byte_phase<=0;image_start<=1;write_req<=1;watchdog<=0;state<=ACK;
   end
  end
  ACK: begin
   state_code<=3;watchdog<=watchdog+1'b1;
   if(transaction_timeout)state<=FAIL;
   if(write_req_ack) begin
    write_req<=0;read_sector(cluster_lba,PIX);
   end
  end
  PIX: begin
   state_code<=4;
   // Existing image semantics are unchanged; a truncated optional cover
   // must not be committed simply because its directory file size ran out.
   if(byte_count>=pixel_end)begin
    if(cover_loading && row_count!=source_height)state<=FAIL;
    else state<=IDLE;
   end
   else state<=NEXT_PIX;
  end
  NEXT_PIX: begin
   if(cluster_sector+1<spc) begin
    cluster_sector<=cluster_sector+1'b1;
    read_sector(next_sector_lba,PIX);
   end else read_sector(fat_base+(cluster>>7),FAT_PIX);
  end
  FAT_PIX: begin
   if(!valid_cluster)state<=FAIL;
   else begin
    cluster<=next_cluster;cluster_sector<=0;
    read_sector(cluster_lba,PIX);
   end
  end
  WAV_HDR:begin
   if(audio_restart || audio_abort_pending)state<=IDLE;
   else if(valid_wav_header && wav_tag_found && wav_data_size>=4 && wav_data_size[1:0]==0 &&
           audio_data_offset<=audio_file_size && wav_data_size<=audio_file_size-audio_data_offset)begin
    audio_file_present<=1;audio_format_error<=0;cluster<=audio_cluster;cluster_sector<=0;
    audio_sample_total<=wav_data_size>>2;
    audio_file_pos<=0;audio_data_remaining<=wav_data_size;audio_byte_phase<=0;
    read_sector(cluster_lba,AUDIO_DATA);
   end else begin audio_file_present<=0;audio_format_error<=1;state<=IDLE;end
  end
  AUDIO_DATA:begin
   state_code<=7;
   if(audio_restart || audio_abort_pending)state<=IDLE;
   else if(audio_data_remaining==0)begin
    cluster<=audio_cluster;cluster_sector<=0;audio_file_pos<=0;
    audio_data_remaining<=wav_data_size;audio_byte_phase<=0;
    if(audio_stream_enable && !audio_fifo_afull)
      read_sector(cluster_lba,AUDIO_DATA);
    else state<=AUDIO_READY;
   end else if(!audio_stream_enable || audio_fifo_afull)state<=AUDIO_READY;
   else state<=AUDIO_NEXT;
  end
  AUDIO_READY:begin
   state_code<=7;
   if(load_start)begin
    cover_loading<=load_sector==32'd4;
    cover_cancel_armed<=load_sector==32'd4;
    if(load_is_valid)begin
     cluster<=selected_image_cluster;selected_size<=selected_image_size;
     cluster_sector<=0;byte_count<=0;byte_phase<=0;
     read_sector(cluster_lba,HDR);
    end else state<=FAIL;
   end else if(pack_wanted)begin start_pack_font;end
   else if(scan_start || audio_restart || audio_abort_pending)state<=IDLE;
   else if(audio_stream_enable && !audio_fifo_afull)begin
    if(audio_file_pos==0)
      read_sector(cluster_lba,AUDIO_DATA);
    else state<=AUDIO_NEXT;
   end
  end
  AUDIO_NEXT:begin
   if(audio_restart || audio_abort_pending)state<=IDLE;
   else if(cluster_sector+1<spc)begin
    cluster_sector<=cluster_sector+1'b1;
    read_sector(next_sector_lba,AUDIO_DATA);
   end else read_sector(fat_base+(cluster>>7),FAT_AUDIO);
  end
  FAT_AUDIO:begin
   if(audio_restart || audio_abort_pending)state<=IDLE;
   else if(!valid_cluster)begin audio_format_error<=1;state<=IDLE;end
   else begin cluster<=next_cluster;cluster_sector<=0;
    read_sector(cluster_lba,AUDIO_DATA);end
  end
  FAIL: begin
   sd_sec_read<=0;write_req<=0;
   if(cover_loading)begin
    // The loader cancels the incomplete fifth-frame write and commits cached
    // image zero on cover_error. Normal image/scan failures stay fatal.
    cover_found<=0;cover_error<=1;cover_loading<=0;cover_cancel_armed<=0;
    state_code<=6;state<=IDLE;
   end else state_code<=14;
  end
  default:state<=FAIL;
  endcase
  // Highest priority: the scaler/writer can fail after the source has already
  // returned to IDLE. Keep cancellation armed for that sink-completion window,
  // not just while parsing pixels. Only the loader asserts it for a cover.
  // A disconnected legacy port is X/Z in simulation and does not take this if.
  if(cover_cancel && cover_cancel_armed)begin
   cover_found<=0;cover_error<=1;cover_loading<=0;cover_cancel_armed<=0;
   state<=IDLE;state_code<=6;sd_sec_read<=0;write_req<=0;
   bmp_data_wr_en<=0;image_start<=0;
   // START has not issued its request until this edge; the override above
   // suppresses it. RX has an outstanding request that must finish first.
   if(state==RX && !sd_sec_read_end)cover_read_draining<=1;
  end
 end
end
endmodule

// True dual-port RAM: port A is shared between directory writes and matcher
// reads; port B is read-only. These phases cannot overlap. There is no RAM reset.
module candidate_name_ram(
 input clk,input we,input [5:0] addr_a,addr_b,input [8:0] din,
 output [8:0] q_a,q_b
);
`ifdef __ICARUS__
 reg [8:0] mem[0:511];
 reg [8:0] qa,qb;
 always @(posedge clk)begin
  if(we)mem[addr_a]<=din;
  qa<=mem[addr_a];qb<=mem[addr_b];
 end
 assign q_a=qa;assign q_b=qb;
`else
 EG_LOGIC_BRAM #(
  .DATA_WIDTH_A(9),.DATA_WIDTH_B(9),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
  .DATA_DEPTH_A(512),.DATA_DEPTH_B(512),
  .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("READBEFOREWRITE"),.WRITEMODE_B("READBEFOREWRITE"),
  .RESETMODE("SYNC"),.IMPLEMENT("9K"),.INIT_FILE("NONE"),.FILL_ALL("NONE")
 ) ram(
  .dia(din),.dib(9'b0),.addra({3'b0,addr_a}),.addrb({3'b0,addr_b}),
  .cea(1'b1),.ceb(1'b1),.ocea(1'b0),.oceb(1'b0),.clka(clk),.clkb(clk),
  .wea(we),.web(1'b0),.bea(1'b0),.beb(1'b0),.rsta(1'b0),.rstb(1'b0),
  .doa(q_a),.dob(q_b)
 );
`endif
endmodule
