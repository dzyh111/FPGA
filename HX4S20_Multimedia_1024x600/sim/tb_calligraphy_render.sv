`timescale 1ns/1ps
// Preview capture only: every pixel below is read from the live RTL ink RAM.
// The renderer receives the real pen state; it never constructs a reveal mask.
module tb_calligraphy_render;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,enable=1,valid=0;
 reg [2:0] scene=1;reg [10:0] x=0,y=0;
 reg [23:0] rgb=24'hf3eddf;
 wire out_valid;wire [10:0] out_x,out_y;wire [23:0] out_rgb;
 calligraphy_title dut(.*);
 integer capture,s,f,n,k,b,ink_count,lifts,previous_ink;
 reg [3:0] nibble;
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask
 task video_frame;begin frame_tick=1;step;frame_tick=0;repeat(999)step;end endtask
 task snapshot;
  begin
   ink_count=0;
   for(n=0;n<8192;n=n+1)if(dut.ink_canvas[n]===1'b1)ink_count=ink_count+1;
   if(ink_count<previous_ink)$fatal(1,"preview lost persistent ink");
   previous_ink=ink_count;
   $fdisplay(capture,"FRAME %0d %0d %0d %0d %0d %0d %0d %0d %0d",
    s,f,dut.pen_x,dut.pen_y,dut.pen_visible,dut.path_address,dut.done,ink_count,lifts);
   // 2048 hex nibbles, low canvas address first, high nibble bit first.
   for(k=0;k<2048;k=k+1)begin
    for(b=0;b<4;b=b+1)nibble[3-b]=dut.ink_canvas[4*k+b];
    $fwrite(capture,"%h",nibble);
   end
   $fwrite(capture,"\n");
  end
 endtask
 always @(posedge clk)if(!rst && enable && scene==dut.saved_scene && dut.state==3 && dut.path_q[13])lifts=lifts+1;
 initial begin
  capture=$fopen("sim/calligraphy_preview/rtl_frames.txt","w");
  if(!capture)$fatal(1,"cannot open capture; create sim/calligraphy_preview first");
  $fdisplay(capture,"RTL_CALLIGRAPHY_CAPTURE_V1 128 64 60");
  repeat(4)step;rst=0;
  for(s=1;s<=4;s=s+1)begin
   scene=s;repeat(2)step;
   if(dut.state!=7)$fatal(1,"scene change did not arm until frame boundary");
   frame_tick=1;step;frame_tick=0;lifts=0;
   repeat(8300)step;
   if(!dut.ready)$fatal(1,"canvas not ready");
   f=0;previous_ink=0;snapshot;
   while(!dut.done && f<700)begin
    video_frame;f=f+1;snapshot;
   end
   if(!dut.done)$fatal(1,"preview timeout scene %0d",s);
   for(n=0;n<8192;n=n+1)
    if(dut.ink_canvas[n]!==dut.glyph_rom[(s-1)*8192+((n%128)>=64?4096:0)+(n/128)*64+n%64])
     $fatal(1,"preview final canvas mismatch scene %0d pixel %0d",s,n);
   $display("CAPTURE scene %0d: %0d video frames, %0d pen lifts, %0d ink pixels",s,f,lifts,previous_ink);
  end
  $fclose(capture);
  $display("PASS captured live RTL canvas and pen state for all four titles");
  $finish;
 end
 initial begin #40000000;$fatal(1,"render capture timeout");end
endmodule
