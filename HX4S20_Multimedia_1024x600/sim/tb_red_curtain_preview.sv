`timescale 1ns/1ps
// Original-coordinate samples of the actual combinational RTL.
// Thumbnail frames sample every fourth source pixel; native keyframes do not.
module tb_red_curtain_preview;
 reg [23:0] rgb=0;
 reg [10:0] x=0,y=0;
 reg [4:0] fade_alpha=16;
 reg [5:0] manual_phase=63;
 reg manual_active=1,valid=1;
 wire [23:0] out_rgb;
 wire [4:0] out_alpha;
 wire [23:0] out_background;
 gallery_transition dut(.*,.curve_gain_in(8'd0));
 reg [23:0] prior_photo[0:614399],next_photo[0:614399];
 integer frame_no=0,px,yy,xx,fd,n,p;
 reg next_picture=0;
 reg [511:0] filename;
 task capture;
  input [5:0] phase;
  input integer scale;
  input [511:0] destination;
  begin
   manual_phase=phase;
   fade_alpha=phase==63?16:{1'b0,phase[5:2]};
   fd=$fopen(destination,"wb");if(!fd)$fatal(1,"missing preview output directory");
   $fwrite(fd,"P6\n%0d %0d\n255\n",1024/scale,600/scale);
   for(yy=0;yy<600;yy=yy+scale)for(xx=0;xx<1024;xx=xx+scale)begin
    x=xx;y=yy;px=yy*1024+xx;
    rgb=next_picture?next_photo[px]:prior_photo[px];#1;
    if((^out_rgb)===1'bx)$fatal(1,"unknown render pixel");
    $fwrite(fd,"%c%c%c",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
   end
   $fclose(fd);
  end
 endtask
 task thumbnail;
  input [5:0] phase;
  begin
   $sformat(filename,"sim/red_curtain_preview/frame_%02d.ppm",frame_no);
   capture(phase,4,filename);
   $display("RED_CAPTURE %0d phase=%0d next=%0d",frame_no,phase,next_picture);
   frame_no=frame_no+1;
  end
 endtask
 initial begin
  $readmemh("sim/red_curtain_preview/prior.hex",prior_photo);
  $readmemh("sim/red_curtain_preview/next.hex",next_photo);
  thumbnail(63);
  for(p=55;p>=7;p=p-8)thumbnail(p);
  thumbnail(0);
  next_picture=1;thumbnail(0);
  for(n=1;n<=48;n=n+1)thumbnail((n*21)>>4);
  if(frame_no!=58)$fatal(1,"wrong preview frame count");
  capture(0,1,"sim/red_curtain_preview/key_closed.ppm");
  capture(31,1,"sim/red_curtain_preview/key_opening.ppm");
  capture(63,1,"sim/red_curtain_preview/key_open.ppm");
  $display("PASS red curtain preview: 58 original-coordinate 256x150 sampled frames and 3 native 1024x600 keyframes");
  $finish;
 end
endmodule

