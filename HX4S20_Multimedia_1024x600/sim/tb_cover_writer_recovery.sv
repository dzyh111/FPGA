`timescale 1ns/1ps
// No asynchronous writer abort is necessary: drain accepted bursts, leave an
// insufficient FIFO tail idle, and let the next normal write request clear it.
module tb_cover_writer_recovery;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,request=0,read_busy=0;
 reg [1:0] index=0;reg [20:0] length=64;
 reg [9:0] used=0;
 wire ack,finish,clear_fifo,write_enable,writer_busy;
 wire [20:0] address;
 frame_fifo_write #(.BURST_SIZE(16),.BURST_BITS(5),.WRITE_V_FLIP(0)) dut(
  .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
  .Sdr_busy(1'b0),.App_rd_busy(read_busy),.O_wr_busy(writer_busy),
  .App_wr_en(write_enable),.App_wr_addr(address),.write_req(request),
  .write_req_ack(ack),.write_finish(finish),.write_addr_0(21'd1000),
  .write_addr_1(21'd5000),.write_addr_2(21'd0),.write_addr_3(21'd0),
  .write_addr_index(index),.write_len(length),.fifo_aclr(clear_fifo),.rdusedw(used));
 integer phase=0,first_words=0,next_words=0,clear_edges=0;
 reg finished=0,source_stopped=0,old_clear=0;
 always @(posedge clk)begin
  if(rst)begin used<=0;old_clear<=0;end
  else begin
   old_clear<=clear_fifo;
   if(clear_fifo && !old_clear)clear_edges=clear_edges+1;
   if(clear_fifo)used<=0;
   else if(write_enable)begin
    if(used==0)$fatal(1,"writer consumed beyond the actual FIFO occupancy");
    used<=used-1'b1;
   end
   if(write_enable)begin
    if(phase==0)begin
     if(address!==1000+first_words)$fatal(1,"accepted cover burst/address was interrupted");
     first_words=first_words+1;
    end else begin
     if(address!==5000+next_words)$fatal(1,"new request did not relatch frame base/clear old stream");
     next_words=next_words+1;
    end
   end
   if(finish)finished=1;
  end
 end
 task start_write(input [1:0] selected,input integer words);begin
  @(negedge clk);index=selected;length=words;request=1;
  wait(ack);repeat(4)@(negedge clk);
  if(!clear_fifo || used!=0)$fatal(1,"normal write ACK did not clear FIFO");
  request=0;wait(!ack && !clear_fifo);@(negedge clk);
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;
  start_write(0,64);used=29;
  wait(first_words==8);@(negedge clk);source_stopped=1;
  // Model a bad cover source terminating during an already accepted burst.
  wait(dut.state==2 && first_words==16);repeat(40)@(negedge clk);
  if(first_words!=16 || used!=13 || writer_busy || finish || finished)
   $fatal(1,"partial cover tail blocked reader or chopped accepted burst");
  read_busy=1;
  repeat(20)begin
   @(negedge clk);
   if(writer_busy || write_enable)$fatal(1,"stopped source did not leave SDRAM read arbitration free");
  end
  read_busy=0;phase=1;start_write(1,32);
  if(clear_edges!=2 || used!=0)$fatal(1,"new request failed to discard partial cover FIFO tail");
  used=40;wait(finished);repeat(8)@(negedge clk);
  if(next_words!=32 || first_words!=16 || writer_busy || dut.state!=0 || !source_stopped)
   $fatal(1,"normal frame failed after optional-cover source termination");
  $display("PASS cover writer recovery: complete accepted 16-word burst, idle 13-word tail permits reads, new ACK clears FIFO and 32-word frame relatches base/completes");
  $finish;
 end
 initial begin #200000;$fatal(1,"cover writer recovery timeout");end
endmodule
