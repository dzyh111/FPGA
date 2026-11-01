`timescale 1ns/1ps
// User-interface contract test, separate from the real vendor control-cone
// phase sweep. Verifies that a busy refresh blocks a NEW burst without
// accidentally advancing FIFO pops, counters or addresses.
module tb_frame_refresh_guard;
 reg clk=0,rst=1,refresh=1,rd_req=0,wr_req=0;
 always #5 clk=~clk;
 wire rd_en,wr_en,rd_ack,wr_ack,rd_finish,wr_finish;
 wire [20:0] rd_addr,wr_addr;
 integer reads=0,writes=0,timeout;
 reg rd_busy_seen=0,wr_busy_seen=0;
 frame_fifo_read #(.BURST_SIZE(256)) r(
  .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),
  .Sdr_init_ref_vld(refresh),.Sdr_busy(refresh),.Sdr_rd_en(1'b0),
  .App_wr_busy(1'b0),.O_rd_busy(),.App_rd_en(rd_en),.App_rd_addr(rd_addr),
  .read_next_index(2'd0),.read_slide_rows(10'd0),
  .read_req(rd_req),.read_req_ack(rd_ack),.read_finish(rd_finish),
  .read_addr_0(21'd1024),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),
  .read_addr_index(2'd0),.read_len(21'd512),.fifo_aclr(),.wrusedw(10'd0));
 frame_fifo_write #(.BURST_SIZE(256),.WRITE_V_FLIP(0)) w(
  .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),
  .Sdr_init_ref_vld(refresh),.Sdr_busy(refresh),.App_rd_busy(1'b0),.O_wr_busy(),
  .App_wr_en(wr_en),.App_wr_addr(wr_addr),.write_req(wr_req),
  .write_req_ack(wr_ack),.write_finish(wr_finish),
  .write_addr_0(21'd2048),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),
  .write_addr_index(2'd0),.write_len(21'd512),.fifo_aclr(),.rdusedw(10'd384));
 always @(posedge clk)if(!rst)begin
  if(rd_en)begin
   if(rd_addr!==1024+reads)$fatal(1,"read address lost after refresh %0d %0d",rd_addr,reads);
   reads=reads+1;
  end
  if(wr_en)begin
   if(wr_addr!==2048+writes)$fatal(1,"write address lost after refresh %0d %0d",wr_addr,writes);
   writes=writes+1;
  end
  if(rd_finish)rd_busy_seen=1;
  if(wr_finish)wr_busy_seen=1;
 end
 initial begin
  repeat(4)@(negedge clk);rst=0;rd_req=1;wr_req=1;
  wait(rd_ack && wr_ack);@(negedge clk);rd_req=0;wr_req=0;
  repeat(40)@(negedge clk);
  if(reads!=0 || writes!=0)$fatal(1,"request started during refresh");
  refresh=0;
  wait(reads==128 && writes==128);@(negedge clk);refresh=1;
  // A pending refresh during a burst must not break its data/addr stream.
  repeat(200)@(negedge clk);
  if(reads!=256 || writes!=256)$fatal(1,"burst interrupted or next burst escaped: %0d %0d",reads,writes);
  repeat(30)@(negedge clk);
  if(reads!=256 || writes!=256)$fatal(1,"burst started while refresh held");
  refresh=0;
  timeout=0;
  while(!(rd_busy_seen && wr_busy_seen) && timeout<700)begin @(negedge clk);timeout=timeout+1;end
  if(reads!=512 || writes!=512 || !rd_busy_seen || !wr_busy_seen)
   $fatal(1,"frame did not finish exactly: rd%0d wr%0d",reads,writes);
  $display("PASS frame refresh guard: no start during refresh, complete 256-word groups, 512 sequential reads/writes");
  $finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
