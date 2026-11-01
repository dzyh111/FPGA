`timescale 1ns/1ps
module tb_commit;
reg clk=0;always #5 clk=~clk;
reg rst=1,finish=0,ack=0;wire toggle;wire[1:0] wi,di,im;wire[3:0] state;
wire dv,autoen,req,we,cs,sclk,mosi;wire[31:0] data;
sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut(
 .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),.state_code(state),
 .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(dv),
 .write_finish_toggle(finish),.commit_toggle(toggle),.commit_ack(ack),
 .current_image(im),.auto_enabled(autoen),.write_buf_idx(wi),.disp_buf_idx(di),
 .write_req(req),.write_req_ack(1'b0),.write_en(we),.write_data(data),
 .SD_nCS(cs),.SD_DCLK(sclk),.SD_MOSI(mosi),.SD_MISO(1'b1));
task scenario(input early_finish);
 begin
  rst=1;finish=0;ack=0;repeat(4)@(negedge clk);rst=0;
  wait(dut.load_busy);wait(!dut.bmp_ready);
  if(early_finish)begin @(negedge clk);finish=1;end
  wait(dut.source_done_seen);
  if(!early_finish)begin repeat(5)@(negedge clk);finish=1;end
  wait(toggle==1);
  repeat(10)@(negedge clk);
  if(!dut.commit_pending || dv)$fatal(1,"display committed before video ack");
  ack=1;repeat(5)@(negedge clk);
  if(dut.load_busy || !dv || di!=0)$fatal(1,"commit not completed");
 end
endtask
initial begin scenario(1);scenario(0);$display("PASS commit: both completion orders, old buffer held until video acknowledgement");$finish;end
initial begin #100000;$fatal(1,"commit timeout");end
endmodule

// File-reader / card protocol models exercise the real playback state machine.
module bmp_read(
input clk,rst,scan_start,load_start,sd_init_done,write_req_ack,
input [31:0] scan_start_sector,scan_max_sector,load_sector,
input [2:0] scan_target_count,input [15:0] bmp_width,bmp_height,
input [7:0] sd_sec_read_data,input sd_sec_read_data_valid,sd_sec_read_end,
output reg ready,scan_done,scan_found_valid,output reg[31:0] scan_found_sector,
output reg[2:0] scan_found_total,output[3:0] state_code,
output write_req,sd_sec_read,output[31:0] sd_sec_read_addr,
output bmp_data_wr_en,output[23:0] bmp_data,
output reg [15:0] source_width,source_height,output reg image_start);
integer busy_count;
assign state_code=1;assign write_req=0;assign sd_sec_read=0;assign sd_sec_read_addr=0;assign bmp_data_wr_en=0;assign bmp_data=0;
always @(posedge clk or posedge rst)if(rst)begin
 ready<=1;scan_done<=0;scan_found_valid<=0;scan_found_sector<=0;scan_found_total<=0;busy_count<=0;
 source_width<=640;source_height<=480;image_start<=0;
end else begin
 scan_found_valid<=0;image_start<=0;
 if(scan_start)begin scan_found_valid<=1;scan_found_total<=1;scan_done<=1;end
 if(load_start)begin ready<=0;busy_count<=20;image_start<=1;end
 if(busy_count>0)begin busy_count<=busy_count-1;if(busy_count==1)ready<=1;end
end
endmodule
module sd_card_top(
input clk,rst,SD_MISO,sd_sec_read,sd_sec_write,
input[31:0]sd_sec_read_addr,sd_sec_write_addr,input[7:0]sd_sec_write_data,
output SD_nCS,SD_DCLK,SD_MOSI,sd_init_done,
output[7:0]sd_sec_read_data,output sd_sec_read_data_valid,sd_sec_read_end,sd_sec_write_data_req,sd_sec_write_end);
assign sd_init_done=~rst;assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=1;
assign sd_sec_read_data=0;assign sd_sec_read_data_valid=0;assign sd_sec_read_end=0;assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
endmodule
