`timescale 1ns/1ps
module tb_wav_reader;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,scan=0,audio_enable=0;
 wire ready,done,found,rd,pcm_wr,audio_present,audio_error;
 wire [31:0] lba,found_sector,pcm_word;wire [2:0] total;wire [3:0] status;
 reg [7:0] rx=0;reg valid=0,ending=0;
 reg [7:0] disk[0:8191];integer busy=0,pos=0,base=0,k,words=0;
 bmp_read dut(.clk(clk),.rst(rst),.ready(ready),.scan_start(scan),
  .scan_start_sector(32'd0),.scan_max_sector(32'd8191),.scan_target_count(3'd4),
  .scan_done(done),.scan_found_valid(found),.scan_found_sector(found_sector),
  .scan_found_total(total),.load_start(1'b0),.load_sector(0),.sd_init_done(1'b1),
  .audio_stream_enable(audio_enable),.audio_fifo_afull(1'b0),
  .audio_scene(3'd0),.audio_restart(1'b0),
  .audio_file_present(audio_present),.audio_format_error(audio_error),
  .audio_pcm_wr(pcm_wr),.audio_pcm_word(pcm_word),
  .bmp_width(16'd640),.bmp_height(16'd480),.write_req_ack(1'b0),
  .sd_sec_read(rd),.sd_sec_read_addr(lba),.sd_sec_read_data(rx),
  .sd_sec_read_data_valid(valid),.sd_sec_read_end(ending));
 task put32(input integer a,input integer v);begin
  disk[a]=v;disk[a+1]=v>>8;disk[a+2]=v>>16;disk[a+3]=v>>24;
 end endtask
 task entry(input integer slot,input [87:0] name,input integer cluster,input integer size);
  integer j,a;begin a=1024+slot*32;
   for(j=0;j<11;j=j+1)disk[a+j]=name[(10-j)*8+:8];
   disk[a+11]=32;disk[a+26]=cluster;disk[a+27]=cluster>>8;put32(a+28,size);
  end
 endtask
 always @(negedge clk)begin
  valid=0;ending=0;
  if(rst)begin busy=0;pos=0;end
  else if(busy==1)begin
   if(pos<512)begin rx=disk[base+pos];valid=1;pos=pos+1;end
   else begin ending=1;busy=2;end
  end else if(busy==2)begin if(!rd)busy=0;end
  else if(rd)begin busy=1;pos=0;base=lba*512;end
 end
 always @(posedge clk)if(!rst && pcm_wr)begin
  if(words==0 && pcm_word!==32'h56781234)$fatal(1,"first PCM %h",pcm_word);
  if(words==1 && pcm_word!==32'hdef09abc)$fatal(1,"second PCM %h",pcm_word);
  words=words+1;if(words==2)audio_enable=0;
 end
 initial begin
  for(k=0;k<8192;k=k+1)disk[k]=0;
  disk[11]=0;disk[12]=2;disk[13]=1;disk[14]=1;disk[16]=1;
  put32(32,100000);put32(36,1);put32(44,2);disk[510]=8'h55;disk[511]=8'haa;
  entry(0,"IMG0    BMP",10,100);entry(1,"111     WAV",12,512);
  disk[10*512]="B";disk[10*512+1]="M";put32(10*512+10,54);put32(10*512+14,40);
  put32(10*512+18,1);put32(10*512+22,1);disk[10*512+26]=1;disk[10*512+28]=24;
  base=12*512;disk[base]="R";disk[base+1]="I";disk[base+2]="F";disk[base+3]="F";
  disk[base+8]="W";disk[base+9]="A";disk[base+10]="V";disk[base+11]="E";
  disk[base+12]="f";disk[base+13]="m";disk[base+14]="t";disk[base+15]=" ";put32(base+16,16);
  disk[base+20]=1;disk[base+22]=2;put32(base+24,48000);put32(base+28,192000);
  disk[base+32]=4;disk[base+34]=16;disk[base+36]="d";disk[base+37]="a";disk[base+38]="t";disk[base+39]="a";put32(base+40,8);
  disk[base+44]=8'h34;disk[base+45]=8'h12;disk[base+46]=8'h78;disk[base+47]=8'h56;
  disk[base+48]=8'hbc;disk[base+49]=8'h9a;disk[base+50]=8'hf0;disk[base+51]=8'hde;
  repeat(5)@(negedge clk);rst=0;scan=1;@(negedge clk);scan=0;wait(done);
  if(total!=1 || !audio_present)$fatal(1,"media discovery");
  audio_enable=1;wait(words==2);wait(ready);repeat(5)@(negedge clk);
  if(audio_error)$fatal(1,"valid WAV rejected");
  $display("PASS wav_reader: FAT32 111.WAV discovery, RIFF validation, stereo PCM streaming");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
