`timescale 1ns/1ps
module tb_bmp_ranges;
 reg clk=0;always #5 clk=~clk;
 reg rst=1;
 bmp_read dut(.clk(clk),.rst(rst),.scan_start(1'b0),.scan_start_sector(32'd0),
  .scan_max_sector(32'd0),.scan_target_count(3'd4),.load_start(1'b0),.load_sector(32'd0),
  .sd_init_done(1'b1),.bmp_width(16'd1024),.bmp_height(16'd600),.write_req_ack(1'b0),
  .audio_stream_enable(1'b0),.audio_fifo_afull(1'b0),.audio_scene(3'd0),.audio_restart(1'b0),
  .sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0));
 reg [87:0] name="GUQIN   BMP";
 integer i,match_cycles;
 task store_name(input integer candidate,input [87:0] full_name);
  integer word_index;
  begin
   dut.candidate_name_head[candidate]=full_name[87:72];
   for(word_index=0;word_index<8;word_index=word_index+1)
    dut.name_store.mem[candidate*8+word_index]=full_name[word_index*9+:9];
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst=0;@(negedge clk);
  if($bits(dut.candidate_size[0])!=22 || $bits(dut.file_size[0])!=22 ||
     $bits(dut.byte_count)!=22 || $bits(dut.pixel_offset)!=13 ||
     $bits(dut.row_stride)!=12 || $bits(dut.row_count)!=11)
      $fatal(1,"range widths");
  dut.candidate_count=8;dut.playlist_count=0;dut.pl_base_pos=5;
  dut.pl_duration=255;dut.pl_mode_text="ORIGINAL";dut.playlist_line=3;
  for(i=0;i<11;i=i+1)dut.pl_name[i]=name[(10-i)*8+:8];
  for(i=0;i<8;i=i+1)begin
   store_name(i,"OTHER   BMP");dut.candidate_cluster[i]=i+10;
   dut.candidate_size[i]=58;
  end
  store_name(1,name);store_name(7,name);
  dut.candidate_size[7]=3149824;
  dut.start_playlist_match(1'b0);#1;
  match_cycles=0;
  while(dut.name_match_busy)begin @(negedge clk);match_cycles=match_cycles+1;end
  if(match_cycles!=34)$fatal(1,"matcher latency %0d != 34 clocks",match_cycles);
  if(!dut.playlist_match_valid || dut.playlist_match_index!=7)$fatal(1,"last duplicate priority");
  if(dut.playlist_count!=1 || dut.file_cluster[0]!=17 || dut.file_size[0]!=3149824 ||
     dut.file_duration[0]!=255 || dut.file_scale[0]!=1 || dut.file_scene[0]!=1 ||
     dut.file_source_line[0]!=3)$fatal(1,"single playlist write changed semantics");
  @(negedge clk);
  for(i=0;i<64;i=i+1)dut.h[i]=0;
  dut.h[0]="B";dut.h[1]="M";dut.h[11]=16;dut.h[14]=40;
  dut.h[19]=4;dut.h[23]=4;dut.h[26]=1;dut.h[28]=24;
  dut.selected_size=3149824;
  #1;if(!dut.valid_bmp)$fatal(1,"maximum-size valid BMP rejected");
  dut.state=9;@(negedge clk);
  if(dut.pixel_offset!=4096 || dut.row_stride!=3072 || dut.row_data_bytes!=3072 ||
     dut.pixel_end!=3149824 || dut.source_width!=1024 || dut.source_height!=1024)
      $fatal(1,"maximum BMP dimensions truncated");
  dut.row_count=1024;dut.byte_count=3150335;#1;
  if(dut.row_count!=1024 || dut.byte_count!=3150335)$fatal(1,"terminal sector/count overflow");
  $display("PASS BMP ranges: 1024x1024, offset4096, stride3072, file3149824, final-sector count, last-duplicate PLAYLIST priority");
  $finish;
 end
endmodule
