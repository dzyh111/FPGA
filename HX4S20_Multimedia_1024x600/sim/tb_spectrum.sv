`timescale 1ns/1ps
module tb_spectrum;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,valid=0;reg signed [23:0] pcm=0;
 wire [127:0] bars;wire ready;
 audio_spectrum dut(clk,rst,valid,pcm,bars,ready);
 integer n,k,peak,peak_index;
 real s;
 initial begin
 repeat(4)@(negedge clk);rst=0;
 for(n=0;n<256;n=n+1)begin
  s=$sin(2.0*3.141592653589793*4*n/256.0);
  // Real WAV data is 16-bit PCM left-justified in the 24-bit analysis bus.
  pcm=$rtoi(8000*s)*256;valid=1;@(negedge clk);valid=0;
  // Minimum pipeline-safe spacing is 65 clocks; real 48 kHz is 1066/1067.
  repeat(64)@(negedge clk);
 end
 peak=0;peak_index=-1;
 for(k=0;k<16;k=k+1)if(bars[k*8+:8]>peak)begin peak=bars[k*8+:8];peak_index=k;end
 if(peak_index!=3||peak<100)$fatal(1,"750Hz peak %d height %d",peak_index,peak);
 for(n=0;n<256;n=n+1)begin
  pcm=0;valid=1;@(negedge clk);valid=0;repeat(64)@(negedge clk);
 end
 if(bars!=0)$fatal(1,"silence is not zero");
 for(n=0;n<256;n=n+1)begin
  s=$sin(2.0*3.141592653589793*48*n/256.0);
  pcm=$rtoi(3000*s)*256;valid=1;@(negedge clk);valid=0;
  repeat(64)@(negedge clk);
 end
 peak=0;peak_index=-1;
 for(k=0;k<16;k=k+1)if(bars[k*8+:8]>peak)begin peak=bars[k*8+:8];peak_index=k;end
 if(peak_index!=14||peak<20)$fatal(1,"9kHz peak %d height %d",peak_index,peak);
 $display("PASS spectrum: 750Hz and 9kHz bins respond, silence zero");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
