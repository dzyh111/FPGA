`timescale 1ns/1ps
module tb_cover_scan;
 reg pixel_clk=0;always #7 pixel_clk=~pixel_clk;
 reg source_clk=0;always #5 source_clk=~source_clk;
 reg memory_clk=0;always #11 memory_clk=~memory_clk;
 reg rst=1,token=0,cover_meta=0,blank=0,rack=0;
 reg [1:0] index=0;
 wire ack,blank_ack,req,enabled,tick,busy,read_cover;
 wire [1:0] current,next;wire [4:0] alpha;wire [9:0] slide;
 video_scan #(.H_ACTIVE(16),.H_FP(4),.H_SYNC(2),.H_BP(4),
  .V_ACTIVE(4),.V_FP(1),.V_SYNC(1),.V_BP(1),.IMG_W(16),.IMG_H(4),
  .ENABLE_COVER(1)) dut(.clk(pixel_clk),.rst(rst),.commit_toggle(token),
  .commit_index(index),.commit_cover(cover_meta),.read_cover(read_cover),
  .blank_toggle(blank),.blank_ack(blank_ack),.commit_ack(ack),
  .read_index(current),.next_index(next),.slide_rows(slide),.fade_alpha(alpha),
  .transition_busy(busy),.read_req(req),.read_req_ack(rack),
  .display_enabled(enabled),.frame_tick(tick));
 // Asynchronous SDRAM-side handshake with an intentionally long response.
 reg [1:0] req_sync=0;
 integer delay_memory=0,requested_delay=41;
 always @(posedge memory_clk)begin
  if(rst)begin req_sync<=0;rack<=0;delay_memory<=0;end
  else begin
   req_sync<={req_sync[0],req};
   if(!req_sync[1])begin rack<=0;delay_memory<=requested_delay;end
   else if(!rack)begin
    if(delay_memory==0)rack<=1;else delay_memory<=delay_memory-1;
   end
  end
 end
 reg old_cover=0,old_ack=0;reg [1:0] old_index=0;
 reg old_tick=0;
 integer select_changes=0;
 always @(posedge pixel_clk)begin
  old_tick=tick;
  #1;
  if(!rst)begin
   if(read_cover!=old_cover || current!=old_index)begin
    if(!old_tick || alpha!=0)$fatal(1,"cover/image address changed outside invisible frame boundary");
    select_changes=select_changes+1;
   end
   if(ack!=old_ack && (!old_tick || alpha!=16 || !enabled))
    $fatal(1,"commit ACK escaped frame/full-fade boundary");
   if(slide!=0 || alpha>16)$fatal(1,"legacy fade invariants changed");
  end
  old_cover=read_cover;old_index=current;old_ack=ack;
 end
 task commit_frame(input reg is_cover,input [1:0] selected);
  integer previous_changes;reg old_token;begin
   previous_changes=select_changes;old_token=token;
   @(negedge source_clk);cover_meta=is_cover;index=selected;token=~token;
   // Metadata must stay stable until the toggle acknowledgment returns.
   wait(busy);wait(req);repeat(4)@(negedge pixel_clk);
   if(ack!=old_token)$fatal(1,"video acknowledged before memory data became ready");
   wait(ack==token);@(negedge source_clk);
   if(read_cover!==is_cover || current!==selected || alpha!=16 || !enabled)
    $fatal(1,"asynchronous cover commit mismatch");
   if(select_changes!=previous_changes+1)$fatal(1,"selection changed more than once per commit");
  end
 endtask
 initial begin
  repeat(6)@(negedge source_clk);rst=0;
  commit_frame(1,0); // Initial fifth-frame cover.
  requested_delay=83;
  commit_frame(0,0); // Same image index, but a different memory frame.
  commit_frame(0,3);
  commit_frame(1,0);
  @(negedge source_clk);blank=1;wait(blank_ack==blank);
  if(enabled || alpha!=0)$fatal(1,"cover blank handshake");
  commit_frame(0,2);
  $display("PASS cover scan: independent 100/71.4/45.5 MHz clocks, fifth-frame metadata, delayed memory ACK, frame-boundary switches and unchanged fades");
  $finish;
 end
 initial begin #2000000;$fatal(1,"cover scan timeout");end
endmodule
