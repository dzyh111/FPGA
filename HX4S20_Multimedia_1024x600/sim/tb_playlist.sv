`timescale 1ns/1ps
module tb_playlist;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,scan=0;
 wire ready,done,found,rd,wr;wire [31:0] lba,idx;
 wire [2:0] total;wire [3:0] status;wire [7:0] duration;wire [1:0] mode;
 wire [8:0] addr;wire [7:0] data,n0,n1,n2,n3;
 reg [7:0] rx=0;reg valid=0,ending=0;
 bmp_read dut(.clk(clk),.rst(rst),.ready(ready),.scan_start(scan),
 .scan_start_sector(32'd0),.scan_max_sector(32'd8191),.scan_target_count(3'd4),
 .scan_done(done),.scan_found_valid(found),.scan_found_sector(idx),.scan_found_total(total),
 .scan_found_duration(duration),.scan_found_scale(mode),.subtitle_wr_en(wr),
 .subtitle_wr_addr(addr),.subtitle_wr_data(data),.subtitle_len0(n0),.subtitle_len1(n1),
 .subtitle_len2(n2),.subtitle_len3(n3),.load_start(1'b0),.load_sector(32'd0),
 .sd_init_done(1'b1),.state_code(status),.bmp_width(16'd640),.bmp_height(16'd480),
 .write_req_ack(1'b0),.sd_sec_read(rd),.sd_sec_read_addr(lba),.sd_sec_read_data(rx),
 .sd_sec_read_data_valid(valid),.sd_sec_read_end(ending));
 reg [7:0] disk[0:8191],subtitle[0:511];
 integer pos=0,base=0,busy=0,seen=0,k,n,scenario,byte_gap=0;
 string playlist,caption;
 task put32(input integer a,input integer v);
 begin disk[a]=v;disk[a+1]=v>>8;disk[a+2]=v>>16;disk[a+3]=v>>24;end endtask
 task entry(input integer slot,input [87:0] name,input integer cluster,input integer size);
 integer j,a;begin
 a=1024+32*slot;
 for(j=0;j<11;j=j+1)disk[a+j]=name[(10-j)*8+:8];
 disk[a+11]=32;disk[a+26]=cluster;disk[a+27]=cluster>>8;put32(a+28,size);
 end endtask
 task bmp_header(input integer lba);integer a;begin
  a=lba*512;disk[a]="B";disk[a+1]="M";put32(a+10,54);put32(a+14,40);
  put32(a+18,640);put32(a+22,480);disk[a+26]=1;disk[a+28]=24;
 end endtask
 always @(negedge clk)begin
 valid=0;ending=0;
 if(rst)begin busy=0;pos=0;byte_gap=0;end
 else if(busy==1)begin
  if(byte_gap!=0)byte_gap=byte_gap-1;
  else if(pos<512)begin rx=disk[base+pos];valid=1;pos=pos+1;byte_gap=35;end
  else begin ending=1;busy=2;end
 end else if(busy==2)begin if(!rd)busy=0;end
 else if(rd)begin
  if(lba>=16)$fatal(1,"unexpected sector %0d",lba);
  busy=1;pos=0;base=lba*512;byte_gap=0;
 end
 end
 always @(posedge clk)if(!rst)begin
  if(wr)subtitle[addr]=data;
  if(found)begin
   if(idx!=seen)$fatal(1,"index order");
   if(scenario==3)begin
    if(seen!=0 || duration!=4 || mode!=3)$fatal(1,"invalid BMP compaction");
   end else if(scenario==0)begin
    if(seen==0 && (duration!=5||mode!=2))$fatal(1,"FIT/time");
    if(seen==1 && (duration!=4||mode!=3))$fatal(1,"FILL/time");
    if(seen==2 && (duration!=7||mode!=1))$fatal(1,"ORIGINAL/time");
   end
   seen=seen+1;
  end
  if(status==14 && scenario!=4)$fatal(1,"reader error scenario %0d cluster %0d next %0d bytes %0d limit %0d",scenario,dut.cluster,dut.next_cluster,dut.text_bytes,dut.text_limit);
 end
 initial begin
 for(scenario=0;scenario<5;scenario=scenario+1)begin
  rst=1;seen=0;
  for(k=0;k<8192;k=k+1)disk[k]=0;
  for(k=0;k<512;k=k+1)subtitle[k]=0;
  disk[11]=0;disk[12]=2;disk[13]=1;disk[14]=1;disk[16]=1;
  put32(32,100000);put32(36,1);put32(44,2);disk[510]=8'h55;disk[511]=8'haa;
  // Data base=2. Directory ordering intentionally differs from playlist.
  entry(0,"IMG0    BMP",10,921654);entry(1,"IMG1    BMP",11,921654);
  if(scenario!=4)bmp_header(10);
  if(scenario!=3 && scenario!=4)bmp_header(11);
  playlist={"IMG1.BMP,5,FIT",8'd13,8'd10,"IMG0.BMP,4,FILL",8'd10,"IMG1.BMP,7,ORIGINAL"};
  caption={"你好呀！",8'd13,8'd10,"对不起！"};
  if(scenario==2)caption={8'hef,8'hbb,8'hbf,8'he4,8'hbd,8'ha0,
    8'hc2,8'ha2,8'hf0,8'h9f,8'h98,8'h80,8'd10,"对不起！"};
  entry(2,"PLAYLISTTXT",3,playlist.len());entry(3,"HELLO   TXT",4,scenario==1?613:caption.len());
  for(k=0;k<playlist.len();k=k+1)disk[1536+k]=playlist[k];
  put32(512+4*4,6);put32(512+4*6,32'h0fffffff);
  for(k=0;k<caption.len();k=k+1)begin
   if(k<512)disk[2048+k]=caption[k];else disk[3072+k-512]=caption[k];
  end
  if(scenario==1)begin
   // Explicit bytes avoid old Icarus string-concatenation UTF8 escaping.
   for(k=0;k<600;k=k+1)begin
    n=k<512?2048+k:3072+k-512;
    case(k%3)0:disk[n]=8'he4;1:disk[n]=8'hbd;2:disk[n]=8'ha0;endcase
   end
   disk[3160]=10;
   disk[3161]=8'he5;disk[3162]=8'haf;disk[3163]=8'hb9;
   disk[3164]=8'he4;disk[3165]=8'hb8;disk[3166]=8'h8d;
   disk[3167]=8'he8;disk[3168]=8'hb5;disk[3169]=8'hb7;
   disk[3170]=8'hef;disk[3171]=8'hbc;disk[3172]=8'h81;
  end
  repeat(5)@(negedge clk);rst=0;scan=1;@(negedge clk);scan=0;
  wait(done);repeat(4)@(negedge clk);
  if(scenario==4)begin
   if(total!=0||seen!=0||status!=14)$fatal(1,"all-invalid media did not enter error-only state: total=%0d seen=%0d state=%0d",total,seen,status);
  end else if(scenario==3)begin
   if(total!=1||seen!=1||dut.file_cluster[0]!=10)$fatal(1,"bad BMP skip %0d/%0d",total,seen);
   if(n0!=4||subtitle[0]!=8'h83||subtitle[1]!=8'h84||subtitle[2]!=8'h85||subtitle[3]!=8'h86)
    $fatal(1,"subtitle did not follow compacted image");
  end else begin
   if(total!=3||seen!=3)$fatal(1,"record count %0d/%0d",total,seen);
   if(dut.file_cluster[0]!=11||dut.file_cluster[1]!=10||dut.file_cluster[2]!=11)$fatal(1,"file name mapping");
   if(n1!=4||subtitle[128]!=8'h83||subtitle[129]!=8'h84||subtitle[130]!=8'h85||subtitle[131]!=8'h86)$fatal(1,"second caption scenario %d n=%d",scenario,n1);
  end
  if(scenario==0)begin
   if(n0!=4||subtitle[0]!=8'h80||subtitle[1]!=8'h81||subtitle[2]!=8'h82||subtitle[3]!=8'h86)$fatal(1,"first caption");
  end else if(scenario==1)begin
   if(n0!=128 || subtitle[127]!=8'h80)$fatal(1,"UTF8 truncation");
  end else if(scenario==2 && (n0!=3 || subtitle[0]!=8'h80 || subtitle[1]!="?" || subtitle[2]!="?"))
   $fatal(1,"BOM or unknown UTF8 codepoint count");
 end
 $display("PASS playlist: order, timing, modes, UTF8, fragmentation, truncation, EOF, bad-BMP skip, all-invalid error and subtitle remap");$finish;
 end
 initial begin #200000000;$fatal(1,"timeout");end
endmodule
