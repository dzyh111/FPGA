`timescale 1ns/1ps
// The reader and scaler have independent tests. Here their completion flags are
// isolated so both source-before-memory and memory-before-source are exercised.
module tb_cover_control;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,ack=0,writer_done=0,reader_ready=1,reader_cover=1,reader_error=0;
 reg reader_done=1,valid_entry=0,scaler_overrun=0;
 reg [31:0] entry_handle=0;
 wire commit,display_valid,audio_reset,started,cover_commit,cover_write,cover_abort,auto_enabled;
 wire [1:0] image,write_index;wire [2:0] progress;wire [3:0] state;
 sd_card_bmp #(.CLK_FREQ_HZ(1000),.ENABLE_COVER(1)) dut(.clk(clk),.rst(rst),
  .key_next(1'b1),.key_auto(1'b1),.control_lock(1'b0),
  .cover_commit(cover_commit),.cover_write(cover_write),.cover_abort(cover_abort),
  .exhibition_started(started),.audio_play_enable(1'b1),.audio_fifo_afull(1'b0),
  .audio_loop_toggle(1'b0),.audio_fifo_reset(audio_reset),.scale_override(2'd0),
  .blank_ack(1'b0),.bmp_width(16'd1024),.bmp_height(16'd600),
  .display_valid(display_valid),.write_finish_toggle(writer_done),
  .commit_toggle(commit),.commit_ack(ack),.current_image(image),
  .auto_enabled(auto_enabled),.write_buf_idx(write_index),.rebuild_progress(progress),
  .state_code(state),.write_req_ack(1'b0),.write_fifo_near_full(1'b0),.SD_MISO(1'b1));
 integer scenario,i,commit_count=0;reg old_commit=0;
 reg check_cover_fault=0;
 integer fault_request_checks=0;
 // A cover failure blocks payload immediately. The request is released by
 // the registered abort on the next source clock, avoiding a fault-to-request
 // combinational path while preserving cancellation before another clock.
 always @(posedge dut.cover_fallback)begin
  if(!rst && check_cover_fault)begin
   #1;
   if(dut.write_en!==0 || dut.write_req!==1 || cover_abort!==0 || cover_commit || dut.cover_loaded)
    $fatal(1,"cover fault did not gate payload while holding request until registered abort scenario=%0d",scenario);
   @(posedge clk);#1;
   if(dut.write_en!==0 || dut.write_req!==0 || cover_abort!==1 || cover_commit || dut.cover_loaded)
    $fatal(1,"cover fault request not cancelled on next source clock scenario=%0d",scenario);
   fault_request_checks=fault_request_checks+1;
  end
 end
 always @(posedge clk)begin
  #1;
  if(rst)begin old_commit=0;commit_count=0;end
  else if(commit!=old_commit)begin commit_count=commit_count+1;old_commit=commit;end
 end
 task pulse_next;begin
  @(negedge clk);force dut.key_next_press=1;
  @(negedge clk);release dut.key_next_press;
 end endtask
 task pulse_auto;begin
  @(negedge clk);force dut.key_auto_press=1;
  @(negedge clk);release dut.key_auto_press;
 end endtask
 task reset_controller(input reg has_cover,input integer count);begin
  rst=1;ack=0;writer_done=0;reader_ready=1;reader_done=0;check_cover_fault=0;
  reader_cover=has_cover;reader_error=0;valid_entry=0;scaler_overrun=0;
  repeat(5)@(negedge clk);rst=0;
  // Skip only card transport/scan launch, not the controller's entry capture.
  dut.scan_kicked=1;
  for(i=0;i<count;i=i+1)begin
   entry_handle=i;valid_entry=1;@(negedge clk);valid_entry=0;@(negedge clk);
  end
  reader_done=1;
 end endtask
 task finish_frame(input integer selected,input reg memory_first);
  reg old_commit_value;begin
   wait(dut.load_start_pulse);@(negedge clk);
   if(dut.load_sector!==selected || cover_write!==(selected==4) ||
      (selected<4 && write_index!==selected[1:0]))
    $fatal(1,"wrong cache destination handle=%0d cover=%b",dut.load_sector,cover_write);
   old_commit_value=commit;reader_ready=0;
   repeat(5)@(negedge clk);
   if(memory_first)begin
    writer_done=~writer_done;repeat(7)@(negedge clk);
    if(commit!=old_commit_value || !dut.load_busy)$fatal(1,"memory-only completion committed a frame");
    reader_ready=1;
   end else begin
    reader_ready=1;repeat(7)@(negedge clk);
    if(commit!=old_commit_value || !dut.load_busy)$fatal(1,"source-only completion committed a frame");
    writer_done=~writer_done;
   end
   wait(!dut.load_busy);@(negedge clk);
   if(selected==4)begin
    if(progress!=4 || !dut.cover_loaded || !cover_commit || started)
     $fatal(1,"cover must use fifth buffer without entering playlist/count");
   end else if(progress!=selected+1)$fatal(1,"ordinary cache progress changed");
  end
 endtask
 task acknowledge_commit;begin
  wait(dut.commit_pending);repeat(12)@(negedge clk);
  if(display_valid)$fatal(1,"display enabled before first video ACK");
  ack=commit;wait(display_valid);repeat(5)@(negedge clk);
 end endtask
 task check_first_entry;begin
  if(started || !cover_commit || !audio_reset || auto_enabled || image!=0)
   $fatal(1,"cover idle is not silent/manual");
  pulse_auto;repeat(30)@(negedge clk);
  if(auto_enabled || started || !audio_reset || dut.audio_stream_enable)
   $fatal(1,"AUTO/audio allowed on cover");
  pulse_next;wait(dut.commit_pending);@(negedge clk);
  if(!started || cover_commit || !audio_reset || image!=0 || dut.pending_image_idx!=0)
   $fatal(1,"first KEY2 skipped image zero or started audio before video ACK");
  repeat(12)@(negedge clk);ack=commit;wait(!dut.commit_pending);
  repeat(15)@(negedge clk);
  if(image!=0 || commit_count!=2 || audio_reset || !dut.audio_stream_enable || auto_enabled)
   $fatal(1,"first KEY2 caused extra advance or failed to release audio");
  pulse_next;wait(dut.commit_pending);ack=commit;
  wait(!dut.commit_pending);repeat(5)@(negedge clk);
  if(image!=1 || cover_commit)$fatal(1,"later KEY2 lost ordinary next-image function");
 end endtask
 initial begin
  force dut.sd_init_done=1'b1;
  force dut.scan_done=reader_done;force dut.bmp_ready=reader_ready;
  force dut.scan_found_valid=valid_entry;force dut.scan_found_sector=entry_handle;
  force dut.scan_found_duration=8'd16;force dut.scan_found_scale=2'd2;
  force dut.scan_found_scene=3'd1;
  force dut.reader_cover_found=reader_cover;force dut.reader_cover_error=reader_error;
  force dut.reader_audio_reset_busy=1'b0;
  force dut.audio_file_present=1'b1;force dut.audio_format_error=1'b0;
  force dut.reader_state_code=4'd6;
  force dut.scale_overrun=scaler_overrun;
  for(scenario=0;scenario<9;scenario=scenario+1)begin
   reset_controller(scenario!=1,scenario==4?0:4);
   if(scenario==4)begin
    force dut.reader_state_code=4'd14;
    repeat(60)@(negedge clk);
    if(state!=14 || display_valid || commit_count || progress || started || !audio_reset)
     $fatal(1,"cover masked no-legal-image error");
    force dut.reader_state_code=4'd6;
   end else begin
    finish_frame(0,1);finish_frame(1,0);finish_frame(2,1);finish_frame(3,0);
    if(scenario==0 || scenario==5)begin
     finish_frame(4,scenario==0);acknowledge_commit;check_first_entry;
    end else if(scenario==1)begin
     acknowledge_commit;
     if(!started || cover_commit || image!=0 || !dut.audio_stream_enable || progress!=4 || commit_count!=1)
      $fatal(1,"missing cover did not preserve old startup");
    end else begin
     wait(dut.load_start_pulse);@(negedge clk);reader_ready=0;
     if(!cover_write || dut.load_sector!=4)$fatal(1,"failure scenario did not load cover");
     // Exercise reader-error, scaler-overrun and both inactivity timeouts
     // while the real writer request and a candidate packed word are high.
     force dut.reader_write_req=1'b1;force dut.packed_write_en=1'b1;
     check_cover_fault=1;
     #1;if(dut.write_req!==1 || dut.write_en!==1 || cover_abort)
      $fatal(1,"cover fault fixture did not start with active request/payload");
     repeat(5)@(negedge clk);
     // Scenario 2 fails at the header, scenario 3 after the writer has begun.
     if(scenario==3)begin
      force dut.bmp_data_wr_en=1;repeat(3)@(negedge clk);release dut.bmp_data_wr_en;
     end
     if(scenario==6)scaler_overrun=1;
     else if(scenario==7 || scenario==8)begin
      // 7: source stops. 8: source completes but SDRAM never returns finish.
      if(scenario==8)reader_ready=1;
     end else begin reader_error=1;reader_cover=0;reader_ready=1;end
     wait(cover_abort);wait(dut.commit_pending);
     // Allow the fault observer to check the registered outputs before release.
     #2;check_cover_fault=0;release dut.reader_write_req;release dut.packed_write_en;
     // The real parser makes this sticky when it receives cover_cancel.
     reader_error=1;reader_cover=0;reader_ready=1;scaler_overrun=0;
     if(progress!=4 || dut.cover_loaded || cover_write || cover_commit || !started || dut.render_error)
      $fatal(1,"bad optional cover discarded cache or entered fatal render error");
     acknowledge_commit;
     if(image!=0 || progress!=4 || !dut.audio_stream_enable || commit_count!=1)
      $fatal(1,"bad-cover fallback not committed exactly once");
     repeat(40)@(negedge clk);
     if(dut.load_busy || cover_abort)$fatal(1,"cover retry/abort stayed active");
    end
   end
   $display("PASS cover controller scenario %0d",scenario);
  end
  if(fault_request_checks!=5)$fatal(1,"missing fault/request timing checks %0d",fault_request_checks);
  $display("PASS cover control: four-frame caching, independent source/memory completion, fifth-frame exclusion, silent cover, first KEY2, no-cover/failure fallback and no-image error; five immediate payload gates/next-clock request cancellations");
  $finish;
 end
 initial begin #1000000;$fatal(1,"cover control timeout scenario=%0d load=%b count=%0d",scenario,dut.load_busy,progress);end
endmodule
