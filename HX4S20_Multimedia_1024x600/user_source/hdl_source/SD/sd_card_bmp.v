
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4,
    parameter integer ENABLE_COVER = 0
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    input                       control_lock,
    output reg                  cover_commit,
    output reg                  cover_write,
    output                      cover_abort,
    output                      exhibition_started,
    input                       audio_play_enable,
    input                       audio_fifo_afull,
    output                      audio_file_present,
    output                      audio_format_error,
    output                      audio_pcm_wr,
    output [31:0]               audio_pcm_word,
    input                       audio_loop_toggle,
    output                      audio_fifo_reset,
    output [31:0]               audio_sample_total,
    output [2:0]                current_scene,
    output [11:0]               scene_map,
    output                      heritage_mode,
    input  [1:0]                scale_override,
    output reg                  blank_toggle,
    input                       blank_ack,
    output                      rebuild_busy,
    output [2:0]                rebuild_progress,
    output [2:0]                rebuild_total,
    output [3:0]                state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,

    input                       write_finish_toggle,
    output reg                  commit_toggle,
    output reg                  commit_manual,
    input                       commit_ack,
    output [1:0]                current_image,
    output                      auto_enabled,
    output [1:0]                current_script_scale,
    output                      subtitle_wr_en,
    output [8:0]                subtitle_wr_addr,
    output [7:0]                subtitle_wr_data,
    output [7:0]                subtitle_len0,
    output [7:0]                subtitle_len1,
    output [7:0]                subtitle_len2,
    output [7:0]                subtitle_len3,
    output                      font_wr_en,
    output [9:0]                font_wr_addr,
    output [17:0]               font_wr_data,
    output                      font_ready,
    output                      font_format24,
    output [2:0]                font_loaded_scene,
    output [1:0]                font_loaded_index,
    output                      packed_subtitles,
    input                       font_cache_idle,
    input                       font_quiet_ack,
    output                      font_quiet_request,
    input                       intro_done,
    input [1:0]                 intro_done_index,
    input                       intro_restart_ack,
    output reg                  intro_restart,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    input                       write_fifo_near_full,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

wire key_next_press;
wire key_auto_press;
wire key_next_event=key_next_press && !control_lock;
wire key_auto_event=key_auto_press && !control_lock;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire [15:0]      source_width,source_height;
wire             image_start,scaled_valid,scaled_done,scale_overrun,scale_config_ready;
wire             scale_input_start_ready;
wire [23:0]      scaled_data;
wire             sd_init_done;
wire             bmp_ready;
wire             scan_done;
wire             reader_cover_found;
wire             reader_cover_error;
reg              cover_cancel;
reg [3:0]        cover_abort_pipe;
assign cover_abort=|cover_abort_pipe;
wire render_rst=rst || cover_abort;
reg              cover_loaded,started;
wire cover_waiting=ENABLE_COVER && reader_cover_found && !cover_loaded;
assign exhibition_started=started;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [2:0]       scan_found_total;
wire [7:0]       scan_found_duration;
wire [1:0]       scan_found_scale;
wire [2:0]       scan_found_scene;
wire             reader_audio_reset_busy;
wire [2:0] pending_scene=pending_image_idx==0?scene0:pending_image_idx==1?scene1:
                         pending_image_idx==2?scene2:scene3;
wire scene_audio_switch=commit_pending && (current_scene!=0 || pending_scene!=0);
// Heritage chapters restart their matching sound. A legacy image-to-image
// (scene 0 -> 0) commit keeps the original continuous 111.WAV background audio.
// For a sound change hold both FIFO domains clear through SD sector draining
// and the frame-boundary image acknowledgement.
wire audio_switch_hold=!display_valid || !started || scene_audio_switch || rebuild_active || rebuild_wait_blank;
assign audio_fifo_reset=audio_switch_hold || reader_audio_reset_busy;
wire audio_stream_enable=audio_play_enable && started && scan_done && display_valid &&
                         loaded_count==img_found_count && !load_busy &&
                         !rebuild_active && !rebuild_wait_blank && !scene_audio_switch;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [2:0]        img_found_count;
