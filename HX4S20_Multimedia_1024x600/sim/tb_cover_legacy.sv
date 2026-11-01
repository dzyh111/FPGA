`timescale 1ns/1ps
// New cover metadata must be inert in existing instantiations which rely on
// ENABLE_COVER's default zero. In particular unconnected new inputs are safe.
module tb_cover_legacy;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,token=0,ctrl_ack=0;reg [1:0] index=1;
 wire ack,req,read_cover,started,cover_write,cover_commit,ctrl_commit,audio_reset;
 wire [1:0] selected,image;
 video_scan #(.H_ACTIVE(16),.H_FP(4),.H_SYNC(2),.H_BP(4),
  .V_ACTIVE(4),.V_FP(1),.V_SYNC(1),.V_BP(1),.IMG_W(16),.IMG_H(4)) scan(
  .clk(clk),.rst(rst),.commit_toggle(token),.commit_index(index),
  .commit_cover(1'b1),.read_cover(read_cover),.blank_toggle(1'b0),
  .commit_ack(ack),.read_index(selected),.read_req(req),.read_req_ack(req));
 sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut(.clk(clk),.rst(rst),
  .key_next(1'b1),.key_auto(1'b1),.control_lock(1'b0),
  .cover_write(cover_write),.cover_commit(cover_commit),.exhibition_started(started),
  .audio_play_enable(1'b1),.audio_fifo_afull(1'b0),.audio_loop_toggle(1'b0),
  .audio_fifo_reset(audio_reset),.scale_override(2'd0),.blank_ack(1'b0),
  .bmp_width(16'd1024),.bmp_height(16'd600),.write_finish_toggle(1'b0),
  .commit_toggle(ctrl_commit),.commit_ack(ctrl_ack),.current_image(image),
  .write_req_ack(1'b0),.write_fifo_near_full(1'b0),.SD_MISO(1'b1));
 initial begin
  force dut.sd_init_done=1;force dut.scan_done=1;force dut.bmp_ready=1;
  force dut.scan_found_valid=0;force dut.reader_cover_found=1;
  force dut.reader_cover_error=1;force dut.reader_audio_reset_busy=0;
  force dut.audio_file_present=1;force dut.audio_format_error=0;
  repeat(5)@(negedge clk);rst=0;
  dut.scan_kicked=1;dut.img_found_count=4;dut.loaded_count=4;
  dut.display_valid=1;dut.first_image_committed=1;
  repeat(5)@(negedge clk);
  if(!started || cover_commit || cover_write || audio_reset || !dut.audio_stream_enable)
   $fatal(1,"default legacy controller unexpectedly entered cover mode");
  token=1;
  @(negedge clk);force dut.key_next_press=1;
  @(negedge clk);release dut.key_next_press;
  wait(dut.commit_pending);ctrl_ack=ctrl_commit;
  wait(!dut.commit_pending);@(negedge clk);
  if(image!=1 || cover_commit || cover_write)$fatal(1,"legacy first KEY2 changed");
  wait(ack==token);@(negedge clk);
  if(read_cover || selected!=1)$fatal(1,"default video scan did not ignore cover metadata");
  $display("PASS cover legacy: ENABLE_COVER defaults off, cover metadata/errors ignored, original next-image and continuous audio behavior preserved");
  $finish;
 end
 initial begin #1000000;$fatal(1,"cover legacy timeout");end
endmodule
