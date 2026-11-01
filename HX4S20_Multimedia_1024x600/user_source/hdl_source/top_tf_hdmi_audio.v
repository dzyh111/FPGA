`include "display_config.vh"

module top(
    input                       clk,
    input                       rst_n,
    input [3:0]                 switches,
    input                       key1,           // KEY2 / B2：手动下一张
    input                       key3,           // KEY3 / B1：菜单/选择
    input                       key2,           // KEY4 / C1：自动轮播开/关

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_WORDS   = 24'd307200;   // 1024*600 RGB565, two pixels/word
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_WORDS;
parameter BUF2_ADDR     = FRAME_WORDS * 2;
parameter BUF3_ADDR     = FRAME_WORDS * 3;
parameter COVER_ADDR    = FRAME_WORDS * 4; // Fifth external SDRAM frame; no image BRAM.

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire        display_valid;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;
(* ASYNC_REG = "TRUE" *) reg [3:0] state_seg_sync0;
(* ASYNC_REG = "TRUE" *) reg [3:0] state_seg_sync1;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx, active_buf_idx, current_image;
wire [1:0] next_buf_idx;
wire [9:0] slide_rows;
wire [4:0] fade_alpha;
wire transition_busy;
wire commit_manual,manual_transition;
wire [5:0] manual_phase;
wire commit_toggle,commit_ack,blank_toggle,blank_ack,auto_enabled;
wire rebuild_busy;
wire cover_commit,cover_write,cover_read,exhibition_started;
wire [2:0] rebuild_progress,rebuild_total;
wire frame_tick,scan_line_start,active,image_active,display_enabled;
wire [10:0] scan_x,scan_y,px,py;
wire pixel_valid;
wire [23:0] pixel_rgb;
wire menu_active;
wire [2:0] menu_item,brightness_level,contrast_level;
wire [1:0] scale_override;
wire [2:0] zoom_level;
reg [2:0] zoom_gray_sd;
(* ASYNC_REG="TRUE" *) reg [2:0] zoom_sync0,zoom_sync1;
reg [2:0] zoom_applied;
wire [2:0] zoom_decoded={zoom_sync1[2],zoom_sync1[2]^zoom_sync1[1],
                                     zoom_sync1[2]^zoom_sync1[1]^zoom_sync1[0]};
wire [10:0] screen_px,screen_py,overlay_screen_x,overlay_screen_y;
wire subtitle_wr_en;
wire [8:0] subtitle_wr_addr;
wire [7:0] subtitle_wr_data,subtitle_len0,subtitle_len1,subtitle_len2,subtitle_len3;
wire font_wr_en,font_ready,packed_subtitles,intro_done,intro_restart,intro_restart_ack;
wire font_cache_idle;
wire font_quiet_ack,font_quiet_request;
wire [9:0] font_wr_addr;
wire [17:0] font_wr_data;
wire [2:0] font_loaded_scene;
wire [1:0] font_loaded_index,intro_done_index;
(* ASYNC_REG="TRUE" *) reg [2:0] font_scene0,font_scene1;
(* ASYNC_REG="TRUE" *) reg [1:0] font_index0,font_index1;
(* ASYNC_REG="TRUE" *) reg font_valid0,font_valid1,pack0,pack1;
(* ASYNC_REG="TRUE" *) reg menu_video0,menu_video1,restart_video0,restart_video1;
wire [1:0] current_script_scale;
wire osd_valid,osd_sof,osd_last;
wire [23:0] osd_rgb;
wire [23:0] subtitle_paper_rgb,subtitle_ink_rgb;
wire waveform_line,waveform_halo;
wire [23:0] waveform_rgb;
wire sys_lock,video_lock,rst_sd,rst_mem,rst_video;
wire arst=~rst_n | ~sys_lock | ~video_lock;
reset_sync reset_sd(sd_card_clk,arst,rst_sd);
reset_sync reset_mem(ext_mem_clk,arst,rst_mem);
reset_sync reset_video(video_clk,arst,rst_video);

(* ASYNC_REG = "TRUE" *) reg [3:0] switches_video0,switches_video1;
(* ASYNC_REG = "TRUE" *) reg switches_sd0,switches_sd1;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin
  switches_video0<=4'hf;switches_video1<=4'hf;
  font_scene0<=0;font_scene1<=0;font_index0<=0;font_index1<=0;
  font_valid0<=0;font_valid1<=0;pack0<=0;pack1<=0;
  menu_video0<=0;menu_video1<=0;restart_video0<=0;restart_video1<=0;
 end else begin
  switches_video0<=switches;switches_video1<=switches_video0;
  font_scene0<=font_loaded_scene;font_scene1<=font_scene0;
  font_index0<=font_loaded_index;font_index1<=font_index0;
  font_valid0<=font_ready;font_valid1<=font_valid0;pack0<=packed_subtitles;pack1<=pack0;
  menu_video0<=menu_active;menu_video1<=menu_video0;
  restart_video0<=intro_restart;restart_video1<=restart_video0;
 end
end
always @(posedge sd_card_clk or posedge rst_sd)begin
 if(rst_sd)begin switches_sd0<=1;switches_sd1<=1;end
 else begin switches_sd0<=switches[2];switches_sd1<=switches_sd0;end
end
// Board DIP switches are ON-low (confirmed by the vendor key/switch demo).
wire spectrum_enable=~switches_video1[0] && !cover_read;
wire subtitle_enable=~switches_video1[1] && !cover_read;
wire audio_play_enable=~switches_video1[2] && !cover_read;
wire audio_mute=~switches_video1[3];

ui_control #(.CLK_HZ(40_000_000)) u_ui(
 .clk(sd_card_clk),.rst(rst_sd),.key_prev(key1 | !exhibition_started),
 .key_menu(key3 | !exhibition_started),.key_next(key2 | !exhibition_started),
 .menu_active(menu_active),.menu_item(menu_item),
 .brightness_level(brightness_level),.contrast_level(contrast_level),
 .scale_override(scale_override),.zoom_level(zoom_level));
// Adopt one stable zoom for the whole frame. The eight-clock scan request
// delay allows this bundle to settle before the memory-side frame handshake.
// Register Gray code at the source: adjacent KEY2/KEY4 steps change one bit.
always @(posedge sd_card_clk or posedge rst_sd)begin
 if(rst_sd)zoom_gray_sd<=3'd3; // Gray(100% index 2)
 else zoom_gray_sd<=zoom_level^{1'b0,zoom_level[2:1]};
end
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin zoom_sync0<=3;zoom_sync1<=3;zoom_applied<=2;end
 else begin
  zoom_sync0<=zoom_gray_sd;zoom_sync1<=zoom_sync0;
  if(frame_tick)zoom_applied<=cover_read?3'd2:(zoom_decoded<=4?zoom_decoded:3'd2);
 end
end

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

// HDMI 1.4b 音频发射相关
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;
wire signed [23:0] audio_analysis_sample;
wire audio_fifo_wr,audio_fifo_afull,audio_fifo_full,audio_fifo_empty,audio_fifo_read;
wire write_fifo_near_full;
wire [31:0] audio_fifo_wdata,audio_fifo_rdata;
wire audio_file_present,audio_format_error;
wire [2:0] current_scene;
wire [11:0] scene_map;
wire heritage_mode,audio_fifo_reset,audio_stream_reset;
wire [31:0] audio_sample_total,audio_sample_position;
wire audio_sample_consumed,audio_loop_toggle;
(* ASYNC_REG = "TRUE" *) reg [31:0] sample_total_s0,sample_total_s1;
(* ASYNC_REG = "TRUE" *) reg [2:0] scene_s0,scene_s1;
(* ASYNC_REG = "TRUE" *) reg [11:0] scene_map_s0,scene_map_s1;
reg [2:0] scene_video;
// Keep the art alive through the EXISTING whole-picture fade, rather than
// resetting the bow/sticks at its first frame (which caused a visible snap).
wire heritage_effect_enable=scene_video!=0 && display_enabled && !cover_read;
wire motion_valid,fx_valid,title_valid;
wire [10:0] motion_x,motion_y,fx_x,fx_y,title_x,title_y;
wire [23:0] motion_rgb,fx_rgb,title_rgb;
wire signed [5:0] bow_offset;
wire [4:0] drum_offset;
wire signed [2:0] bow_tilt;
wire signed [5:0] bow_angle;
wire [4:0] drum_right_offset;
reset_sync reset_audio_video(video_clk,arst | audio_fifo_reset,audio_stream_reset);
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin
  sample_total_s0<=0;sample_total_s1<=0;scene_s0<=0;scene_s1<=0;scene_video<=0;
  scene_map_s0<=0;scene_map_s1<=0;
 end else begin
  sample_total_s0<=audio_sample_total;sample_total_s1<=sample_total_s0;
  scene_s0<=current_scene;scene_s1<=scene_s0;
  scene_map_s0<=scene_map;scene_map_s1<=scene_map_s0;
  // Follow the buffer actually being scanned, including its fade-in. The
  // audio chapter changes later, only after the video commit is complete.
  if(frame_tick)if(cover_read)scene_video<=0;else case(active_buf_idx)
    0:scene_video<=scene_map_s1[2:0];1:scene_video<=scene_map_s1[5:3];
    2:scene_video<=scene_map_s1[8:6];3:scene_video<=scene_map_s1[11:9];
  endcase
 end
end

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 音频链路
wire rst_all;
assign rst_all = arst;

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .locked     (sys_lock),
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (~rst_n)
);

video_pll video_pll_m0(
    .locked     (video_lock),
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (~rst_n)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// The parser state changes slowly in the 40 MHz SD-card domain.  Synchronise
// it before driving the 50 MHz seven-segment display domain.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_seg_sync0 <= 4'd0;
        state_seg_sync1 <= 4'd0;
    end else begin
        state_seg_sync0 <= state_code;
        state_seg_sync1 <= state_seg_sync0;
    end
end

// TF: four preloaded 640x480 frames.
sd_card_bmp #(
    .CLK_FREQ_HZ       (40_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd8191),
    .SCAN_TARGET_COUNT (3'd4),
    .ENABLE_COVER      (1)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_sd),
    .key_next          (key1),
    .key_auto          (key2),
    .control_lock      (menu_active),
    .cover_commit      (cover_commit),
    .cover_write       (cover_write),
    .exhibition_started(exhibition_started),
    .audio_play_enable (~switches_sd1),
    .audio_fifo_afull  (audio_fifo_afull),
    .audio_file_present(audio_file_present),
    .audio_format_error(audio_format_error),
    .audio_pcm_wr      (audio_fifo_wr),
    .audio_pcm_word    (audio_fifo_wdata),
    .current_scene     (current_scene),
    .scene_map         (scene_map),
    .heritage_mode     (heritage_mode),
    .audio_fifo_reset  (audio_fifo_reset),
    .audio_sample_total(audio_sample_total),
    .audio_loop_toggle (audio_loop_toggle),
    .scale_override    (2'd0), // Zoom never restarts TF loading or the audio FIFO.
    .blank_toggle      (blank_toggle),
    .blank_ack         (blank_ack),
    .rebuild_busy      (rebuild_busy),
    .rebuild_progress  (rebuild_progress),
    .rebuild_total     (rebuild_total),
    .state_code        (state_code),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),

    .commit_toggle     (commit_toggle),
    .commit_manual     (commit_manual),
    .commit_ack        (commit_ack),
    .current_image     (current_image),
    .auto_enabled      (auto_enabled),
    .current_script_scale(current_script_scale),
    .subtitle_wr_en(subtitle_wr_en),.subtitle_wr_addr(subtitle_wr_addr),.subtitle_wr_data(subtitle_wr_data),
    .subtitle_len0(subtitle_len0),.subtitle_len1(subtitle_len1),.subtitle_len2(subtitle_len2),.subtitle_len3(subtitle_len3),
    .font_wr_en(font_wr_en),.font_wr_addr(font_wr_addr),.font_wr_data(font_wr_data),.font_format24(),
    .font_ready(font_ready),.font_loaded_scene(font_loaded_scene),.font_loaded_index(font_loaded_index),
    .packed_subtitles(packed_subtitles),.intro_done(intro_done),.intro_done_index(intro_done_index),
    .font_cache_idle(font_cache_idle),
    .font_quiet_ack(font_quiet_ack),.font_quiet_request(font_quiet_request),
    .intro_restart(intro_restart),.intro_restart_ack(intro_restart_ack),
    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_fifo_near_full(write_fifo_near_full),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

seg_decoder seg_decoder_m0(
    .bin_data          (state_seg_sync1),
    .seg_data          (seg_data_0)
);

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,7'b1111_111}),
    .seg_data_1        ({1'b1,7'b1111_111}),
    .seg_data_2        ({1'b1,7'b1111_111}),
    .seg_data_3        ({1'b1,7'b1111_111}),
    .seg_data_4        ({1'b1,7'b1111_111}),
    .seg_data_5        ({1'b1,seg_data_0})
);

// The five cached 1024x600 canvases remain intact. Zoom is a read-side map,
// applied in one frame without TF reads, cache rewriting or a blank/fade cycle.
video_scan #(.IMG_W(1024),.IMG_H(600),.ENABLE_COVER(1)) u_scan(
 .clk(video_clk),.rst(rst_video),.commit_toggle(commit_toggle),.commit_index(disp_buf_idx),
 .commit_manual(commit_manual),.manual_transition(manual_transition),
 .manual_phase(manual_phase),
 .commit_cover(cover_commit),.read_cover(cover_read),
 .blank_toggle(blank_toggle),.blank_ack(blank_ack),
 .commit_ack(commit_ack),.read_index(active_buf_idx),.next_index(next_buf_idx),.slide_rows(slide_rows),.read_req(video_read_req),
 .fade_alpha(fade_alpha),.transition_busy(transition_busy),
 .read_req_ack(video_read_req_ack),.display_enabled(display_enabled),
 .frame_tick(frame_tick),.line_start(scan_line_start),
 .active(active),.image_active(image_active),.x(scan_x),.y(scan_y));
video_zoom_rgb565 u_pixels(
 .clk(video_clk),.rst(rst_video),.active(active),
 .frame_tick(frame_tick),.line_start(scan_line_start),
 .cover_active(cover_read),.zoom_index(zoom_applied),
 .display_enabled(display_enabled),.x(scan_x),.y(scan_y),.read_data(video_read_data),
 .read_en(video_read_en),.valid(pixel_valid),.src_x(px),.src_y(py),
 .screen_x(screen_px),.screen_y(screen_py),.rgb(pixel_rgb));
video_xy_delay #(.STAGES(9)) u_screen_xy(
 .clk(video_clk),.rst(rst_video),.x(screen_px),.y(screen_py),
 .out_x(overlay_screen_x),.out_y(overlay_screen_y));
heritage_motion_layer u_motion(
 .clk(video_clk),.rst(rst_video),.scene(display_enabled && !cover_read?scene_video:3'd0),
 .bow_offset(bow_offset),.bow_angle(bow_angle),
 .drum_offset(drum_offset),.drum_right_offset(drum_right_offset),
 .valid(pixel_valid),.x(px),.y(py),.rgb(pixel_rgb),
 .out_valid(motion_valid),.out_x(motion_x),.out_y(motion_y),.out_rgb(motion_rgb));
heritage_fx u_heritage_fx(
 .clk(video_clk),.rst(rst_video),.frame_tick(frame_tick),
 .enable(heritage_effect_enable),.stream_reset(audio_stream_reset),.scene(scene_video),
 .sample_consumed(audio_sample_consumed),.sample_position(audio_sample_position),
 .valid(motion_valid),.x(motion_x),.y(motion_y),.rgb(motion_rgb),
 .out_valid(fx_valid),.out_x(fx_x),.out_y(fx_y),.out_rgb(fx_rgb),
 .bow_offset(bow_offset),.bow_tilt(bow_tilt),
 .bow_angle(bow_angle),
 .drum_offset(drum_offset),.drum_right_offset(drum_right_offset));
calligraphy_title u_title(
 .clk(video_clk),.rst(rst_video),.frame_tick(frame_tick),
 .enable(heritage_effect_enable),.scene(scene_video),
 .valid(fx_valid),.x(fx_x),.y(fx_y),.rgb(fx_rgb),
 .out_valid(title_valid),.out_x(title_x),.out_y(title_y),.out_rgb(title_rgb));
media_osd #(.ENABLE_COVER(1),.SUBTITLE_PALETTE(1),.DEFER_WAVEFORM(1)) u_osd(
 .clk(video_clk),.rst(rst_video),.frame_tick(frame_tick),
 .cover_active(cover_read),
 .state_code(state_code),
 .fade_alpha(fade_alpha),.menu_active(menu_active),.menu_item(menu_item),
 .manual_transition(manual_transition),
 .manual_phase(manual_phase),
 .rebuild_busy(rebuild_busy),.rebuild_progress(rebuild_progress),.rebuild_total(rebuild_total),
 .brightness_level(brightness_level),.contrast_level(contrast_level),.zoom_level(zoom_applied),
 .scale_override(scale_override),.spectrum_enable(spectrum_enable),
 .scene(heritage_effect_enable?scene_video:3'd0),
 .audio_valid(audio_sample_consumed),.audio_sample(audio_analysis_sample),
 .audio_stream_reset(audio_stream_reset),
 .valid(title_valid),.x(overlay_screen_x),.y(overlay_screen_y),.rgb(title_rgb),
 .out_valid(osd_valid),.out_sof(osd_sof),.out_last(osd_last),.out_rgb(osd_rgb),
 .subtitle_paper_rgb(subtitle_paper_rgb),.subtitle_ink_rgb(subtitle_ink_rgb),
 .waveform_line(waveform_line),.waveform_halo(waveform_halo),.waveform_rgb(waveform_rgb));
subtitle_overlay #(.ENABLE_FONT24(1),.TRANSITION_PALETTE(1),.WAVEFORM_ON_TOP(1)) u_subtitles(
 .wr_clk(sd_card_clk),.wr_en(subtitle_wr_en),.wr_addr(subtitle_wr_addr),.wr_data(subtitle_wr_data),
 .font_wr_en(font_wr_en),.font_wr_addr(font_wr_addr),.font_wr_data(font_wr_data),
 .font_ready(font_valid1 && (!pack1 || (font_scene1==scene_video && font_index1==active_buf_idx))),
 .clk(video_clk),.rst(rst_video),.frame_tick(frame_tick),.enable(subtitle_enable),
 .intro_pause(!audio_play_enable || menu_video1),.intro_restart(restart_video1),
 .intro_done(intro_done),.intro_done_index(intro_done_index),.intro_restart_ack(intro_restart_ack),
 .font_cache_idle(font_cache_idle),
 .font_quiet_request(font_quiet_request),.font_quiet_ack(font_quiet_ack),
 // Font scene/index and quiet-token readiness prevent stale captions. The
 // aligned colour palette now hides/reveals captions with the picture, so
 // waiting for transition_busy to clear would unnecessarily delay them.
 .show_picture(display_enabled && state_code!=14 && !cover_read),.image_index(active_buf_idx),
 .len0(subtitle_len0),.len1(subtitle_len1),.len2(subtitle_len2),.len3(subtitle_len3),
 .valid(osd_valid),.sof(osd_sof),.last(osd_last),.rgb(osd_rgb),
 .subtitle_paper_rgb(subtitle_paper_rgb),.subtitle_ink_rgb(subtitle_ink_rgb),
 .waveform_line(waveform_line),.waveform_halo(waveform_halo),.waveform_rgb(waveform_rgb),
 .out_valid(axis_s_valid),.out_sof(axis_s_user),.out_last(axis_s_last),.out_rgb(axis_s_data));

// Cover base selection settles before the existing request handshake. The
// video scan waits eight clocks; the loader selects COVER before its header.
(* ASYNC_REG = "TRUE" *) reg cover_read_m0,cover_read_m1,cover_write_m0,cover_write_m1;
always @(posedge ext_mem_clk or posedge rst_mem)begin
 if(rst_mem)begin cover_read_m0<=0;cover_read_m1<=0;cover_write_m0<=0;cover_write_m1<=0;end
 else begin
  cover_read_m0<=cover_read;cover_read_m1<=cover_read_m0;
  cover_write_m0<=cover_write;cover_write_m1<=cover_write_m0;
 end
end

frame_read_write #(
    .ENABLE_ZOOM      (1),
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (512),
    .FRAME_HEIGHT     (600)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_zoom         (cover_read ? 3'd2 : zoom_applied),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (cover_read_m1?COVER_ADDR:BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (BUF2_ADDR),
    .read_addr_3       (BUF3_ADDR),
    .read_addr_index   (active_buf_idx),
    .read_next_index   (next_buf_idx),
    .read_slide_rows   (slide_rows),
    .read_len          (FRAME_WORDS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (cover_write_m1?COVER_ADDR:BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (BUF2_ADDR),
    .write_addr_3      (BUF3_ADDR),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_WORDS),
    .write_en          (sd_card_write_en),
    .write_fifo_near_full(write_fifo_near_full),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

wfifo_32_32_512 #(.AL_FULL_NUM(384),.AL_EMPTY_NUM(2)) u_audio_fifo(
 .rst(rst_all | audio_fifo_reset | audio_stream_reset),.clkw(sd_card_clk),.clkr(video_clk),
 .we(audio_fifo_wr),.di(audio_fifo_wdata),.re(audio_fifo_read),.dout(audio_fifo_rdata),
 .valid(),.full_flag(audio_fifo_full),.empty_flag(audio_fifo_empty),
 .afull(audio_fifo_afull),.aempty(),.wrusedw(),.rdusedw());

wav_audio_player u_wav_audio(
 // Do not consume the first PCM samples until the matching scene has been
 // latched at a video frame boundary. Otherwise its cue clock starts late.
 .clk(video_clk),.rst(rst_video),
 .play_enable(audio_play_enable && scene_s1==scene_video),.mute(audio_mute),
 .stream_reset(audio_stream_reset),.sample_total(sample_total_s1),
 .fifo_data(audio_fifo_rdata),.fifo_empty(audio_fifo_empty),.fifo_read(audio_fifo_read),
 .valid(audio_valid),.analysis_sample(audio_analysis_sample),
 .sample_consumed(audio_sample_consumed),.sample_position(audio_sample_position),
 .loop_toggle(audio_loop_toggle),
 .left_data(audio_left_data),.right_data(audio_right_data),
 .acr_valid(acr_valid),.acr_n(acr_n),.acr_cts(acr_cts));

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_video),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( `H_TOTAL ),
    .HSA                    ( `H_SYNC ),
    .HFP                    ( `H_FP ),
    .HBP                    ( `H_BP ),
    .HACTIVE                ( `H_ACTIVE ),
    .VTOTAL                 ( `V_TOTAL ),
    .VSA                    ( `V_SYNC ),
    .VFP                    ( `V_FP ),
    .VBP                    ( `V_BP ),
    .VACTIVE                ( `V_ACTIVE ),
    .VIDEO_VIC              ( 0 ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 512 )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_video),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_video),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
