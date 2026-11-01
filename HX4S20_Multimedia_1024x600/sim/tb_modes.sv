`timescale 1ns/1ps
module tb_modes;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0,go=0,pv=0;reg [1:0] mode=1;reg [23:0] p=0;
 wire ready,ov,done,over;wire [23:0] rgb;
 bmp_mode_scaler dut(.clk(clk),.rst(rst),.image_start(start),.output_start(go),.output_pause(1'b0),
  .source_width(16'd4),.source_height(16'd2),.mode(mode),.pixel_valid(pv),.pixel_rgb(p),
  .config_ready(ready),.output_valid(ov),.output_rgb(rgb),.output_done(done),.input_overrun(over));
 integer scenario,x,y,count,sx,sy;reg [23:0] expected;
 task tick;begin @(negedge clk);end endtask
 task source_pixels;integer ix,iy;begin
  for(iy=0;iy<2;iy=iy+1)for(ix=0;ix<4;ix=ix+1)begin
   pv=1;p={iy[7:0],ix[7:0],8'h55};tick;
  end
  pv=0;
 end endtask
 always @(negedge clk)if(!rst && ov)begin
  x=count%1024;y=count/1024;expected=24'h101c30;
  case(mode)
   1:if(x>=510&&x<514&&y>=299&&y<301)begin
      sx=x-510;sy=y-299;expected={sy[7:0],sx[7:0],8'h55};end
   2:if(y>=44&&y<556)begin sx=(x*4)/1024;sy=((y-44)*2)/512;expected={sy[7:0],sx[7:0],8'h55};end
   3:begin sx=((x+88)*4)/1200;sy=(y*2)/600;expected={sy[7:0],sx[7:0],8'h55};end
  endcase
  if(rgb!==expected)$fatal(1,"mode%0d xy%0d,%0d got%h expected%h",mode,x,y,rgb,expected);
  count=count+1;
 end
 initial begin
  repeat(4)tick;rst=0;
  for(scenario=1;scenario<=3;scenario=scenario+1)begin
   mode=scenario;start=1;tick;start=0;wait(ready);tick;
   count=0;go=1;tick;go=0;source_pixels;wait(done);repeat(3)tick;
   if(count!=614400)$fatal(1,"pixel count %0d",count);
   if(over)$fatal(1,"input overrun");
  end
  $display("PASS modes: ORIGINAL centre, FIT letterbox, FILL symmetric crop, 1024x600 exact output");$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
