`timescale 1ns/1ps
module tb_zoom_borrow_equivalence;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,line_start=0,active=0,display_enabled=0,cover_active=0;
 reg [2:0] zoom_index=0;
 reg [10:0] x=0,y=0;
 reg [31:0] read_data=0;
 wire re0,v0,re1,v1;
 wire [10:0] sx0,sy0,px0,py0,sx1,sy1,px1,py1;
 wire [23:0] rgb0,rgb1;
 video_zoom_rgb565 dut(clk,rst,frame_tick,line_start,active,display_enabled,cover_active,
  zoom_index,x,y,read_data,re0,v0,sx0,sy0,px0,py0,rgb0);
 video_zoom_rgb565_reference refdut(clk,rst,frame_tick,line_start,active,display_enabled,cover_active,
  zoom_index,x,y,read_data,re1,v1,sx1,sy1,px1,py1,rgb1);
 reg [3:0] sum;
 reg [2:0] den;
 wire [1:0] old_step=sum>=({1'b0,den}<<1)?2:sum>={1'b0,den}?1:0;
 wire [3:0] old_rem=sum-(old_step==2?({1'b0,den}<<1):old_step==1?{1'b0,den}:4'd0);
 wire [4:0] one={1'b0,sum}-{2'b0,den};
 wire [4:0] two={1'b0,sum}-{1'b0,den,1'b0};
 wire [1:0] new_step=!two[4]?2'd2:!one[4]?2'd1:2'd0;
 wire [3:0] new_rem=!two[4]?two[3:0]:!one[4]?one[3:0]:sum;
 integer a,b,i,checks=0,comb=0;
 reg [31:0] random_state=32'h95a6c37d;
 function [31:0] rng;
 input [31:0] r;
 begin rng={r[30:0],r[31]^r[21]^r[1]^r[0]};end
 endfunction
 task compare;
 begin
  #1;
  if({re0,v0,sx0,sy0,px0,py0,rgb0}!=={re1,v1,sx1,sy1,px1,py1,rgb1})
   $fatal(1,"video zoom mismatch cycle=%0d z=%0d xy=%0d,%0d",checks,zoom_index,x,y);
  if({dut.source_x,dut.source_y,dut.x_rem,dut.y_rem,dut.words_consumed,dut.last_word,dut.word_valid}!==
     {refdut.source_x,refdut.source_y,refdut.x_rem,refdut.y_rem,refdut.words_consumed,refdut.last_word,refdut.word_valid})
   $fatal(1,"video zoom state mismatch cycle=%0d",checks);
  checks=checks+1;
 end
 endtask
 initial begin
  for(a=0;a<16;a=a+1)for(b=0;b<8;b=b+1)begin
   sum=a;den=b;#1;
   if({old_step,old_rem}!=={new_step,new_rem})$fatal(1,"arithmetic mismatch sum=%0d den=%0d",a,b);
   comb=comb+1;
  end
  repeat(4)@(negedge clk);rst=0;
  for(i=0;i<220000;i=i+1)begin
   @(negedge clk);
   random_state=rng(random_state);
   rst=(i%10007==0);
   zoom_index=(i/241)%8;cover_active=(i/577)%2;
   frame_tick=(i%223==0);line_start=(i%79==0);
   active=(i%13!=0);display_enabled=(i%19!=0);
   x=random_state[10:0];y=random_state[21:11];read_data=random_state;
   @(posedge clk);compare();
  end
  $display("PASS zoom borrow equivalence: %0d arithmetic full-domain cases, %0d exact cycle/state comparisons, all 8 zoom codes and both cover states, resets/bubbles/handshake boundaries",comb,checks);
  $finish;
 end
endmodule
