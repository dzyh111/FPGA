`timescale 1ns/1ps
module tb_subtitle_cn_parser;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,scan=0;
 wire ready,done,found,rd,wr;wire [31:0] lba,idx;
 wire [2:0] total;wire [3:0] status;
 wire [8:0] addr;wire [7:0] data,n0,n1,n2,n3;
 reg [7:0] rx=0;reg valid=0,ending=0;
 bmp_read dut(.clk(clk),.rst(rst),.ready(ready),.scan_start(scan),
 .scan_start_sector(32'd0),.scan_max_sector(32'd8191),.scan_target_count(3'd4),
 .scan_done(done),.scan_found_valid(found),.scan_found_sector(idx),.scan_found_total(total),
 .subtitle_wr_en(wr),.subtitle_wr_addr(addr),.subtitle_wr_data(data),
 .subtitle_len0(n0),.subtitle_len1(n1),.subtitle_len2(n2),.subtitle_len3(n3),
 .load_start(1'b0),.load_sector(32'd0),.sd_init_done(1'b1),.state_code(status),
 .bmp_width(16'd640),.bmp_height(16'd480),.write_req_ack(1'b0),
 .sd_sec_read(rd),.sd_sec_read_addr(lba),.sd_sec_read_data(rx),
 .sd_sec_read_data_valid(valid),.sd_sec_read_end(ending));
 reg [7:0] disk[0:8191],subtitle[0:511],text[0:1023];
 reg [7:0] fixture[0:1023],expected[0:255],utf8[0:95];
 integer pos=0,base=0,busy=0,seen=0,k,j,scenario,byte_gap=0,txtlen=0,writes=0;
 integer fixture_len,reads4=0,reads6=0;
 task put32(input integer a,input integer v);
 begin disk[a]=v;disk[a+1]=v>>8;disk[a+2]=v>>16;disk[a+3]=v>>24;end endtask
 task entry(input integer slot,input [87:0] name,input integer cluster,input integer size);
 integer a,j;begin a=1024+32*slot;
  for(j=0;j<11;j=j+1)disk[a+j]=name[(10-j)*8+:8];
  disk[a+11]=32;disk[a+26]=cluster;disk[a+27]=cluster>>8;put32(a+28,size);
 end endtask
 task bmp_header(input integer lba);integer a;begin
  a=lba*512;disk[a]="B";disk[a+1]="M";put32(a+10,54);put32(a+14,40);
  put32(a+18,640);put32(a+22,480);disk[a+26]=1;disk[a+28]=24;
 end endtask
 task append(input [7:0] b);begin text[txtlen]=b;txtlen=txtlen+1;end endtask
 task append_glyph(input integer id);begin append(utf8[3*id]);append(utf8[3*id+1]);append(utf8[3*id+2]);end endtask
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
   if(lba==4)reads4=reads4+1;if(lba==6)reads6=reads6+1;
  end
 end
 always @(posedge clk)if(!rst)begin
  if(wr)begin subtitle[addr]=data;writes=writes+1;end
  if(found)begin if(idx!=seen)$fatal(1,"index order");seen=seen+1;end
  if(status==14)$fatal(1,"reader error scenario=%0d state=%0d cluster=%0d",scenario,dut.state,dut.cluster);
 end
 initial begin
  $readmemh("sim/subtitle_cn_fixture.hex",fixture);
  $readmemh("sim/subtitle_cn_expected.hex",expected);
  $readmemh("sim/subtitle_cn_utf8.hex",utf8);
  fixture_len={fixture[3],fixture[2],fixture[1],fixture[0]};
  for(k=0;k<32;k=k+1)
   if(dut.subtitle_glyph(utf8[3*k],utf8[3*k+1],utf8[3*k+2])!==128+k)
    $fatal(1,"UTF8 function mapping id=%0d",k);
  if(dut.subtitle_glyph(8'he5,8'ha4,8'ha9)!="?")$fatal(1,"unsupported Chinese did not map to '?'");
  for(scenario=0;scenario<5;scenario=scenario+1)begin
   rst=1;seen=0;writes=0;txtlen=0;reads4=0;reads6=0;
   for(k=0;k<8192;k=k+1)disk[k]=0;
   for(k=0;k<512;k=k+1)subtitle[k]=0;
   disk[11]=0;disk[12]=2;disk[13]=1;disk[14]=1;disk[16]=1;
   put32(32,100000);put32(36,1);put32(44,2);disk[510]=8'h55;disk[511]=8'haa;
   entry(0,"GUQIN   BMP",10,921654);entry(1,"ERHU    BMP",11,921654);
   entry(2,"DIZI    BMP",12,921654);entry(3,"TANGGU  BMP",13,921654);
   for(k=10;k<14;k=k+1)bmp_header(k);
   if(scenario==1)begin
    append(8'hef);append(8'hbb);append(8'hbf);
    for(k=0;k<32;k=k+1)append_glyph(k);
    append(13);append(10);
    append(8'he5);append(8'ha4);append(8'ha9); // Unsupported CJK, one slot.
    append(8'hc3);append(8'ha9); // Unsupported two-byte character, one slot.
    append(8'hf0);append(8'h9f);append(8'h98);append(8'h80); // Four-byte, one slot.
    append(10);for(k=0;k<7;k=k+1)append_glyph(k); // EOF without newline.
   end else if(scenario==2)begin
    for(k=0;k<63;k=k+1)append_glyph(0);append(10);
    for(k=0;k<63;k=k+1)append_glyph(1);append(10);
    for(k=0;k<43;k=k+1)append_glyph(7);append(" ");append(" ");
    if(txtlen!=511)$fatal(1,"boundary fixture offset");
    append_glyph(31);append(10);
    for(k=0;k<160;k=k+1)append_glyph(2); // Truncate to 128 complete characters.
   end else begin
    for(k=0;k<fixture_len;k=k+1)append(fixture[k+4]);
   end
   if(scenario==3)begin
    entry(4,"HELLO   TXT",7,5);entry(5,"TEXT    TXT",4,txtlen);
    disk[3584]="W";disk[3585]="R";disk[3586]="O";disk[3587]="N";disk[3588]="G";
   end else entry(4,scenario==4?"HELLO   TXT":"TEXT    TXT",4,txtlen);
   put32(512+4*4,6);put32(512+4*6,32'h0fffffff);
   for(k=0;k<txtlen;k=k+1)disk[k<512?2048+k:3072+k-512]=text[k];
   repeat(5)@(negedge clk);rst=0;scan=1;@(negedge clk);scan=0;
   wait(done);repeat(4)@(negedge clk);
   if(total!=4||seen!=4)$fatal(1,"four image mapping failed");
   if(scenario==1)begin
    if(n0!=32||n1!=3||n2!=7||n3!=0||writes!=42)$fatal(1,"BOM/unsupported/EOF slot counts %0d %0d %0d %0d writes%0d",n0,n1,n2,n3,writes);
    for(k=0;k<32;k=k+1)if(subtitle[k]!==128+k)$fatal(1,"glyph id %0d misdecoded",k);
    for(k=128;k<131;k=k+1)if(subtitle[k]!="?")$fatal(1,"unsupported slot %0d",k);
    for(k=0;k<7;k=k+1)if(subtitle[256+k]!==128+k)$fatal(1,"legacy greeting changed");
   end else if(scenario==2)begin
    if(n0!=63||n1!=63||n2!=46||n3!=128||writes!=300||reads4!=1||reads6!=1)
     $fatal(1,"fragmentation/truncation counts %0d/%0d/%0d/%0d writes%0d reads%0d,%0d",n0,n1,n2,n3,writes,reads4,reads6);
    for(k=0;k<63;k=k+1)if(subtitle[k]!==8'h80||subtitle[128+k]!==8'h81)$fatal(1,"boundary prefix changed");
    for(k=0;k<43;k=k+1)if(subtitle[256+k]!==8'h87)$fatal(1,"new glyph prefix changed");
    if(subtitle[299]!=" "||subtitle[300]!=" "||subtitle[301]!==8'h9f)$fatal(1,"split UTF8 at byte511 did not decode once");
    for(k=0;k<128;k=k+1)if(subtitle[384+k]!==8'h82)$fatal(1,"128-char truncation data changed");
   end else begin
    if(n0!=16||n1!=16||n2!=16||n3!=16||writes!=64)$fatal(1,"introduction lengths");
    for(k=0;k<4;k=k+1)for(j=0;j<16;j=j+1)
     if(subtitle[128*k+j]!==expected[64*k+j])$fatal(1,"introduction scene%0d char%0d mismatch",k,j);
   end
  end
  $display("PASS subtitle UTF8 CN32 fallback: all 32 mappings, BOM/CRLF/EOF, unsupported UTF8, fragmented FAT clusters, 128-char truncation, TEXT priority and HELLO fallback");
  $finish;
 end
 initial begin #120000000;$fatal(1,"CN subtitle parser timeout");end
endmodule
