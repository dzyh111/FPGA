`timescale 1ns/1ps
module tb_calligraphy_title;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,enable=1,valid=1;
 reg [2:0] scene=1;reg [10:0] x=60,y=90;
 reg [23:0] rgb=24'h204060;
 wire out_valid;wire [10:0] out_x,out_y;wire [23:0] out_rgb;
 calligraphy_title dut(.*);
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask
 integer n,s,f,lifts=0,ink_count,previous_count,expected_strokes,frames[1:4];
 reg checking=0,began_second=0;
 always @(posedge clk)if(checking && !rst && enable && scene==dut.saved_scene)begin
  if(dut.state==3 && dut.path_q[13])begin
   lifts=lifts+1;
   if(dut.path_q[12])began_second=1;
  end
  if(dut.state!=0 && dut.brush_valid && dut.glyph_q && dut.brush_address[6] && !began_second)
   $fatal(1,"second character ink appeared before its first pen-down");
 end
 task video_frame;begin frame_tick=1;step;frame_tick=0;repeat(999)step;end endtask
 initial begin
  repeat(4)step;rst=0;
  for(s=1;s<=4;s=s+1)begin
   checking=0;scene=s;repeat(2)step;frame_tick=1;step;frame_tick=0;
   lifts=0;began_second=0;checking=1;
   repeat(8300)step;
   if(!dut.ready)$fatal(1,"canvas did not clear in vertical blank");
   previous_count=0;f=0;
   while(!dut.done && f<700)begin
    video_frame;f=f+1;
    if(f%20==0)begin
     ink_count=0;for(n=0;n<8192;n=n+1)if(dut.ink_canvas[n])ink_count=ink_count+1;
     if(ink_count<previous_count)$fatal(1,"old ink vanished while writing");
     previous_count=ink_count;
    end
   end
   frames[s]=f;
   if(!dut.done || f<20)$fatal(1,"not a progressive pen animation: scene %0d frames %0d",s,f);
   expected_strokes=s==1?17:(s==2?11:(s==3?14:24));
   if(lifts!=expected_strokes)$fatal(1,"stroke order/lifts scene%0d: %0d vs %0d",s,lifts,expected_strokes);
   // Final canvas must exactly match both installed Xingkai glyphs, including
   // every transparent hole. This detects missing or stray stroke fragments.
   for(n=0;n<8192;n=n+1)begin
    if(dut.ink_canvas[n]!==dut.glyph_rom[(s-1)*8192+((n%128)>=64?4096:0)+(n/128)*64+n%64])
     $fatal(1,"completed glyph mismatch scene%0d canvas%0d",s,n);
   end
   $display("PASS handwriting scene %0d: %0d frames, %0d real pen lifts, every Xingkai pixel present",s,f,lifts);
   repeat(5)video_frame;
   if(!dut.done)$fatal(1,"title restarted without scene change");
  end
  checking=0;enable=0;repeat(5)step;
  if(!out_valid || out_rgb!==rgb || out_x!=x || out_y!=y)$fatal(1,"cover/disabled bypass");
  enable=1;scene=0;repeat(5)step;
  if(out_rgb!==rgb)$fatal(1,"ordinary scene changed photo");
  $display("PASS stroke handwriting: 66 ordered strokes, explicit lifts, first-then-second character, persistent exact ink, scene clear, no wipe/stripe, 3-clock bypass");
  $finish;
 end
 initial begin #40000000;$fatal(1,"handwriting timeout");end
endmodule
