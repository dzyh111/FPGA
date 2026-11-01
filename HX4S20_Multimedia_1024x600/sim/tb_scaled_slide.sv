`timescale 1ns/1ps
module tb_scaled_slide;
reg clk=0,memclk=0,rst=1;
always #5 clk=~clk;
always #6.4 memclk=~memclk;
reg commit=0;reg [1:0] idx=0;
wire ack,req,rack,enabled,frame,active,img;
wire [1:0] ridx,nidx;wire [9:0] slide;
wire [10:0] x,y,px,py;wire re,pv;wire [23:0] rgb;
video_scan scan(.clk(clk),.rst(rst),.commit_toggle(commit),.commit_index(idx),
 .commit_ack(ack),.read_index(ridx),.next_index(nidx),.slide_rows(slide),
 .read_req(req),.read_req_ack(rack),.display_enabled(enabled),
 .frame_tick(frame),.active(active),.image_active(img),.x(x),.y(y));
wire app_en,aclr,finish;wire [20:0] addr;
integer wp=0,rp=0;reg [23:0] fifo[0:1023];reg [23:0] data=0;
wire [9:0] used=wp-rp;
frame_fifo_read #(.BURST_SIZE(256)) reader(.rst(rst),.mem_clk(memclk),
 .Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.Sdr_rd_en(1'b0),
 .App_wr_busy(1'b0),.O_rd_busy(),.App_rd_en(app_en),.App_rd_addr(addr),
 .read_req(req),.read_req_ack(rack),.read_finish(finish),
 .read_addr_0(21'd0),.read_addr_1(21'd480000),.read_addr_2(21'd960000),.read_addr_3(21'd1440000),
 .read_addr_index(ridx),.read_next_index(nidx),.read_slide_rows(slide),
 .read_len(21'd480000),.fifo_aclr(aclr),.wrusedw(used));
// Ten-memory-clock SDRAM response pipeline and synchronous-read FIFO model.
reg [9:0] pipevalid=0;reg [20:0] pipeaddr[0:9];integer k;
always @(posedge memclk) begin
 if(rst || aclr)begin wp=0;pipevalid<=0;end
 else begin
  pipevalid<={pipevalid[8:0],app_en};pipeaddr[0]<=addr;
  for(k=1;k<10;k=k+1)pipeaddr[k]<=pipeaddr[k-1];
  if(pipevalid[9])begin
   if(wp-rp>=512)$fatal(1,"FIFO overflow");
   fifo[wp%1024]=pipeaddr[9];wp=wp+1;
  end
 end
end
always @(posedge clk) begin
 if(rst || aclr)begin rp=0;data<=0;end
 else if(re)begin
  if(wp<=rp)$fatal(1,"FIFO underflow x=%d y=%d slide=%d",x,y,slide);
  data<=fifo[rp%1024];rp=rp+1;
 end
end
video_pixels pixels(clk,rst,active,img,enabled,x,y,data,re,pv,px,py,rgb);
integer expected,sy,bank,pixels_checked=0,frames_checked=0;
reg start=0,second=0;
// One complete scaled frame is sufficient for the integrated pixel/FIFO path.
// Jump over repeated animation positions; tb_slide_control checks all 30 steps.
always @(negedge clk) begin
 if(!rst && scan.animating && scan.hc==1 && scan.vc==0 && slide==20)
  scan.slide_rows=10'd580;
end
always @(negedge clk)if(!rst)begin
 if(pv && enabled && px>=112 && px<912)begin
  sy=py+slide;
  bank=sy>=600?nidx:ridx;
  if(sy>=600)sy=sy-600;
  expected=bank*480000+sy*800+(px-112);
  if(rgb!==expected[23:0])$fatal(1,"pixel %d,%d slide %d got %h expected %h",px,py,slide,rgb,expected);
  pixels_checked=pixels_checked+1;
 end
 if(frame && enabled)begin
  frames_checked=frames_checked+1;
  if(frames_checked==1)begin idx=1;commit=0;second=1;end
 end
 if(second && ack==0)begin
  if(ridx!=1 || slide!=0)$fatal(1,"commit before slide complete");
  $display("PASS scaled_slide: %d pixels checked, no FIFO underflow, 800x600, slide and frame commit",pixels_checked);
  $finish;
 end
end
initial begin #31;rst=0;#100;commit=1;end
initial begin #350000000;$fatal(1,"timeout");end
endmodule
