`timescale 1ns/1ps
module tb_curtain_render;
 reg [23:0] rgb=0;
 reg [10:0] x=0,y=0;
 reg [4:0] fade_alpha=16;
 reg [5:0] manual_phase=63;
 reg manual_active=1,valid=1;
 wire [23:0] out_rgb;
 wire [4:0] out_alpha;
 wire [23:0] out_background;
 gallery_transition dut(.*);
 reg [23:0] prior_photo[0:614399],next_photo[0:614399];
 integer frame_no=0,px,yy,xx,fd,n,p;
 reg next_picture=0;
 reg [511:0] filename;
 task capture;
  input [5:0] phase;
  begin
   manual_phase=phase;
   fade_alpha=phase==63?16:{1'b0,phase[5:2]};
   $sformat(filename,"sim/curtain_preview/frame_%02d.ppm",frame_no);
   fd=$fopen(filename,"wb");if(!fd)$fatal(1,"missing preview output directory");
   $fwrite(fd,"P6\n1024 600\n255\n");
   for(yy=0;yy<600;yy=yy+1)for(xx=0;xx<1024;xx=xx+1)begin
    x=xx;y=yy;px=yy*1024+xx;
    rgb=next_picture?next_photo[px]:prior_photo[px];#1;
    if((^out_rgb)===1'bx)$fatal(1,"unknown render pixel");
    $fwrite(fd,"%c%c%c",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
   end
   $fclose(fd);frame_no=frame_no+1;
   $display("CAPTURE %0d phase=%0d next=%0d",frame_no-1,phase,next_picture);
  end
 endtask
 initial begin
  $readmemh("sim/curtain_preview/prior.hex",prior_photo);
  $readmemh("sim/curtain_preview/next.hex",next_photo);
  capture(63);
  for(p=55;p>=7;p=p-8)capture(p);
  capture(0);
  // Single-bank swap is invisible behind an opaque phase-zero veil.
  next_picture=1;capture(0);
  for(p=2;p<=62;p=p+2)capture(p);
  capture(63);
  if(frame_no!=42)$fatal(1,"wrong preview frame count");
  $display("PASS native curtain render: 42 full frames, 25804800 pixels");
  $finish;
 end
endmodule
