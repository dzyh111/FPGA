`timescale 1ns/1ps
module tb_heritage_audio_reader;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,scan=0,audio_enable=0,restart=1,afull=0;
 reg [2:0] scene=0;
 wire ready,done,found,rd,pcm_wr,present,error,reset_busy;
 wire [31:0] lba,found_sector,pcm_word,samples;
 wire [2:0] total,found_scene;
 reg [7:0] rx=0;reg valid=0,ending=0;
 reg [7:0] disk[0:32767];
 integer busy=0,pos=0,base=0,k,found_count=0,words=0,expected_scene=0;
 reg checking=0;
 bmp_read dut(.clk(clk),.rst(rst),.ready(ready),.scan_start(scan),
  .scan_start_sector(32'd0),.scan_max_sector(32'd8191),.scan_target_count(3'd4),
  .scan_done(done),.scan_found_valid(found),.scan_found_sector(found_sector),
  .scan_found_total(total),.scan_found_scene(found_scene),
  .load_start(1'b0),.load_sector(32'd0),.sd_init_done(1'b1),
  .audio_stream_enable(audio_enable),.audio_fifo_afull(afull),
  .audio_scene(scene),.audio_restart(restart),.audio_reset_busy(reset_busy),
  .audio_sample_total(samples),.audio_file_present(present),.audio_format_error(error),
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
 task image(input integer cluster);integer a;begin
  a=cluster*512;disk[a]="B";disk[a+1]="M";put32(a+10,54);put32(a+14,40);
  put32(a+18,1);put32(a+22,1);disk[a+26]=1;disk[a+28]=24;
 end endtask
 task wav(input integer cluster,input integer identity);
  integer a,j;begin
   a=cluster*512;disk[a]="R";disk[a+1]="I";disk[a+2]="F";disk[a+3]="F";
   put32(a+4,836);disk[a+8]="W";disk[a+9]="A";disk[a+10]="V";disk[a+11]="E";
   disk[a+12]="f";disk[a+13]="m";disk[a+14]="t";disk[a+15]=" ";put32(a+16,16);
   disk[a+20]=1;disk[a+22]=2;put32(a+24,48000);put32(a+28,192000);
   disk[a+32]=4;disk[a+34]=16;disk[a+36]="d";disk[a+37]="a";disk[a+38]="t";disk[a+39]="a";
   put32(a+40,800);
   for(j=0;j<200;j=j+1)put32(a+44+j*4,32'h12340000+(identity<<8)+j);
   put32(512+cluster*4,cluster+1);put32(512+(cluster+1)*4,32'h0fffffff);
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
 always @(posedge clk)begin
  if(found)begin
   case(found_count)
    0:if(found_scene!==3)$fatal(1,"DIZI scene map");
    1:if(found_scene!==1)$fatal(1,"GUQIN scene map");
    2:if(found_scene!==4)$fatal(1,"TANGGU scene map");
    3:if(found_scene!==2)$fatal(1,"ERHU scene map");
   endcase
   found_count=found_count+1;
  end
  if(!rst && checking && pcm_wr)begin
   if(pcm_word!==(32'h12340000+(expected_scene<<8)+(words%200)))
     $fatal(1,"scene %0d word %0d got %h",expected_scene,words,pcm_word);
   words=words+1;
  end
 end
 task select_scene(input integer identity);
  begin
   @(negedge clk);checking=0;restart=1;scene=identity;
   repeat(3)@(negedge clk);
   if(!reset_busy)$fatal(1,"restart did not assert busy");
   repeat(8)@(negedge clk);restart=0;
   wait(!reset_busy);@(negedge clk);
   words=0;expected_scene=identity;checking=1;audio_enable=1;
   wait(words>=205); // Cross the FAT chain and verify a gap-free file loop.
   if(samples!==200 || error || !present)$fatal(1,"WAV metadata");
  end
 endtask
 initial begin
  for(k=0;k<32768;k=k+1)disk[k]=0;
  disk[11]=0;disk[12]=2;disk[13]=1;disk[14]=1;disk[16]=1;
  put32(32,100000);put32(36,1);put32(44,2);disk[510]=8'h55;disk[511]=8'haa;
  entry(0,"DIZI    BMP",10,100);entry(1,"GUQIN   BMP",11,100);
  entry(2,"TANGGU  BMP",12,100);entry(3,"ERHU    BMP",13,100);
  entry(4,"111     WAV",20,844);entry(5,"GUQIN   WAV",30,844);
  entry(6,"ERHU    WAV",40,844);entry(7,"DIZI    WAV",50,844);
  entry(8,"TANGGU  WAV",60,844);
  image(10);image(11);image(12);image(13);
  wav(20,0);wav(30,1);wav(40,2);wav(50,3);wav(60,4);
  repeat(5)@(negedge clk);rst=0;scan=1;@(negedge clk);scan=0;wait(done);
  if(total!==4 || found_count!=4)$fatal(1,"scene discovery");
  select_scene(1);select_scene(2);select_scene(3);select_scene(4);select_scene(0);
  @(negedge clk);checking=0;restart=1;
  repeat(3)@(negedge clk);
  repeat(600)begin @(negedge clk);if(pcm_wr)$fatal(1,"old PCM escaped restart");end
  if(!reset_busy)$fatal(1,"reset hold released early");
  $display("PASS heritage reader: basename scenes, five WAV choices, FAT crossing, sample totals, loop and in-flight cancellation");
  $finish;
 end
 initial begin #20000000;$fatal(1,"timeout state=%0d",dut.state);end
endmodule
