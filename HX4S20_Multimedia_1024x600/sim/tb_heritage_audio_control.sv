`timescale 1ns/1ps
module tb_heritage_audio_control;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,lock=0,loop_toggle=0,ack=0;
 wire commit,display_valid,audio_reset;
 wire [1:0] image;
 wire [2:0] scene;
 sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut(.clk(clk),.rst(rst),
  .key_next(1'b1),.key_auto(1'b1),.control_lock(lock),
  .audio_play_enable(1'b1),.audio_fifo_afull(1'b0),.audio_loop_toggle(loop_toggle),
  .audio_fifo_reset(audio_reset),.current_scene(scene),.scale_override(2'd0),
  .blank_ack(1'b0),.bmp_width(16'd1024),.bmp_height(16'd600),
  .display_valid(display_valid),.write_finish_toggle(1'b0),
  .commit_toggle(commit),.commit_ack(ack),.current_image(image),
  .write_req_ack(1'b0),.write_fifo_near_full(1'b0),.SD_MISO(1'b1));
 initial begin
  // Isolate the playback controller from the separately tested FAT/SD reader.
  force dut.sd_init_done=1'b1;force dut.scan_done=1'b1;
  force dut.bmp_ready=1'b1;force dut.scan_found_valid=1'b0;
  force dut.reader_audio_reset_busy=1'b0;
  force dut.audio_file_present=1'b1;force dut.audio_format_error=1'b0;
  repeat(5)@(negedge clk);rst=0;
  dut.scan_kicked=1;dut.img_found_count=4;dut.loaded_count=4;
  dut.display_valid=1;dut.first_image_committed=1;dut.img_idx=0;
  dut.scene0=1;dut.scene1=2;dut.scene2=3;dut.scene3=4;
  dut.duration0=1;dut.duration1=1;dut.duration2=1;dut.duration3=1;
  dut.auto_play_en=1;
  repeat(2100)@(negedge clk);
  if(commit || image!=0)$fatal(1,"heritage advanced on wall clock");
  lock=1;loop_toggle=1;repeat(8)@(negedge clk);
  if(commit || !dut.audio_auto_pending)$fatal(1,"menu completion was not retained auto=%b heritage=%b clock=%b display=%b sync=%b seen=%b pending=%b",dut.auto_play_en,dut.heritage_mode,dut.heritage_audio_clock,display_valid,dut.audio_loop_sync,dut.audio_loop_seen,dut.commit_pending);
  lock=0;wait(commit);
  @(negedge clk);
  if(!audio_reset || image!=0 || scene!=1)$fatal(1,"commit reset/old scene");
  repeat(20)@(negedge clk);
  if(!audio_reset || image!=0)$fatal(1,"audio started before video acknowledgement");
  ack=1;repeat(5)@(negedge clk);
  if(audio_reset || image!=1 || scene!=2)$fatal(1,"commit did not release new scene");
  repeat(1100)@(negedge clk);
  if(commit!=1 || image!=1)$fatal(1,"new scene used independent seconds");
  force dut.audio_file_present=1'b0;
  wait(commit==0); // Missing audio falls back to the existing playlist duration.
  @(negedge clk);
  if(image!=1 || !audio_reset)$fatal(1,"fallback switch handshake");
  dut.scene2=0;dut.scene3=0;
  ack=0;repeat(5)@(negedge clk);
  if(image!=2 || scene!=0 || audio_reset)$fatal(1,"legacy entry");
  force dut.audio_file_present=1'b1;
  dut.auto_play_en=0;dut.next_req_pending=1;
  wait(commit==1);@(negedge clk);
  if(audio_reset || !dut.audio_stream_enable || image!=2)
    $fatal(1,"ordinary image switch interrupted 111.WAV");
  repeat(20)begin @(negedge clk);if(audio_reset)$fatal(1,"legacy commit asserted audio reset");end
  ack=1;repeat(5)@(negedge clk);
  if(image!=3 || scene!=0 || audio_reset || !dut.audio_stream_enable)
    $fatal(1,"legacy background audio did not remain continuous");
  $display("PASS heritage controller: consumed-audio AUTO, menu event latch, commit reset, missing-WAV fallback, continuous legacy 111.WAV");
  $finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
