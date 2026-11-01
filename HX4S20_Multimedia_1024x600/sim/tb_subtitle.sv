`timescale 1ns/1ps
module tb_subtitle;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,wr=0,frame=0,enable=1,picture=1,valid=0,sof=0,last=0;
 reg [8:0] addr=0;reg [7:0] data=0;reg [1:0] index=0;
 wire ov,os,ol;wire [23:0] rgb;
 subtitle_overlay dut(.wr_clk(clk),.wr_en(wr),.wr_addr(addr),.wr_data(data),
 .font_wr_en(1'b0),.font_wr_addr(10'd0),.font_wr_data(16'd0),.font_ready(1'b1),
 .font_quiet_request(1'b0),
 .intro_pause(1'b0),.intro_restart(1'b0),
 .clk(clk),.rst(rst),.frame_tick(frame),.enable(enable),.show_picture(picture),
 .image_index(index),.len0(8'd1),.len1(8'd0),.len2(8'd0),.len3(8'd0),
 .valid(valid),.sof(sof),.last(last),.rgb(24'h204060),
 .out_valid(ov),.out_sof(os),.out_last(ol),.out_rgb(rgb));
 integer x,y,mode,count=0,markers=0,ink=0;reg [23:0] expected;reg active_check=1;
 task tick;begin @(negedge clk);end endtask
 task frame_pulse;begin frame=1;tick;frame=0;tick;end endtask
 always @(negedge clk)if(!rst && ov && active_check)begin
   x=count%1024;y=552+count/1024;
   if(os!==1'b0 || ol!==(x==1023))$fatal(1,"subtitle metadata misaligned at %0d",count);
   expected=24'h204060;
   if(mode==0 && x>=6 && x<1018 && y>=552 && y<594)expected=24'hc8d0d8;
   if(mode==0 && x>=6 && x<32 && y>=560 && y<592 && dut.font[(y-560)/2][15-x/2])begin
     expected=24'h101820;ink=ink+1;
   end
   if(rgb!==expected)$fatal(1,"subtitle pixel mode=%0d xy=%0d,%0d got=%h expected=%h",mode,x,y,rgb,expected);
   count=count+1;
 end
 integer px,py;
 initial begin
  repeat(4)tick;rst=0;
  wr=1;addr=0;data=8'h80;tick;wr=0;
  for(mode=0;mode<3;mode=mode+1)begin
   if(mode==1)enable=0;
   if(mode==2)begin enable=1;index=1;end
   repeat(4)tick;frame_pulse;
   // Place the first glyph at x=0 without waiting 1024 video frames.
   if(mode==0)begin force dut.scroll=13'd1024;end
   count=0;dut.x=0;dut.y=552;
   for(py=552;py<600;py=py+1)begin
    for(px=0;px<1024;px=px+1)begin
     valid=1;sof=(px==0 && py==0);last=(px==1023);tick;
    end
    valid=0;sof=0;last=0;repeat(4)tick;
   end
   repeat(5)tick;
   if(count!=49152)$fatal(1,"output count");
   if(mode==0)begin release dut.scroll;if(ink==0)$fatal(1,"missing Chinese glyph");end
  end
  active_check=0;valid=1;sof=1;last=0;tick;valid=0;sof=0;
  wait(os);tick;
  $display("PASS subtitle: every pixel, Chinese glyph, inset75-percent white strip, protected border gutters, pipeline markers, disabled/empty lines");$finish;
 end
 initial begin #30000000;$fatal(1,"timeout");end
endmodule
