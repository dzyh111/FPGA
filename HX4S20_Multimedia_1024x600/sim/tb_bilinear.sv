`timescale 1ns/1ps
module tb_bilinear;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,pv=0;reg [15:0] sw=4,sh=3;reg [23:0] pix=0;
wire ov,done,overrun;wire [23:0] out;
reg done_seen=0;
bmp_bilinear_scaler #(.OUT_W(8),.OUT_H(6),.MAX_W(8)) dut(
 .clk(clk),.rst(rst),.image_start(start),.source_width(sw),.source_height(sh),
 .pixel_valid(pv),.pixel_rgb(pix),.output_valid(ov),.output_rgb(out),
 .output_done(done),.input_overrun(overrun));
integer ix,iy,count=0,ox,oy,x0,y0,xrem,yrem,x1,y1;
integer p00,p01,p10,p11,top,bot,expected,fx,fy;
function integer lerp;input integer a,b,f;begin lerp=a+(((b-a)*f)>>>8);end endfunction
always @(negedge clk)if(ov)begin
 ox=count%8;oy=count/8;x0=(ox*3)/7;xrem=(ox*3)%7;
 y0=(oy*2)/5;yrem=(oy*2)%5;x1=x0==3?3:x0+1;y1=y0==2?2:y0+1;
 fx=(xrem*256)/7;fy=(yrem*256)/5;
 p00=y0*40+x0*10;p01=y0*40+x1*10;p10=y1*40+x0*10;p11=y1*40+x1*10;
 top=lerp(p00,p01,fx);bot=lerp(p10,p11,fx);expected=lerp(top,bot,fy);
 if(out!=={expected[7:0],expected[7:0],expected[7:0]})$fatal(1,"pixel %d,%d got %h expected %d",ox,oy,out,expected);
 count=count+1;
end
always @(posedge clk)if(done)done_seen<=1;
task send_pixel(input integer value);begin
 pix={value[7:0],value[7:0],value[7:0]};pv=1;@(negedge clk);pv=0;repeat(200)@(negedge clk);
end endtask
initial begin
 repeat(4)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;
 for(iy=0;iy<3;iy=iy+1)for(ix=0;ix<4;ix=ix+1)send_pixel(iy*40+ix*10);
 wait(done_seen);wait(count==48);@(negedge clk);
 if(count!=48 || overrun)$fatal(1,"count/overrun %d %d",count,overrun);
 $display("PASS bilinear: arbitrary 4x3 BMP mapping to 8x6, 48 RGB pixels exact");$finish;
end
initial begin #100000;$fatal(1,"timeout count=%d out_y=%d vbase=%d pair=%d in_y=%d gen=%d",count,dut.out_y,dut.v_base,dut.pair_y,dut.in_y,dut.generating);end
endmodule
