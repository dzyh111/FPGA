`timescale 1ns/1ps
module tb_gallery_auto;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,lock=0,loop_toggle=0,ack=0,play=1;
 reg done=0;reg [1:0] done_index=0;reg restart_ack=0;
 wire commit,manual_commit,display_valid,audio_reset,restart;
 wire [1:0] image;wire [2:0] scene;
 sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut(.clk(clk),.rst(rst),
  .key_next(1'b1),.key_auto(1'b1),.control_lock(lock),
  .audio_play_enable(play),.audio_fifo_afull(1'b0),.audio_loop_toggle(loop_toggle),
  .audio_fifo_reset(audio_reset),.current_scene(scene),.scale_override(2'd0),
  .blank_ack(1'b0),.bmp_width(16'd1024),.bmp_height(16'd600),
  .display_valid(display_valid),.write_finish_toggle(1'b0),
  .commit_toggle(commit),.commit_manual(manual_commit),.commit_ack(ack),.current_image(image),
  .intro_done(done),.intro_done_index(done_index),.intro_restart(restart),.intro_restart_ack(restart_ack),
  .font_cache_idle(1'b1),.font_quiet_ack(1'b0),
  .write_req_ack(1'b0),.write_fifo_near_full(1'b0),.SD_MISO(1'b1));
 integer checks=0;
 task tick;begin @(negedge clk);end endtask
 task wait_cycles(input integer count);integer i;begin for(i=0;i<count;i=i+1)tick;end endtask
 task auto_key;begin force dut.key_auto_press=1'b1;tick;release dut.key_auto_press;tick;end endtask
 task finish_commit(input [1:0] next_image);
 begin
  wait_cycles(5);ack=commit;wait_cycles(6);
  if(image!==next_image || dut.commit_pending || audio_reset)$fatal(1,"gallery commit acknowledgement image=%0d wanted=%0d",image,next_image);
 end endtask
 task stable(input [1:0] expected_image,input expected_toggle,input integer cycles);
 integer i;begin
  for(i=0;i<cycles;i=i+1)begin tick;
   if(image!==expected_image || commit!==expected_toggle)$fatal(1,"unexpected gallery advance image=%0d commit=%b",image,commit);
  end checks=checks+1;
 end endtask
 initial begin
  // Reader/filesystem and image caching are covered independently. Drive only
  // their stable status here so this suite isolates the playback controller.
  force dut.sd_init_done=1'b1;force dut.scan_done=1'b1;
  force dut.bmp_ready=1'b1;force dut.scan_found_valid=1'b0;
  force dut.reader_audio_reset_busy=1'b0;
  force dut.audio_file_present=1'b1;force dut.audio_format_error=1'b0;
  force dut.subtitle_len0=8'd84;force dut.subtitle_len1=8'd85;
  force dut.subtitle_len2=8'd80;force dut.subtitle_len3=8'd86;
  wait_cycles(5);rst=0;
  dut.scan_kicked=1;dut.img_found_count=4;dut.loaded_count=4;
  dut.display_valid=1;dut.first_image_committed=1;dut.img_idx=0;
  dut.scene0=1;dut.scene1=2;dut.scene2=3;dut.scene3=4;
  dut.duration0=1;dut.duration1=1;dut.duration2=1;dut.duration3=1;
  dut.auto_play_en=1;
  stable(0,0,2100); // Two elapsed script seconds must not truncate narration.
  loop_toggle=1;stable(0,0,10);
  if(dut.audio_auto_pending)$fatal(1,"WAV loop overrode nonempty introduction");
  done_index=3;done=1;stable(0,0,10);
  if(dut.audio_auto_pending)$fatal(1,"wrong-index completion accepted");
  done=0;done_index=0;wait_cycles(8);
  lock=1;done=1;stable(0,0,10);
  if(!dut.audio_auto_pending)$fatal(1,"completion lost while menu locked");
  play=0;lock=0;stable(0,0,10);
  play=1;wait(commit==1);tick;
  if(manual_commit || !audio_reset)$fatal(1,"AUTO should request fade and reset chapter audio");
  stable(0,1,12);finish_commit(1);
  stable(1,1,12); // Old page0 completion is still high across acknowledgement.
  done_index=1;stable(1,1,12);
  if(dut.intro_armed)$fatal(1,"high completion rearmed without a cleared level");
  done=0;wait_cycles(8);
  if(!dut.intro_armed)$fatal(1,"cleared current scene did not arm");
  // A KEY2 press concurrent with an already pending AUTO event wins the
  // transition classification. Both still advance by exactly one chapter.
  lock=1;done=1;done_index=1;wait_cycles(8);
  if(!dut.audio_auto_pending)$fatal(1,"second completion was not retained");
  lock=0;force dut.key_next_press=1'b1;tick;release dut.key_next_press;
  if(commit!==0 || !manual_commit || !dut.commit_pending)$fatal(1,"KEY2 lost priority against AUTO");
  finish_commit(2);stable(2,0,12);
  // Disable AUTO, then start it while the old reading finishes before the
  // video frame has acknowledged restart. That stale pass must be discarded.
  auto_key;if(dut.auto_play_en)$fatal(1,"AUTO disable key");
  done=0;done_index=2;wait_cycles(8);
  auto_key;
  if(!dut.auto_play_en || restart===restart_ack)$fatal(1,"AUTO enable did not request a new introduction epoch");
  done=1;stable(2,0,15);
  if(dut.audio_auto_pending || dut.intro_armed)$fatal(1,"stale completion accepted before restart acknowledgement");
  done=0;restart_ack=restart;wait_cycles(8);
  if(!dut.intro_armed)$fatal(1,"acknowledged cleared epoch did not arm");
  // Completion may be retained through SW3 pause; no commit occurs until play.
  play=0;done=1;stable(2,0,12);
  if(!dut.audio_auto_pending)$fatal(1,"paused completed epoch was lost");
  play=1;wait(commit==1);tick;
  if(manual_commit)$fatal(1,"resumed AUTO classified as manual");
  finish_commit(3);stable(3,1,10);
  // With no introduction, retain the old consumed-audio AUTO clock.
  done=0;force dut.subtitle_len3=8'd0;wait_cycles(8);
  loop_toggle=0;wait(commit==0);tick;
  if(manual_commit)$fatal(1,"legacy audio fallback transition classification");
  finish_commit(0);
  // A mixed playlist may contain an ordinary image while the optional pack
  // remains present for the four instruments. Its unused TEXT length must
  // not make AUTO wait for an instrument intro that cannot be displayed.
  dut.scene0=0;force dut.packed_subtitles=1'b1;force dut.subtitle_len0=8'd80;
  done=1;done_index=0;
  stable(0,0,500);
  wait(commit==1);tick;
  if(manual_commit || dut.pending_image_idx!==1 || dut.auto_cnt!==0)
   $fatal(1,"mixed ordinary-image playlist did not retain script-timer AUTO");
  finish_commit(1);
  $display("PASS gallery AUTO: %0d stable-state checks, ignores WAV/walltimer during narration, menu/pause retention, scene-tag/low rearm, restart epoch handshake and stale-event rejection, KEY2 priority, legacy audio fallback, mixed noninstrument image script fallback",checks);
  $finish;
 end
 initial begin #1000000;$fatal(1,"gallery AUTO timeout");end
endmodule
