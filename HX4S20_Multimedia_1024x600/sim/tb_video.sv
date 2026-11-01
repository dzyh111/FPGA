`timescale 1ns/1ps
module tb_video;
reg clk=0;always #5 clk=~clk;
reg rst=1,commit=0;reg [1:0] idx=0;wire ack;wire [1:0] ridx;
wire req;reg rack=0;wire enabled,frame,active,img;wire [10:0] x,y;
video_scan scan(clk,rst,commit,idx,ack,ridx,req,rack,enabled,frame,active,img,x,y);
wire re,pv;wire [10:0] px,py;wire [23:0] rgb;
reg [23:0] data=0;integer count_data=0;
always @(posedge clk)begin
 rack<=req;
 if(re)begin data<=count_data;count_data<=count_data+1;end
end
video_pixels pixels(clk,rst,active,img,enabled,x,y,data,re,pv,px,py,rgb);
wire ov,sof,last,mute;wire [23:0] orgb;
media_osd osd(clk,rst,frame,4'b0000,4'd1,2'd0,1'b0,1'b0,24'sd0,pv,px,py,rgb,ov,sof,last,orgb,mute);
integer n=0,lines=0,frames=0,reads=0,cycles=0,frame_cycle=0,expected=0;
reg old_ack=0;reg started=0;
always @(negedge clk)if(!rst)begin
 cycles=cycles+1;
 if(re)reads=reads+1;
 if(pv && px>=192 && px<832 && py>=60 && py<540 && enabled)begin
    if(rgb!==expected[23:0])$fatal(1,"FIFO alignment at %d,%d got %d expected %d",px,py,rgb,expected);
    expected=expected+1;
 end
 if(sof)begin
   if(started)begin
     if(n!=614400 || lines!=600 || cycles-frame_cycle!=853440)$fatal(1,"frame geometry %d %d %d",n,lines,cycles-frame_cycle);
     frames=frames+1;
   end
   started=1;n=0;lines=0;frame_cycle=cycles;
 end
 if(ov)begin n=n+1;if(last)begin if(n%1024!=0)$fatal(1,"bad EOL");lines=lines+1;end end
 if(ack!=old_ack)begin if(active)$fatal(1,"commit outside blank");if(ridx!=idx)$fatal(1,"bad bank");old_ack=ack;end
 if(frames==2)begin $display("PASS video: 1024x600, 600 EOL, one SOF, 853440 clocks/frame, FIFO alignment");$finish;end
end
initial begin #35;rst=0;#100;idx=1;commit=1;end
initial begin #30000000;$fatal(1,"video timeout");end
endmodule