reg [1:0]        img_idx;              // 当前真正显示中的图片编号
reg [1:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg [7:0]        duration0,duration1,duration2,duration3;
reg [1:0]        scale0,scale1,scale2,scale3;
reg [2:0]        scene0,scene1,scene2,scene3;
reg              audio_auto_pending;
(* ASYNC_REG = "TRUE" *) reg [1:0] audio_loop_sync;
reg              audio_loop_seen;
(* ASYNC_REG="TRUE" *) reg [1:0] intro_done_sync;
(* ASYNC_REG="TRUE" *) reg [1:0] intro_restart_sync;
(* ASYNC_REG="TRUE" *) reg [1:0] intro_index0,intro_index1;
reg intro_armed;
reg [7:0]        auto_elapsed;
reg              next_req_pending;
reg              load_busy;
reg              scale_output_start,scale_started;
reg              writer_ack_seen;
wire             reader_write_req;
wire             packed_write_en,pack_half;
wire [31:0]      packed_write_data;
reg [1:0]        applied_scale_override,rebuild_image;
reg              rebuild_active,rebuild_wait_blank;
reg              render_error;
reg [31:0]       render_watchdog;
(* ASYNC_REG = "TRUE" *) reg [1:0] blank_ack_sync;

// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;
reg              memory_done_seen;
reg              commit_pending;
reg [1:0]        pending_image_idx;
reg [2:0]        loaded_count;
reg [1:0]        commit_ack_sync;
reg [1:0]        write_ack_sync;
reg              source_busy_seen;
assign current_image=img_idx;
assign auto_enabled=auto_play_en;
assign current_script_scale=scale_lut(img_idx);
assign current_scene=img_idx==0?scene0:img_idx==1?scene1:img_idx==2?scene2:scene3;
assign scene_map={scene3,scene2,scene1,scene0};
assign heritage_mode=current_scene!=0;
assign rebuild_busy=rebuild_active || rebuild_wait_blank;
assign rebuild_progress=loaded_count;
assign rebuild_total=img_found_count;
wire [3:0] reader_state_code;
assign state_code=render_error ? 4'd14 : reader_state_code;
always @(posedge clk or posedge rst) begin
    if(rst) begin commit_ack_sync<=0;write_ack_sync<=0;blank_ack_sync<=0;audio_loop_sync<=0;
     intro_done_sync<=0;intro_restart_sync<=0;intro_index0<=0;intro_index1<=0;end
    else begin
     commit_ack_sync<={commit_ack_sync[0],commit_ack};
     write_ack_sync<={write_ack_sync[0],write_req_ack};
     blank_ack_sync<={blank_ack_sync[0],blank_ack};
     audio_loop_sync<={audio_loop_sync[0],audio_loop_toggle};
     intro_done_sync<={intro_done_sync[0],intro_done};
     intro_restart_sync<={intro_restart_sync[0],intro_restart_ack};
     intro_index0<=intro_done_index;intro_index1<=intro_index0;
    end
end

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
wire auto_advance;
wire heritage_audio_clock=heritage_mode && audio_file_present && !audio_format_error;
wire [7:0] intro_length=img_idx==0?subtitle_len0:img_idx==1?subtitle_len1:img_idx==2?subtitle_len2:subtitle_len3;
// The optional pack describes the four named instruments only. An ordinary
// BMP mixed into that playlist has no matching font page and must retain the
// legacy audio/script clock, rather than wait forever for an invisible intro.
wire intro_clock_valid=intro_length!=0 && (!packed_subtitles || heritage_mode);
wire auto_next_due=(intro_clock_valid || heritage_audio_clock) ? audio_auto_pending : auto_advance;
wire manual_due=next_req_pending || key_next_event;
wire [1:0] next_from_current;

assign write_en   = packed_write_en && !cover_abort && !cover_fallback;
assign write_data = packed_write_data;
assign write_req  = reader_write_req && !writer_ack_seen && !cover_abort;
assign auto_tick  = (auto_cnt == (CLK_FREQ_HZ - 1));
assign auto_advance=auto_tick && (auto_elapsed+1'b1>=duration_lut(img_idx));
assign next_from_current = next_index_limited(img_idx, img_found_count);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press)
);

