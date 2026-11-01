`timescale 1ns/1ps
module tb_slide_control;
reg clk=0;always #5 clk=~clk;
reg rst=1,commit=0;reg [1:0] idx=0;reg rack=0;
wire ack,req,enabled,frame,active,img;wire [1:0] ridx,nidx;
wire [9:0] slide;wire [10:0] x,y;
video_scan #(.H_ACTIVE(8),.H_FP(2),.H_SYNC(1),.H_BP(1),
 .V_ACTIVE(6),.V_FP(2),.V_SYNC(1),.V_BP(1),.IMG_W(8),.IMG_H(6)) dut(
 .clk(clk),.rst(rst),.commit_toggle(commit),.commit_index(idx),
 .commit_ack(ack),.read_index(ridx),.next_index(nidx),.slide_rows(slide),
 .read_req(req),.read_req_ack(rack),.display_enabled(enabled),
 .frame_tick(frame),.active(active),.image_active(img),.x(x),.y(y));
always @(posedge clk)rack<=req;
integer step=0;reg [9:0] previous=0;
always @(negedge clk)if(!rst && slide!=previous)begin
 if(slide!=0)begin
  step=step+1;
  if(slide!=step*20 || ridx!=0 || nidx!=1)$fatal(1,"bad animation step");
  if(ack!=1)$fatal(1,"ack before animation end");
 end else if(step!=29 || ridx!=1)$fatal(1,"bad animation end");
 previous=slide;
end
initial begin
 #31;rst=0;#100;commit=1;wait(ack==1);
 @(negedge clk);idx=1;commit=0;wait(ack==0);
 if(step!=29 || slide!=0 || ridx!=1)$fatal(1,"bad final commit");
 $display("PASS slide_control: all 30 frame steps and final acknowledgement");$finish;
end
initial begin #100000;$fatal(1,"control timeout");end
endmodule
