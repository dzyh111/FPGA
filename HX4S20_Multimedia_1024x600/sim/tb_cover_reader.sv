`timescale 1ns/1ps
// Exercise the real FAT directory/header/pixel state machine. The SD transport
// model retains the physical minimum of 36 system clocks between SPI bytes.
module tb_cover_reader;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,scan=0,load=0,write_ack=1,cancel_cover=0;
 reg [31:0] handle=0;
 wire ready,done,found,cover_found,cover_error,rd,write_req,pixel_valid;
 wire [31:0] lba,index;wire [2:0] total;wire [3:0] status;
 wire [23:0] pixel;
 reg [7:0] rx=0;reg valid=0,ending=0;
 bmp_read #(.COVER_TIMEOUT_CYCLES(27'd24000)) dut(
  .clk(clk),.rst(rst),.ready(ready),.scan_start(scan),
  .scan_start_sector(32'd0),.scan_max_sector(32'd8191),.scan_target_count(3'd4),
  .scan_done(done),.scan_found_valid(found),.scan_found_sector(index),
  .scan_found_total(total),.cover_found(cover_found),.cover_error(cover_error),.cover_cancel(cancel_cover),
  .load_start(load),.load_sector(handle),.sd_init_done(1'b1),.state_code(status),
  .bmp_width(16'd1024),.bmp_height(16'd600),.write_req(write_req),
  .write_req_ack(write_ack),.sd_sec_read(rd),.sd_sec_read_addr(lba),
  .sd_sec_read_data(rx),.sd_sec_read_data_valid(valid),.sd_sec_read_end(ending),
  .bmp_data_wr_en(pixel_valid),.bmp_data(pixel),.audio_stream_enable(1'b0),
  .audio_fifo_afull(1'b0),.audio_scene(3'd0),.audio_restart(1'b0));
 reg [7:0] disk[0:32767];
 integer scenario,k,j,pos=0,base=0,busy=0,gap=0,seen=0,pixels=0;
 integer end_limit=512,stall_cycles=0,cover_reads=0,ordinary_reads=0;
 integer last_byte_cycle=-100,cycle=0,requests=0;
 reg testing_cover=0,check_pixels=0,late_drain_seen=0;
 task put32(input integer a,input integer v);begin
  disk[a]=v;disk[a+1]=v>>8;disk[a+2]=v>>16;disk[a+3]=v>>24;
 end endtask
 task entry(input integer slot,input [87:0] name,input integer cluster,input integer size);
  integer n,a;begin a=1024+slot*32;
   for(n=0;n<11;n=n+1)disk[a+n]=name[(10-n)*8+:8];
   disk[a+11]=32;disk[a+26]=cluster;disk[a+27]=cluster>>8;put32(a+28,size);
  end
 endtask
 task bmp(input integer cluster,input integer width,input integer height,input integer offset);
  integer a,n;begin a=cluster*512;
   disk[a]="B";disk[a+1]="M";put32(a+10,offset);put32(a+14,40);
   put32(a+18,width);put32(a+22,height);disk[a+26]=1;disk[a+28]=24;
   for(n=offset;n<512;n=n+1)disk[a+n]=(n-offset)%3==0?8'h11:
                                      (n-offset)%3==1?8'h22:8'h33;
  end
 endtask
 always @(negedge clk)begin
  valid=0;ending=0;cycle=cycle+1;
  if(rst)begin busy=0;pos=0;gap=0;stall_cycles=0;last_byte_cycle=-100;end
  else if(busy==1)begin
   if(stall_cycles>0)stall_cycles=stall_cycles-1;
   else if(gap!=0)gap=gap-1;
   else if(pos<end_limit)begin
    if(cycle-last_byte_cycle<36)$fatal(1,"SPI byte spacing below 36 clocks");
    rx=disk[base+pos];valid=1;pos=pos+1;gap=35;last_byte_cycle=cycle;
   end else begin ending=1;busy=2;end
  end else if(busy==2)begin if(!rd)busy=0;end
  else if(rd)begin
   if(lba>=64)$fatal(1,"unexpected sector %0d scenario %0d",lba,scenario);
   requests=requests+1;busy=1;pos=0;base=lba*512;gap=36;end_limit=512;
   if(lba==20)begin
    cover_reads=cover_reads+1;
    if(testing_cover && scenario==5)end_limit=32; // header sector ends early
    if(testing_cover && scenario==6)stall_cycles=25000; // timeout, then late bytes/end
   end else if(lba>=10 && lba<=13)ordinary_reads=ordinary_reads+1;
  end
 end
 always @(posedge clk)if(!rst)begin
  if(found)begin
   if(index!==seen)$fatal(1,"cover changed ordinary image handle order");
   seen=seen+1;
  end
  if(pixel_valid && check_pixels)pixels=pixels+1;
  if(testing_cover && (scenario==6 || scenario==10) && dut.cover_read_draining)begin
   late_drain_seen=1;
   if(ready || rd)$fatal(1,"timed-out transaction not quarantined");
  end
 end
 task request_load(input integer selected);begin
  wait(ready);@(negedge clk);handle=selected;load=1;
  @(negedge clk);load=0;wait(!ready);
 end endtask
 task setup_disk;begin
  for(k=0;k<32768;k=k+1)disk[k]=0;
  disk[11]=0;disk[12]=2;disk[13]=1;disk[14]=1;disk[16]=1;
  put32(32,100000);put32(36,1);put32(44,2);disk[510]=8'h55;disk[511]=8'haa;
  entry(0,"COVER   BMP",20,scenario==3?100:scenario==4?658:58);
  entry(1,"GUQIN   BMP",10,58);entry(2,"ERHU    BMP",11,58);
  entry(3,"DIZI    BMP",12,58);entry(4,"TANGGU  BMP",13,58);
  bmp(10,1,1,54);bmp(11,1,1,54);bmp(12,1,1,54);bmp(13,1,1,54);
  bmp(20,scenario==3?16:1,scenario==3?2:1,scenario==4?654:54);
  put32(512+20*4,32'h0fffffff); // deliberate early EOC in scenario 4
  if(scenario==1)disk[1024]=8'he5; // no optional cover
  if(scenario==2)disk[20*512]="X"; // bad cover signature
  if(scenario==7)begin
   disk[10*512]="X";disk[11*512]="X";disk[12*512]="X";disk[13*512]="X";
  end
 end endtask
 initial begin
  // 0 valid, 1 absent, 2 corrupt header, 3 truncated pixels, 4 broken FAT,
  // 5 short transport sector, 6 timeout/late end, 7 no legal instruments,
  // 8 regular image corruption remains fatal, 9 cover ACK timeout,
  // 10 in-flight controller cancellation, 11 source-done sink cancellation.
  for(scenario=0;scenario<12;scenario=scenario+1)begin
   rst=1;scan=0;load=0;cancel_cover=0;write_ack=1;seen=0;pixels=0;
   cover_reads=0;ordinary_reads=0;testing_cover=0;check_pixels=0;late_drain_seen=0;
   setup_disk;
   repeat(5)@(negedge clk);rst=0;scan=1;@(negedge clk);scan=0;
   wait(done);repeat(4)@(negedge clk);
   if(scenario==7)begin
    if(total!==0 || seen!=0 || status!=14 || ready)
     $fatal(1,"cover must not mask no-legal-instrument error");
   end else begin
    if(total!==4 || seen!=4 || dut.candidate_count!=4 || ordinary_reads!=4 || cover_reads!=0)
     $fatal(1,"cover counted/validated as ordinary image %0d/%0d candidates=%0d",total,seen,dut.candidate_count);
    if(cover_found!==(scenario!=1) || cover_error)$fatal(1,"cover directory discovery");
    if(scenario==1)begin
     request_load(0);wait(ready);
     if(status==14 || cover_error)$fatal(1,"missing optional cover damaged image load");
    end else if(scenario==8)begin
     disk[10*512]="X";request_load(0);wait(status==14);
     repeat(20)@(negedge clk);
     if(ready || cover_error)$fatal(1,"ordinary failure incorrectly recovered as cover");
    end else begin
     testing_cover=1;check_pixels=1;write_ack=scenario!=9;
     request_load(4);
     if(scenario==10)begin
      wait(dut.state==2);repeat(10)@(negedge clk);cancel_cover=1;
      @(negedge clk);cancel_cover=0;
     end
     if(scenario==0 || scenario==11)begin
      wait(ready);@(negedge clk);
      if(!cover_found || cover_error || status==14 || pixels!=1)
       $fatal(1,"valid cover failed pixels=%0d state=%0d",pixels,status);
      if(scenario==11)begin
       cancel_cover=1;@(negedge clk);cancel_cover=0;
       repeat(4)@(negedge clk);
       if(!ready || cover_found || !cover_error || status==14)
        $fatal(1,"source-complete sink cancellation failed");
      end
     end else begin
      wait(cover_error);repeat(4)@(negedge clk);
      if(cover_found || status==14 || total!=4 || seen!=4)
       $fatal(1,"optional cover failure discarded ordinary media scenario %0d",scenario);
      if(scenario==6 || scenario==10)begin
       if(!late_drain_seen || ready)$fatal(1,"RX timeout did not defer new SD requests");
       wait(ready);repeat(4)@(negedge clk);
      end else wait(ready);
      testing_cover=0;check_pixels=0;write_ack=1;
      request_load(0);wait(ready);@(negedge clk);
      if(status==14 || !cover_error)$fatal(1,"image fallback/sticky error failed scenario %0d",scenario);
     end
    end
   end
   $display("PASS cover reader scenario %0d",scenario);
  end
  $display("PASS cover reader: real FAT directory, 36-clock SPI spacing, separate handle, missing/corrupt/truncated/broken-chain/timeout fallback and fatal no-image/ordinary errors");
  $finish;
 end
 initial begin #300000000;$fatal(1,"cover reader timeout scenario=%0d state=%0d",scenario,dut.state);end
endmodule
