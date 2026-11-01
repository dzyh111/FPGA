`timescale 1ns/1ps
module tb_fat32;
reg clk=0;always #5 clk=~clk;
reg rst=1,scan=0,load=0,ack=0;
reg[31:0] index=0;wire ready,done,found,req,rd,we;
wire[31:0] found_index,lba;wire[2:0] total;wire[3:0] state;
wire[23:0] rgb;reg[7:0] rx=0;reg valid=0,ending=0;
bmp_read dut(.clk(clk),.rst(rst),.ready(ready),.scan_start(scan),
 .scan_start_sector(32'd0),.scan_max_sector(32'd8191),.scan_target_count(3'd4),
 .scan_done(done),.scan_found_valid(found),.scan_found_sector(found_index),.scan_found_total(total),
 .load_start(load),.load_sector(index),.sd_init_done(1'b1),.state_code(state),
 .bmp_width(16'd640),.bmp_height(16'd480),.write_req(req),.write_req_ack(ack),
 .sd_sec_read(rd),.sd_sec_read_addr(lba),.sd_sec_read_data(rx),
 .sd_sec_read_data_valid(valid),.sd_sec_read_end(ending),.bmp_data_wr_en(we),.bmp_data(rgb));
reg[7:0] disk[0:6291455];
reg[23:0] expected[0:1228799];
integer pos=0,reads=0,k,image_id,pixels=0,found_count=0;
reg busy=0;reg[31:0] base;
always @(negedge clk) begin
 valid=0;ending=0;
 if(busy) begin
  if(pos<512)begin rx=disk[base+pos];valid=1;pos=pos+1;end
  else begin ending=1;busy=0;end
 end else if(rd)begin busy=1;pos=0;base=lba*512;reads=reads+1;
  if(base>=6290944)$fatal(1,"LBA out of fixture %d",lba);
 end
 ack=req;
end
always @(posedge clk) begin
 if(found)begin
  if(found_index!=found_count)$fatal(1,"file index");found_count=found_count+1;
 end
 if(we)begin
  if(rgb!==expected[pixels])$fatal(1,"pixel %0d got %h expected %h",pixels,rgb,expected[pixels]);
  pixels=pixels+1;
 end
 if(!rst && state==14)begin
  if($test$plusargs("expect_error") && pixels>0 && pixels<307200)begin
   $display("PASS FAT32: premature end of cluster chain rejected; partial frame not marked ready");$finish;
  end
  $fatal(1,"reader error, state %d LBA %d count %d",dut.state,lba,dut.count);
 end
end
initial begin
 for(k=0;k<6291456;k=k+1)disk[k]=0;
 $readmemh("sim/fat32.hex",disk);$readmemh("sim/expected_pixels.hex",expected);
 repeat(5)@(negedge clk);rst=0;scan=1;@(negedge clk);scan=0;
 wait(done);repeat(3)@(negedge clk);
 if(total!=4 || found_count!=4)$fatal(1,"directory enumeration");
 for(image_id=0;image_id<4;image_id=image_id+1)begin
  index=image_id;load=1;@(negedge clk);load=0;
  wait(!ready);wait(ready);repeat(3)@(negedge clk);
  if(pixels!=(image_id+1)*307200)$fatal(1,"pixel count %0d",pixels);
 end
 if($test$plusargs("expect_error"))$fatal(1,"broken chain accepted");
 $display("PASS FAT32: partition/VBR, chained root, LFN skip, four fragmented BMPs, 1228800 exact pixels (%0d reads)",reads);
 $finish;
end
initial begin #200000000;$fatal(1,"timeout");end
endmodule
