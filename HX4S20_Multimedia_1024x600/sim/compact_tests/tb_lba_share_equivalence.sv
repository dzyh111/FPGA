`timescale 1ns/1ps
module tb_lba_share_equivalence;
 reg clk=0,rst=1,load_start=0;
 reg [31:0] load_sector=0;
 reg [2:0] audio_scene=0;
wire [304:0] reference_outputs,dut_outputs;
bmp_read_reference reference(.clk(clk),.rst(rst),.scan_start(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0),.scan_target_count(3'd4),.cover_cancel(1'b0),.font_scene_request(3'd0),.font_index_request(2'd0),.font_cache_idle(1'b1),.font_quiet_ack(1'b0),.audio_stream_enable(1'b1),.audio_fifo_afull(1'b0),.audio_scene(audio_scene),.audio_restart(1'b0),.load_start(load_start),.load_sector(load_sector),.sd_init_done(1'b1),.bmp_width(16'd1024),.bmp_height(16'd600),.write_req_ack(1'b1),.sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0),.ready(reference_outputs[0 +: 1]),.scan_done(reference_outputs[1 +: 1]),.scan_found_valid(reference_outputs[2 +: 1]),.scan_found_sector(reference_outputs[3 +: 32]),.scan_found_total(reference_outputs[35 +: 3]),.scan_found_duration(reference_outputs[38 +: 8]),.scan_found_scale(reference_outputs[46 +: 2]),.scan_found_scene(reference_outputs[48 +: 3]),.cover_found(reference_outputs[51 +: 1]),.cover_error(reference_outputs[52 +: 1]),.subtitle_wr_en(reference_outputs[53 +: 1]),.subtitle_wr_addr(reference_outputs[54 +: 9]),.subtitle_wr_data(reference_outputs[63 +: 8]),.subtitle_len0(reference_outputs[71 +: 8]),.subtitle_len1(reference_outputs[79 +: 8]),.subtitle_len2(reference_outputs[87 +: 8]),.subtitle_len3(reference_outputs[95 +: 8]),.font_quiet_request(reference_outputs[103 +: 1]),.font_wr_en(reference_outputs[104 +: 1]),.font_wr_addr(reference_outputs[105 +: 10]),.font_wr_data(reference_outputs[115 +: 18]),.font_ready(reference_outputs[133 +: 1]),.font_format24(reference_outputs[134 +: 1]),.font_loaded_scene(reference_outputs[135 +: 3]),.font_loaded_index(reference_outputs[138 +: 2]),.packed_subtitles(reference_outputs[140 +: 1]),.audio_reset_busy(reference_outputs[141 +: 1]),.audio_sample_total(reference_outputs[142 +: 32]),.audio_file_present(reference_outputs[174 +: 1]),.audio_format_error(reference_outputs[175 +: 1]),.audio_pcm_wr(reference_outputs[176 +: 1]),.audio_pcm_word(reference_outputs[177 +: 32]),.state_code(reference_outputs[209 +: 4]),.source_width(reference_outputs[213 +: 16]),.source_height(reference_outputs[229 +: 16]),.image_start(reference_outputs[245 +: 1]),.write_req(reference_outputs[246 +: 1]),.sd_sec_read(reference_outputs[247 +: 1]),.sd_sec_read_addr(reference_outputs[248 +: 32]),.bmp_data_wr_en(reference_outputs[280 +: 1]),.bmp_data(reference_outputs[281 +: 24]));
bmp_read dut(.clk(clk),.rst(rst),.scan_start(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0),.scan_target_count(3'd4),.cover_cancel(1'b0),.font_scene_request(3'd0),.font_index_request(2'd0),.font_cache_idle(1'b1),.font_quiet_ack(1'b0),.audio_stream_enable(1'b1),.audio_fifo_afull(1'b0),.audio_scene(audio_scene),.audio_restart(1'b0),.load_start(load_start),.load_sector(load_sector),.sd_init_done(1'b1),.bmp_width(16'd1024),.bmp_height(16'd600),.write_req_ack(1'b1),.sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0),.ready(dut_outputs[0 +: 1]),.scan_done(dut_outputs[1 +: 1]),.scan_found_valid(dut_outputs[2 +: 1]),.scan_found_sector(dut_outputs[3 +: 32]),.scan_found_total(dut_outputs[35 +: 3]),.scan_found_duration(dut_outputs[38 +: 8]),.scan_found_scale(dut_outputs[46 +: 2]),.scan_found_scene(dut_outputs[48 +: 3]),.cover_found(dut_outputs[51 +: 1]),.cover_error(dut_outputs[52 +: 1]),.subtitle_wr_en(dut_outputs[53 +: 1]),.subtitle_wr_addr(dut_outputs[54 +: 9]),.subtitle_wr_data(dut_outputs[63 +: 8]),.subtitle_len0(dut_outputs[71 +: 8]),.subtitle_len1(dut_outputs[79 +: 8]),.subtitle_len2(dut_outputs[87 +: 8]),.subtitle_len3(dut_outputs[95 +: 8]),.font_quiet_request(dut_outputs[103 +: 1]),.font_wr_en(dut_outputs[104 +: 1]),.font_wr_addr(dut_outputs[105 +: 10]),.font_wr_data(dut_outputs[115 +: 18]),.font_ready(dut_outputs[133 +: 1]),.font_format24(dut_outputs[134 +: 1]),.font_loaded_scene(dut_outputs[135 +: 3]),.font_loaded_index(dut_outputs[138 +: 2]),.packed_subtitles(dut_outputs[140 +: 1]),.audio_reset_busy(dut_outputs[141 +: 1]),.audio_sample_total(dut_outputs[142 +: 32]),.audio_file_present(dut_outputs[174 +: 1]),.audio_format_error(dut_outputs[175 +: 1]),.audio_pcm_wr(dut_outputs[176 +: 1]),.audio_pcm_word(dut_outputs[177 +: 32]),.state_code(dut_outputs[209 +: 4]),.source_width(dut_outputs[213 +: 16]),.source_height(dut_outputs[229 +: 16]),.image_start(dut_outputs[245 +: 1]),.write_req(dut_outputs[246 +: 1]),.sd_sec_read(dut_outputs[247 +: 1]),.sd_sec_read_addr(dut_outputs[248 +: 32]),.bmp_data_wr_en(dut_outputs[280 +: 1]),.bmp_data(dut_outputs[281 +: 24]));

 integer state_number,shift_number,trial,j,checks=0,requests=0;
 integer requests_in_state[0:36];
 reg [31:0] value,wanted_cluster,wanted_lba,wanted_next;
 reg [31:0] edge_values[0:7];
 reg [31:0] rng=32'hc0ffee31;
 task random32;
  begin rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);value=rng;end
 endtask
 task populate;
  begin
   reference.state=state_number;dut.state=state_number;
   reference.cluster_shift=shift_number;dut.cluster_shift=shift_number;
   random32;reference.data_base=value;dut.data_base=value;
   random32;reference.cluster=value;dut.cluster=value;
   random32;
   if(trial[0])value=(value&32'h0ffffffc)+32'd2;
   reference.next_cluster=value;dut.next_cluster=value;
   random32;reference.audio_cluster=value;dut.audio_cluster=value;
   random32;reference.playlist_cluster=value;dut.playlist_cluster=value;
   random32;reference.text_cluster=value;dut.text_cluster=value;
   random32;reference.pack_cluster=value;dut.pack_cluster=value;
   random32;reference.cover_cluster=value;dut.cover_cluster=value;
   for(j=0;j<4;j=j+1)begin random32;reference.file_cluster[j]=value;dut.file_cluster[j]=value;end
   for(j=0;j<5;j=j+1)begin random32;reference.scene_audio_cluster[j]=value;dut.scene_audio_cluster[j]=value;end
   // Exercise wrap, underflow, every shift code and high bits as well as random inputs.
   if(trial<8)begin
    reference.data_base=edge_values[trial];dut.data_base=edge_values[trial];
    reference.cluster=edge_values[(trial+1)%8];dut.cluster=edge_values[(trial+1)%8];
    reference.next_cluster=edge_values[(trial+2)%8];dut.next_cluster=edge_values[(trial+2)%8];
   end
   load_start=trial[0];load_sector=trial%8;audio_scene=(trial>>1)%8;
   reference.cover_found=trial[1];dut.cover_found=trial[1];
   reference.scan_found_total=4;dut.scan_found_total=4;
   reference.scan_done=1;dut.scan_done=1;
   reference.audio_found=5'b11111;dut.audio_found=5'b11111;
   reference.audio_abort_pending=0;dut.audio_abort_pending=0;
   reference.audio_reset_busy=0;dut.audio_reset_busy=0;
   reference.playlist_found=1;dut.playlist_found=1;
   reference.playlist_count=4;dut.playlist_count=4;
   reference.validate_index=trial%4;dut.validate_index=trial%4;
   reference.text_found=1;dut.text_found=1;
   reference.pack_found=1;dut.pack_found=1;
   reference.pack_initialized=0;dut.pack_initialized=0;
   reference.font_idle_sync=2'b11;dut.font_idle_sync=2'b11;
   reference.font_quiet_sync=0;dut.font_quiet_sync=0;
   reference.font_quiet_request=0;dut.font_quiet_request=0;
   reference.audio_file_pos=0;dut.audio_file_pos=0;
   reference.audio_data_remaining=0;dut.audio_data_remaining=0;
   reference.cluster_sector=trial;dut.cluster_sector=trial;
   reference.spc=128;dut.spc=128;
   reference.fat_size=1;dut.fat_size=1;
   reference.partition=reference.data_base;dut.partition=dut.data_base;
   reference.total_sectors=1;dut.total_sectors=1;
   reference.max_cluster=32'h0fffffff;dut.max_cluster=32'h0fffffff;
   // Force the legacy WAV header acceptance branch, without stubbing its logic.
   if(state_number==27)begin
    reference.h[0]="R";dut.h[0]="R";reference.h[1]="I";dut.h[1]="I";
    reference.h[2]="F";dut.h[2]="F";reference.h[3]="F";dut.h[3]="F";
    reference.h[8]="W";dut.h[8]="W";reference.h[9]="A";dut.h[9]="A";
    reference.h[10]="V";dut.h[10]="V";reference.h[11]="E";dut.h[11]="E";
    reference.h[12]="f";dut.h[12]="f";reference.h[13]="m";dut.h[13]="m";
    reference.h[14]="t";dut.h[14]="t";reference.h[15]=" ";dut.h[15]=" ";
    reference.h[20]=1;dut.h[20]=1;reference.h[22]=2;dut.h[22]=2;
    reference.h[24]=8'h80;dut.h[24]=8'h80;reference.h[25]=8'hbb;dut.h[25]=8'hbb;
    reference.h[32]=4;dut.h[32]=4;reference.h[34]=16;dut.h[34]=16;
    reference.wav_tag_found=1;dut.wav_tag_found=1;
    reference.wav_data_size=16;dut.wav_data_size=16;
    reference.audio_data_offset=44;dut.audio_data_offset=44;
    reference.audio_file_size=60;dut.audio_file_size=60;
   end
  end
 endtask
 initial begin
  edge_values[0]=0;edge_values[1]=1;edge_values[2]=2;edge_values[3]=32'h7fffffff;
  edge_values[4]=32'h80000000;edge_values[5]=32'hfffffffe;edge_values[6]=32'hffffffff;edge_values[7]=32'h0fffffff;
  for(j=0;j<37;j=j+1)requests_in_state[j]=0;
  for(state_number=0;state_number<37;state_number=state_number+1)
   for(shift_number=0;shift_number<16;shift_number=shift_number+1)
    for(trial=0;trial<64;trial=trial+1)begin
     clk=0;rst=1;#1;clk=1;#1;clk=0;rst=0;
     populate;#1;
     // Original expressions select these sources at the individual read_sector call sites.
     case(state_number)
      0:wanted_cluster=load_start?reference.selected_image_cluster:reference.selected_audio_cluster;
      31:wanted_cluster=load_start?reference.selected_image_cluster:reference.cluster;
      8,13,22,30,35:wanted_cluster=reference.next_cluster;
      15:wanted_cluster=reference.playlist_cluster;
      24:wanted_cluster=reference.file_cluster[reference.validate_index];
      26:wanted_cluster=reference.text_cluster;
      19,36:wanted_cluster=reference.pack_cluster;
      27,28:wanted_cluster=reference.audio_cluster;
      default:wanted_cluster=reference.cluster;
     endcase
     wanted_lba=reference.data_base+((wanted_cluster-2)<<reference.cluster_shift);
     wanted_next=wanted_lba+reference.cluster_sector+1;
     if(dut.request_cluster!==wanted_cluster || dut.cluster_lba!==wanted_lba || dut.next_sector_lba!==wanted_next)
      $fatal(1,"raw LBA mismatch state=%0d shift=%0d trial=%0d",state_number,shift_number,trial);
     clk=1;#1;
     if(reference_outputs!==dut_outputs || reference.state!==dut.state || reference.after_rx!==dut.after_rx)
      $fatal(1,"cycle outputs/state mismatch state=%0d shift=%0d trial=%0d",state_number,shift_number,trial);
     if(dut.state==1 && state_number!=1)begin requests=requests+1;requests_in_state[state_number]=requests_in_state[state_number]+1;end
     checks=checks+1;clk=0;
    end
  // These 22 states cover every data/fat-sector call site plus their guarded alternatives.
  for(j=0;j<37;j=j+1)if(j==0 || j==5 || j==7 || j==8 || j==10 || j==12 || j==13 || j==15 || j==19 ||
   j==21 || j==22 || j==24 || j==26 || j==27 || j==28 || j==29 || j==30 || j==31 || j==34 || j==35 || j==36)
    if(requests_in_state[j]==0)$fatal(1,"uncovered request state=%0d",j);
  $display("PASS LBA sharing equivalence: %0d state/shift/address vectors; %0d actual one-cycle requests; all outputs, state and continuation equal",checks,requests);
  for(j=0;j<37;j=j+1)if(requests_in_state[j]!=0)$display("REQUEST_STATE %0d %0d",j,requests_in_state[j]);
  $finish;
 end
endmodule
