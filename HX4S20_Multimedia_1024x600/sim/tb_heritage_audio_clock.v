`timescale 1ns/1ps
module tb_heritage_audio_clock;
 reg clk=0,rst=1,play=0,mute=0,empty=0,clear=1;
 reg [31:0] total=10;
 wire pop,valid,consumed,loop;
 wire [31:0] pos;
 wire [23:0] left,right,analysis;
 wire [19:0] n,cts;
 wire acr;
 integer pops=0,valids=0,errors=0;
 reg old_loop;
 wav_audio_player #(.PIXEL_HZ(480000)) dut(
 .clk(clk),.rst(rst),.play_enable(play),.mute(mute),.stream_reset(clear),
 .sample_total(total),.fifo_data(32'h80007fff),.fifo_empty(empty),.fifo_read(pop),
 .valid(valid),.left_data(left),.right_data(right),.analysis_sample(analysis),
 .acr_valid(acr),.acr_n(n),.acr_cts(cts),.sample_consumed(consumed),
 .sample_position(pos),.loop_toggle(loop));
 always #5 clk=~clk;
 always @(negedge clk)begin
  if(pop)pops=pops+1;
  if(valid)valids=valids+1;
  if(pop!==consumed)begin errors=errors+1;$display("FAIL pop/consumed");end
 end
 task cycles;input integer count;integer i;begin
  for(i=0;i<count;i=i+1)@(negedge clk);
 end endtask
 initial begin
  cycles(3);rst=0;cycles(25);
  if(pops!=0 || valids<2)begin errors=errors+1;$display("FAIL clock while idle");end
  clear=0;play=1;cycles(100);
  if(pops!=10 || pos!=0 || loop!=1)begin errors=errors+1;$display("FAIL loop %d %d %d",pops,pos,loop);end
  play=0;cycles(30);
  if(pops!=10 || pos!=0)begin errors=errors+1;$display("FAIL paused advanced");end
  play=1;mute=1;cycles(20);
  if(pops!=12 || pos!=2 || left!=0 || right!=0 || analysis!=24'h7fff00)begin
   errors=errors+1;$display("FAIL muted clock/analysis");end
  empty=1;cycles(30);
  if(pops!=12 || pos!=2)begin errors=errors+1;$display("FAIL starvation advanced");end
  old_loop=loop;clear=1;empty=0;cycles(25);
  if(pos!=0 || pops!=12 || loop!=old_loop)begin errors=errors+1;$display("FAIL reset event");end
  clear=0;mute=0;cycles(10);
  if(pos!=1 || pops!=13 || left!=24'h7fff00 || right!=24'h800000)begin
   errors=errors+1;$display("FAIL restart");end
  if(errors==0)$display("PASS heritage audio: pause/mute/underflow/reset/loop");
  else $fatal(1,"%0d errors",errors);
  $finish;
 end
endmodule