function [1:0] next_index_limited;
    input [1:0] cur;
    input [2:0] count;
    begin
        case (count)
            3'd0: next_index_limited = 2'd0;
            3'd1: next_index_limited = 2'd0;
            3'd2: next_index_limited = (cur == 2'd1) ? 2'd0 : (cur + 2'd1);
            3'd3: next_index_limited = (cur == 2'd2) ? 2'd0 : (cur + 2'd1);
            default: next_index_limited = (cur == 2'd3) ? 2'd0 : (cur + 2'd1);
        endcase
    end
endfunction

function [7:0] duration_lut;
    input [1:0] idx;
    begin case(idx)0:duration_lut=duration0;1:duration_lut=duration1;
      2:duration_lut=duration2;default:duration_lut=duration3;endcase end
endfunction
function [1:0] scale_lut;
    input [1:0] idx;
    begin case(idx)0:scale_lut=scale0;1:scale_lut=scale1;
      2:scale_lut=scale2;default:scale_lut=scale3;endcase end
endfunction
function [1:0] effective_scale;
    input [1:0] idx;
    begin effective_scale=applied_scale_override==0?scale_lut(idx):applied_scale_override;end
endfunction
always @(posedge clk or posedge render_rst)begin
 if(render_rst)begin
  scale_output_start<=0;scale_started<=0;writer_ack_seen<=0;
 end else begin
  scale_output_start<=0;
  if(image_start)begin scale_started<=0;writer_ack_seen<=0;end
  else if(write_ack_sync[1])writer_ack_seen<=1;
  // The writer holds its FIFO in reset while write_req remains high. Release
  // that request on its ACK, then wait until the ACK falls before emitting
  // the first border pixel. The BMP reader may remain in ACK independently.
  if(reader_write_req && writer_ack_seen && !write_ack_sync[1] &&
     scale_config_ready && !scale_started)begin
   scale_output_start<=1;scale_started<=1;
  end
 end
end

rgb565_packer u_packer(.clk(clk),.rst(render_rst),.clear(image_start),
 .valid(scaled_valid),.rgb(scaled_data),.write_en(packed_write_en),
 .write_data(packed_write_data),.half_pending(pack_half));

function [31:0] sector_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: sector_lut = img_sector0;
            2'd1: sector_lut = img_sector1;
            2'd2: sector_lut = img_sector2;
            2'd3: sector_lut = img_sector3;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        commit_toggle         <= 1'b0;
        commit_manual<=0;intro_restart<=0;intro_armed<=0;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0;
        auto_elapsed<=0;
        duration0<=5;duration1<=5;duration2<=5;duration3<=5;
        scale0<=2;scale1<=2;scale2<=2;scale3<=2;
        scene0<=0;scene1<=0;scene2<=0;scene3<=0;
        audio_loop_seen<=0;audio_auto_pending<=0;
        img_found_count       <= 3'd0;
        loaded_count          <= 3'd0;
        img_idx               <= 2'd0;
        load_idx              <= 2'd0;
        pending_image_idx     <= 2'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        next_req_pending      <= 1'b0;
        load_busy             <= 1'b0;
        source_done_seen      <= 1'b0;
        memory_done_seen      <= 1'b0;
        source_busy_seen      <= 1'b0;
        commit_pending        <= 1'b0;
        display_valid         <= 1'b0;
        blank_toggle          <= 1'b0;
        applied_scale_override<= 2'd0;
        rebuild_image         <= 2'd0;
        rebuild_active        <= 1'b0;
        rebuild_wait_blank    <= 1'b0;
        render_error          <= 1'b0;
        render_watchdog       <= 32'd0;
        cover_commit<=0;cover_write<=0;cover_loaded<=0;started<=!ENABLE_COVER;
        cover_cancel<=0;cover_abort_pipe<=0;
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;
        cover_cancel<=0;cover_abort_pipe<={1'b0,cover_abort_pipe[3:1]};
        audio_loop_seen<=audio_loop_sync[1];
        if(!intro_done_sync[1] && !commit_pending && intro_restart_sync[1]==intro_restart)intro_armed<=1;
        if(intro_done_sync[1] && intro_index1==img_idx && intro_armed &&
           auto_play_en && intro_clock_valid && display_valid && !commit_pending)
            audio_auto_pending<=1;
        // Legacy cards with no introductions retain their audio/script clock.
        if(audio_loop_sync[1]!=audio_loop_seen && auto_play_en && !intro_clock_valid &&
           heritage_audio_clock && display_valid && !commit_pending)audio_auto_pending<=1;

        if (!sd_init_done) begin
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            auto_elapsed<=0;
            audio_auto_pending<=0;
            img_found_count       <= 3'd0;
            loaded_count          <= 3'd0;
            img_idx               <= 2'd0;
            load_idx              <= 2'd0;
            pending_image_idx     <= 2'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            next_req_pending      <= 1'b0;
            load_busy             <= 1'b0;
            source_done_seen      <= 1'b0;
            memory_done_seen      <= 1'b0;
            source_busy_seen      <= 1'b0;
            commit_pending        <= 1'b0;
            display_valid         <= 1'b0;
            blank_toggle          <= 1'b0;
            applied_scale_override<= scale_override;
            rebuild_image         <= 2'd0;
            rebuild_active        <= 1'b0;
            rebuild_wait_blank    <= 1'b0;
            render_error          <= 1'b0;
            render_watchdog       <= 32'd0;
            cover_commit<=0;cover_write<=0;cover_loaded<=0;started<=!ENABLE_COVER;
            cover_cancel<=0;cover_abort_pipe<=0;
            commit_manual<=0;intro_armed<=0;
        end else begin
            // Watch inactivity, not total BMP duration. Large ORIGINAL files
            // can legitimately take much longer than 15 seconds over TF SPI.
            if(load_busy)begin
                if(bmp_data_wr_en || scaled_valid || write_finish_pulse)
                    render_watchdog<=0;
                else if(render_watchdog >= RENDER_STALL_CYCLES-1 || scale_overrun)begin
                    render_error<=1'b1;
                    load_busy<=1'b0;
                    rebuild_active<=1'b0;
                    rebuild_wait_blank<=1'b0;
                    display_valid<=1'b0;
                end else render_watchdog<=render_watchdog+1'b1;
            end else render_watchdog<=0;
            // Apply a menu scale selection only after the menu closes. Fade to
            // the background before rewriting any frame buffer.
            if(scan_done && started && !control_lock && scale_override!=applied_scale_override &&
               !load_busy && !commit_pending && !rebuild_active && !rebuild_wait_blank)begin
                rebuild_image<=img_idx;
                if(display_valid)begin
                    blank_toggle<=~blank_toggle;rebuild_wait_blank<=1;
                end else begin
                    applied_scale_override<=scale_override;loaded_count<=0;
                    first_image_committed<=0;rebuild_active<=1;
                end
            end
            if(rebuild_wait_blank && blank_ack_sync[1]==blank_toggle)begin
                rebuild_wait_blank<=0;rebuild_active<=1;
                applied_scale_override<=scale_override;loaded_count<=0;
                first_image_committed<=0;display_valid<=0;
            end
            // Cache the first four BMP locations discovered by the scanner.
            if (scan_found_valid) begin
                case (img_found_count)
                    3'd0: begin img_sector0<=scan_found_sector;duration0<=scan_found_duration;scale0<=scan_found_scale;scene0<=scan_found_scene;end
                    3'd1: begin img_sector1<=scan_found_sector;duration1<=scan_found_duration;scale1<=scan_found_scale;scene1<=scan_found_scene;end
                    3'd2: begin img_sector2<=scan_found_sector;duration2<=scan_found_duration;scale2<=scan_found_scale;scene2<=scan_found_scene;end
                    3'd3: begin img_sector3<=scan_found_sector;duration3<=scan_found_duration;scale3<=scan_found_scale;scene3<=scan_found_scene;end
                    default: ;
                endcase
                if (img_found_count < 3'd4)
                    img_found_count <= img_found_count + 3'd1;
            end

            if (load_busy && !bmp_ready)
                source_busy_seen <= 1'b1;
            if (load_busy && source_busy_seen && bmp_ready)
                source_done_seen <= 1'b1;
            if (load_busy && write_finish_pulse)
                memory_done_seen <= 1'b1;

            // A frame becomes usable only after both the BMP source and SDRAM writer finish.
            if (load_busy && source_done_seen && memory_done_seen && !cover_fallback) begin
                load_busy        <= 1'b0;
                if(!cover_write)loaded_count<=loaded_count+3'd1;
                source_done_seen <= 1'b0;
                memory_done_seen <= 1'b0;
                source_busy_seen <= 1'b0;
                // Start scanout only after all frames are cached.  The SDRAM writer has
                // priority over the reader, so this avoids visible FIFO starvation while
                // the remaining BMP files are being loaded in the background.
                if(cover_write)begin
                    commit_manual<=0;
                    cover_loaded<=1;cover_write<=0;cover_commit<=1;
                    disp_buf_idx<=0;pending_image_idx<=0;
                    commit_toggle<=~commit_toggle;commit_pending<=1;
                end else if ((loaded_count + 3'd1 >= img_found_count) &&
                    !first_image_committed && !commit_pending && !cover_waiting) begin
                    started<=1;cover_commit<=0;
                    commit_manual<=0;
                    disp_buf_idx      <= rebuild_active?rebuild_image:2'd0;
                    pending_image_idx <= rebuild_active?rebuild_image:2'd0;
                    commit_toggle     <= ~commit_toggle;
                    commit_pending    <= 1'b1;
                end
            end

            // Complete a frame-boundary buffer switch after the video domain acknowledges it.
            if (commit_pending && commit_ack_sync[1] == commit_toggle) begin
                commit_pending        <= 1'b0;
                img_idx               <= pending_image_idx;
                display_valid         <= 1'b1;
                first_image_committed <= 1'b1;
                rebuild_active        <= 1'b0;
                audio_auto_pending    <= 1'b0;
                intro_armed<=0;
            end

            // Start one scan after card initialisation.
            if (!scan_kicked && bmp_ready) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                audio_auto_pending    <= 1'b0;
                img_found_count       <= 3'd0;
                loaded_count          <= 3'd0;
                next_req_pending      <= 1'b0;
                display_valid         <= 1'b0;
                render_error          <= 1'b0;
                cover_commit<=0;cover_write<=0;cover_loaded<=0;started<=!ENABLE_COVER;
                commit_manual<=0;intro_armed<=0;
            end else begin
                // The first KEY2 enters image zero; it must not skip GUQIN.
                if(key_next_event && cover_loaded && !started && display_valid && !commit_pending)begin
                    commit_manual<=1;intro_armed<=0;
                    started<=1;cover_commit<=0;
                    pending_image_idx<=0;disp_buf_idx<=0;
                    commit_toggle<=~commit_toggle;commit_pending<=1;
                    next_req_pending<=0;
                end
                if (started && key_next_event && scan_done && loaded_count != 3'd0)
                    next_req_pending <= 1'b1;

                if (started && key_auto_event && scan_done && loaded_count > 3'd1) begin
                    auto_play_en <= ~auto_play_en;
                    auto_cnt     <= 32'd0;
                    auto_elapsed <= 0;
                    audio_auto_pending<=0;
                    intro_armed<=0;
                    if(!auto_play_en)intro_restart<=~intro_restart;
                end

                // Count continuously while playback is idle. TF preloading no longer delays it.
                if (started && scan_done && auto_play_en && display_valid && !commit_pending && loaded_count > 3'd1 && !control_lock && audio_play_enable) begin
                    if (auto_tick) begin
                        auto_cnt<=0;
                        if(auto_advance)auto_elapsed<=0;else auto_elapsed<=auto_elapsed+1'b1;
                    end else auto_cnt <= auto_cnt + 32'd1;
                end else if(!control_lock && audio_play_enable) begin
                    auto_cnt <= 32'd0;
                    auto_elapsed<=0;
                end

                // Preload every discovered image once into its own SDRAM frame buffer.
                if (scan_done && bmp_ready && !load_busy && loaded_count < img_found_count) begin
                    cover_write       <= 1'b0;
                    load_idx          <= loaded_count[1:0];
                    load_sector       <= sector_lut(loaded_count[1:0]);
                    pending_buf_idx   <= loaded_count[1:0];
                    write_buf_idx     <= loaded_count[1:0];
                    load_start_pulse  <= 1'b1;
                    load_busy         <= 1'b1;
                    source_done_seen  <= 1'b0;
                    memory_done_seen  <= 1'b0;
                    source_busy_seen  <= 1'b0;
                    render_watchdog   <= 32'd0;
                end

                // Switching a preloaded image only changes the SDRAM read base at frame boundary.
                // Cache the cover before scanout: the SDRAM writer has priority.
                if(scan_done && bmp_ready && !load_busy && !cover_abort && loaded_count==img_found_count &&
                   img_found_count!=0 && cover_waiting && !first_image_committed)begin
                    cover_write<=1;write_buf_idx<=0;load_sector<=32'd4;
                    load_start_pulse<=1;load_busy<=1;
                    source_done_seen<=0;memory_done_seen<=0;source_busy_seen<=0;
                    render_watchdog<=0;
                end

                if (started && display_valid && !commit_pending && loaded_count != 3'd0 && !control_lock &&
                    (manual_due || (auto_play_en && !key_auto_event && audio_play_enable && auto_next_due))) begin
                    commit_manual<=manual_due;intro_armed<=0;
                    pending_image_idx <= next_index_limited(img_idx, loaded_count);
                    disp_buf_idx      <= next_index_limited(img_idx, loaded_count);
                    commit_toggle     <= ~commit_toggle;
                    commit_pending    <= 1'b1;
                    next_req_pending  <= 1'b0;
                    auto_cnt          <= 32'd0;
                    auto_elapsed<=0;
                    audio_auto_pending<=0;
                end
            end

            // Optional artwork must never strand the four valid cached frames.
            // Flush only the source/scaler/packer. Do not reset the SDRAM write
            // FSM mid-burst: accepted words finish in the discarded fifth frame.
            // Its CHECK_FIFO permits reads while waiting for data, and the next
            // rebuild request already resets/restarts that FIFO in S_ACK.
            if(cover_fallback)begin
                cover_cancel<=1;cover_abort_pipe<=4'hf;
                cover_write<=0;cover_commit<=0;cover_loaded<=0;started<=1;
                load_busy<=0;source_done_seen<=0;memory_done_seen<=0;source_busy_seen<=0;
                render_error<=0;render_watchdog<=0;
                disp_buf_idx<=0;pending_image_idx<=0;
                commit_toggle<=~commit_toggle;commit_pending<=1;
                next_req_pending<=0;auto_cnt<=0;auto_elapsed<=0;audio_auto_pending<=0;
                commit_manual<=0;intro_armed<=0;
            end
        end
    end
end

bmp_read bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),
    .scan_found_duration    (scan_found_duration),
    .scan_found_scale       (scan_found_scale),
    .scan_found_scene       (scan_found_scene),
    .cover_found            (reader_cover_found),
    .cover_error            (reader_cover_error),
    .cover_cancel           (cover_cancel),
    .subtitle_wr_en         (subtitle_wr_en),
    .subtitle_wr_addr       (subtitle_wr_addr),
    .subtitle_wr_data       (subtitle_wr_data),
    .subtitle_len0          (subtitle_len0),
    .subtitle_len1          (subtitle_len1),
    .subtitle_len2          (subtitle_len2),
    .subtitle_len3          (subtitle_len3),
    .font_scene_request     (commit_pending?pending_scene:current_scene),
    .font_index_request     (commit_pending?pending_image_idx:img_idx),
    .font_cache_idle(font_cache_idle),
    .font_quiet_ack(font_quiet_ack),.font_quiet_request(font_quiet_request),
    .font_wr_en(font_wr_en),.font_wr_addr(font_wr_addr),.font_wr_data(font_wr_data),
    .font_ready(font_ready),.font_format24(font_format24),.font_loaded_scene(font_loaded_scene),.font_loaded_index(font_loaded_index),
    .packed_subtitles(packed_subtitles),
    .audio_stream_enable    (audio_stream_enable),
    .audio_fifo_afull       (audio_fifo_afull),
    .audio_scene            (current_scene),
    .audio_restart          (audio_switch_hold),
    .audio_reset_busy       (reader_audio_reset_busy),
    .audio_sample_total     (audio_sample_total),
    .audio_file_present     (audio_file_present),
    .audio_format_error     (audio_format_error),
    .audio_pcm_wr           (audio_pcm_wr),
    .audio_pcm_word         (audio_pcm_word),

    .load_start             (load_start_pulse),
    .load_sector            (load_sector),

    .sd_init_done           (sd_init_done),
    .state_code             (reader_state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .source_width           (source_width),
    .source_height          (source_height),
    .image_start            (image_start),
    .write_req              (reader_write_req),
    .write_req_ack          (writer_ack_seen && scale_input_start_ready),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

localparam [31:0] RENDER_STALL_CYCLES = CLK_FREQ_HZ * 2;
wire cover_fallback=cover_write && (reader_cover_error || scale_overrun ||
                    (load_busy && render_watchdog>=RENDER_STALL_CYCLES-1));

bmp_mode_scaler u_bmp_scaler(
    .clk(clk),.rst(render_rst),.image_start(image_start),
    .output_start(scale_output_start),.output_pause(write_fifo_near_full),
    .mode(cover_write?2'd2:effective_scale(load_idx)),
    .source_width(source_width),.source_height(source_height),
    .pixel_valid(bmp_data_wr_en),.pixel_rgb(bmp_data),
    .config_ready(scale_config_ready),.input_start_ready(scale_input_start_ready),
    .output_valid(scaled_valid),.output_rgb(scaled_data),
    .output_done(scaled_done),.input_overrun(scale_overrun)
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (8'd0),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
