`timescale 1ns/1ps
// Real FAT32 root/playlist/fragmented cluster transactions, not forced states.
module tb_gallery_pack_formats;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,scan=0,audio_enable=0,audio_restart=0,audio_afull=0;
 reg [2:0] font_scene=0;reg [1:0] font_index=0;
 reg font_cache_idle=1,font_quiet_ack=0,ack_enabled=1,force_fresh_ack=0;
 wire font_quiet_request;
 integer mock_frame_div=0,quiet_frames=0;
 wire ready,done,found,rd,sub_wr,font_wr,font_ready,packed_subtitles,audio_reset,pcm_wr;
 wire [31:0] lba,idx;wire [2:0] total,found_scene,loaded_scene;wire [1:0] loaded_index;
 wire [3:0] status;wire [8:0] sub_addr;wire [7:0] sub_data,n0,n1,n2,n3;
 wire [9:0] font_addr;wire [17:0] font_data;wire font_format24;
 reg [7:0] rx=0;reg valid=0,ending=0;
 bmp_read dut(.clk(clk),.rst(rst),.ready(ready),.scan_start(scan),
  .scan_start_sector(32'd0),.scan_max_sector(32'd511),.scan_target_count(3'd4),
  .scan_done(done),.scan_found_valid(found),.scan_found_sector(idx),.scan_found_total(total),.scan_found_scene(found_scene),
  .subtitle_wr_en(sub_wr),.subtitle_wr_addr(sub_addr),.subtitle_wr_data(sub_data),
  .subtitle_len0(n0),.subtitle_len1(n1),.subtitle_len2(n2),.subtitle_len3(n3),
  .font_scene_request(font_scene),.font_index_request(font_index),.font_wr_en(font_wr),
  .font_cache_idle(font_cache_idle),.font_quiet_ack(font_quiet_ack),.font_quiet_request(font_quiet_request),
  .font_wr_addr(font_addr),.font_wr_data(font_data),.font_ready(font_ready),.font_format24(font_format24),
  .font_loaded_scene(loaded_scene),.font_loaded_index(loaded_index),.packed_subtitles(packed_subtitles),
  .audio_stream_enable(audio_enable),.audio_fifo_afull(audio_afull),.audio_scene(3'd0),
  .audio_restart(audio_restart),.audio_reset_busy(audio_reset),.audio_pcm_wr(pcm_wr),
  .load_start(1'b0),.load_sector(32'd0),.sd_init_done(1'b1),.cover_cancel(1'b0),
  .state_code(status),.bmp_width(16'd1),.bmp_height(16'd1),.write_req_ack(1'b0),
  .sd_sec_read(rd),.sd_sec_read_addr(lba),.sd_sec_read_data(rx),
  .sd_sec_read_data_valid(valid),.sd_sec_read_end(ending));
 reg [7:0] disk[0:262143],pack[0:14335],codes[0:511],lengths[0:3],subtitles[0:511];
 reg [17:0] font_mem[0:1023];
 reg use24;integer record_bytes,record_sectors,pack_bytes;
 integer scenario,spc,seen=0,pos=0,base=0,busy=0,byte_gap=0,k,j,a,cluster_no;
 integer case_select=-1,run_cases=0;
 integer font_writes=0,expected_font_scene=1,pack_reads=0,pcm_words=0,truncated_lba=-1;
 integer expected_scene[0:3];
 string playlist,caption;
 function [17:0] pattern(input integer scene_id,word_id);
  pattern=((scene_id<<15)^(word_id*123)^18'h1abcd)&(use24?18'h3ffff:18'h0ffff);
 endfunction
 task make_pack;
 integer scene_id,n,at,value;
 begin
  record_sectors=use24?7:5;record_bytes=record_sectors*512;pack_bytes=4*record_bytes;
  for(n=0;n<14336;n=n+1)pack[n]=0;
  for(n=0;n<512;n=n+1)codes[n]=0;
  for(scene_id=1;scene_id<=4;scene_id=scene_id+1)begin
   at=(scene_id-1)*record_bytes;
   pack[at]="S";pack[at+1]="U";pack[at+2]="B";pack[at+3]=use24?"2":"1";
   pack[at+4]=scene_id;pack[at+5]=4;pack[at+6]=use24?32:64;lengths[scene_id-1]=4;
   codes[(scene_id-1)*128]=use24?8'he0:8'h80;
   codes[(scene_id-1)*128+1]=use24?8'hff:8'hbf;
   codes[(scene_id-1)*128+2]=use24?8'hc0:"A";
   codes[(scene_id-1)*128+3]=use24?8'hc1:",";
   for(n=0;n<4;n=n+1)pack[at+16+n]=codes[(scene_id-1)*128+n];
   for(n=0;n<1024;n=n+1)begin
    value=pattern(scene_id,n);
    pack[at+512+n*(use24?3:2)]=value;
    pack[at+513+n*(use24?3:2)]=value>>8;
    if(use24)pack[at+514+3*n]=value>>16;
   end
  end
 end endtask
 function integer clba(input integer c);clba=2+(c-2)*spc;endfunction
 function integer pack_byte_addr(input integer offset);
   pack_byte_addr=(clba(20+3*((offset/512)/spc))+(offset/512)%spc)*512+offset%512;
 endfunction
 task put32(input integer at,value);
 begin disk[at]=value;disk[at+1]=value>>8;disk[at+2]=value>>16;disk[at+3]=value>>24;end endtask
 task entry(input integer slot,input [87:0] name,input integer c,size);
 integer at,n;begin at=clba(2)*512+slot*32;
  for(n=0;n<11;n=n+1)disk[at+n]=name[(10-n)*8+:8];
  disk[at+11]=32;disk[at+26]=c;disk[at+27]=c>>8;put32(at+28,size);
 end endtask
 task bmp_header(input integer c);
 integer at;begin at=clba(c)*512;disk[at]="B";disk[at+1]="M";put32(at+10,54);put32(at+14,40);
 put32(at+18,1);put32(at+22,1);disk[at+26]=1;disk[at+28]=24;end endtask
 task make_disk;
 integer n,at,needed;begin
  for(n=0;n<262144;n=n+1)disk[n]=0;
  for(n=0;n<512;n=n+1)subtitles[n]=8'hfe;
  disk[11]=0;disk[12]=2;disk[13]=spc;disk[14]=1;disk[16]=1;
  put32(32,100000);put32(36,1);put32(44,2);disk[510]=8'h55;disk[511]=8'haa;
  entry(0,"GUQIN   BMP",4,100);entry(1,"ERHU    BMP",5,100);
  entry(2,"DIZI    BMP",6,100);entry(3,"TANGGU  BMP",7,100);
  for(n=4;n<=7;n=n+1)bmp_header(n);
  if(scenario==1)begin
   playlist={"TANGGU.BMP,16,FIT",8'd10,"DIZI.BMP,16,FIT",8'd10,"GUQIN.BMP,16,FIT",8'd10,"ERHU.BMP,16,FIT",8'd10};
   expected_scene[0]=4;expected_scene[1]=3;expected_scene[2]=1;expected_scene[3]=2;
  end else if(scenario==2)begin
   playlist={"ERHU.BMP,16,FIT",8'd10,"GUQIN.BMP,16,FIT",8'd10,"ERHU.BMP,16,FIT",8'd10,"TANGGU.BMP,16,FIT",8'd10};
   expected_scene[0]=2;expected_scene[1]=1;expected_scene[2]=2;expected_scene[3]=4;
  end else begin
   playlist={"GUQIN.BMP,16,FIT",8'd10,"ERHU.BMP,16,FIT",8'd10,"DIZI.BMP,16,FIT",8'd10,"TANGGU.BMP,16,FIT",8'd10};
   for(n=0;n<4;n=n+1)expected_scene[n]=n+1;
  end
  entry(4,"PLAYLISTTXT",8,playlist.len());
  for(n=0;n<playlist.len();n=n+1)disk[clba(8)*512+n]=playlist[n];
  caption={"fallback0",8'd10,"fallback1",8'd10,"fallback2",8'd10,"fallback3",8'd10};
  if(scenario==7)begin
   caption="";for(n=0;n<140;n=n+1)caption={caption,"A"};caption={caption,8'd10};
   for(n=0;n<128;n=n+1)caption={caption,"B"};caption={caption,8'd10};
   for(n=0;n<128;n=n+1)caption={caption,"C"};caption={caption,8'd10};
   for(n=0;n<128;n=n+1)caption={caption,"D"};
  end
  entry(5,"TEXT    TXT",9,caption.len());
  put32(512+9*4,11);put32(512+11*4,32'h0fffffff);
  for(n=0;n<caption.len();n=n+1)begin
   at=(n<spc*512)?clba(9)*512+n:clba(11)*512+n-spc*512;disk[at]=caption[n];
  end
  entry(6,"SUBS    BIN",20,scenario==7?pack_bytes-1:pack_bytes);
  needed=(4*record_sectors+spc-1)/spc;
  for(n=0;n<needed;n=n+1)put32(512+(20+3*n)*4,n==needed-1?32'h0fffffff:23+3*n);
  for(n=0;n<pack_bytes;n=n+1)disk[pack_byte_addr(n)]=pack[n];
  if(scenario==3)disk[pack_byte_addr(2*record_bytes+4)]=1; // Wrong record scene.
  if(scenario==5)truncated_lba=pack_byte_addr(512)/512;
  if(scenario==6)put32(512+20*4,32'h0fffffff);
  if(scenario==9)disk[pack_byte_addr(514)]=8'h80; // Reserved high bits.
  if(scenario==10)disk[pack_byte_addr(6)]=33; // Native glyph count overflow.
  if(scenario==11)disk[pack_byte_addr(record_bytes+3)]="1"; // Mixed record format.
  if(scenario==12)disk[pack_byte_addr(3)]="2"; // SUB1-sized file, SUB2 magic.
  if(scenario==13)disk[pack_byte_addr(16)]=8'ha0; // Native glyph index alias.
  if(scenario==14)disk[pack_byte_addr(3*record_bytes+514)]=8'hfc; // Bad unrendered page.
  if(scenario==15)disk[pack_byte_addr(16)]=8'h80; // Old native tag is now illegal.
  if(scenario==16)disk[pack_byte_addr(6)]=31; // FF must not alias a declared 31-glyph page.
  entry(7,"111     WAV",10,512);
  at=clba(10)*512;
  disk[at]="R";disk[at+1]="I";disk[at+2]="F";disk[at+3]="F";
  disk[at+8]="W";disk[at+9]="A";disk[at+10]="V";disk[at+11]="E";
  disk[at+12]="f";disk[at+13]="m";disk[at+14]="t";disk[at+15]=" ";put32(at+16,16);
  disk[at+20]=1;disk[at+22]=2;put32(at+24,48000);put32(at+28,192000);
  disk[at+32]=4;disk[at+34]=16;disk[at+36]="d";disk[at+37]="a";disk[at+38]="t";disk[at+39]="a";
  put32(at+40,468);for(n=44;n<512;n=n+1)disk[at+n]=n;
 end endtask

 // Model the pixel-domain frame boundary: normally acknowledge a new quiet
 // epoch only after five mock frames with the old subtitle cache idle.
 always @(posedge clk)begin
  if(rst)begin font_quiet_ack<=0;mock_frame_div<=0;quiet_frames<=0;end
  else begin
   mock_frame_div<=mock_frame_div==15?0:mock_frame_div+1;
   if(force_fresh_ack)begin font_quiet_ack<=font_quiet_request;quiet_frames<=0;end
   else if(!font_cache_idle || !ack_enabled)quiet_frames<=0;
   else if(mock_frame_div==15 && font_quiet_ack!=font_quiet_request)begin
    if(quiet_frames==4)begin font_quiet_ack<=font_quiet_request;quiet_frames<=0;end
    else quiet_frames<=quiet_frames+1;
   end
  end
 end

 always @(negedge clk)begin
  valid=0;ending=0;
  if(rst)begin busy=0;pos=0;byte_gap=0;end
  else if(busy==1)begin
   if(byte_gap!=0)byte_gap=byte_gap-1;
   else if(pos<(base/512==truncated_lba?384:512))begin rx=disk[base+pos];valid=1;pos=pos+1;byte_gap=35;end
   else begin ending=1;busy=2;end
  end else if(busy==2)begin if(!rd)busy=0;end
  else if(rd)begin
   if(lba>=512)$fatal(1,"invalid LBA %0d",lba);
   busy=1;pos=0;base=lba*512;byte_gap=0;
   if(dut.after_rx==32 || dut.after_rx==33)begin
    if(!dut.pack_initial && (!font_cache_idle || font_quiet_ack!=font_quiet_request))$fatal(1,"pack read before quiet epoch acknowledged");
    pack_reads=pack_reads+1;
   end
  end
 end
 always @(posedge clk)if(!rst)begin
  if(status==14)$fatal(1,"optional pack caused image FAIL: scenario=%0d state=%0d",scenario,dut.state);
  if(sub_wr)subtitles[sub_addr]=sub_data;
  if(found)begin
   if(idx!==seen || found_scene!==expected_scene[seen])$fatal(1,"playlist mapping scenario=%0d slot=%0d",scenario,seen);
   seen=seen+1;
  end
  if(font_wr)begin
   if(font_ready)$fatal(1,"font cache published before final row");
   if(font_addr!==font_writes)$fatal(1,"font write order expected=%0d actual=%0d",font_writes,font_addr);
   if(font_data!==pattern(expected_font_scene,font_addr))$fatal(1,"font scene%0d word%0d got=%h expected=%h",expected_font_scene,font_addr,font_data,pattern(expected_font_scene,font_addr));
   font_mem[font_addr]=font_data;font_writes=font_writes+1;
   if(!dut.pack_initial && !audio_reset)$fatal(1,"runtime font transaction did not hold audio FIFO reset");
   if(!dut.pack_initial && (!font_cache_idle || font_quiet_ack!=font_quiet_request))$fatal(1,"font cache write before display idle/fresh acknowledgement");
  end
  if(pcm_wr)begin
   if(audio_reset || dut.pack_rx)$fatal(1,"PCM leak during font load/reset");
   pcm_words=pcm_words+1;
  end
 end
 task check_page(input integer index,scene_id);
 integer n,len;begin
  len=lengths[scene_id-1];
  case(index)0:if(n0!==len)$fatal(1,"length0 %0d/%0d",n0,len);1:if(n1!==len)$fatal(1,"length1");
   2:if(n2!==len)$fatal(1,"length2");3:if(n3!==len)$fatal(1,"length3");endcase
  for(n=0;n<len;n=n+1)if(subtitles[index*128+n]!==codes[(scene_id-1)*128+n])
   $fatal(1,"subtitle scenario%0d slot%0d scene%0d char%0d got=%h expected=%h",scenario,index,scene_id,n,subtitles[index*128+n],codes[(scene_id-1)*128+n]);
 end endtask
 task request_font(input integer scene_id,index);
 integer before_reads,timeout,n;begin
  before_reads=pack_reads;font_writes=0;expected_font_scene=scene_id;
  if(scenario==0 && scene_id==4)ack_enabled=0;
  @(negedge clk);font_scene=scene_id;font_index=index;
  if(scenario==0 && scene_id==4)begin
   wait(!font_ready);wait(font_quiet_request!=font_quiet_ack);
   // Idle from the previous epoch is stale: fresh ack is mandatory.
   repeat(100)begin @(negedge clk);
    if(pack_reads!=before_reads || font_writes!=0 || rd)$fatal(1,"stale-high idle bypassed fresh quiet acknowledgement");
   end
   // Independently exercise the idle gate with a fresh ack already present.
   font_cache_idle=0;force_fresh_ack=1;
   wait(font_quiet_request==font_quiet_ack);
   repeat(32)begin @(negedge clk);
    if(pack_reads!=before_reads || font_writes!=0 || rd)$fatal(1,"fresh ack bypassed busy cache protection");
   end
   force_fresh_ack=0;font_cache_idle=1;ack_enabled=1;
  end
  timeout=0;
  while(!(font_ready && loaded_scene==scene_id && loaded_index==index))begin
   @(negedge clk);timeout=timeout+1;if(timeout>1500000)$fatal(1,"font request timeout scene%0d index%0d state%0d",scene_id,index,dut.state);
  end
  if(font_writes!=1024 || font_format24!==use24)$fatal(1,"font word count/format %0d/%0b",font_writes,font_format24);
  if(pack_reads-before_reads!=scene_id*record_sectors)$fatal(1,"seek read count scene%0d got%0d",scene_id,pack_reads-before_reads);
  check_page(index,scene_id);
  before_reads=pack_reads;repeat(40)@(negedge clk);
  if(pack_reads!=before_reads)$fatal(1,"stable font epoch continuously reloaded");
 end endtask

 initial begin
  if($value$plusargs("CASE_SELECT=%d",case_select))begin end
  // Tag-only follow-up: preserve the earlier full 15-case evidence, and
  // execute only cases directly affected by the E0..FF character tags.
  for(scenario=0;scenario<17;scenario=scenario+1)begin
   if(case_select<0 || case_select==scenario || (case_select==100 &&
      (scenario==0 || scenario==8 || scenario==13 || scenario==15 || scenario==16)))begin
   run_cases=run_cases+1;
   use24=scenario!=8 && scenario!=12;make_pack;
   rst=1;scan=0;font_scene=0;font_index=0;audio_enable=0;audio_restart=0;audio_afull=0;
   font_cache_idle=1;ack_enabled=1;force_fresh_ack=0;
   seen=0;pack_reads=0;font_writes=0;expected_font_scene=1;pcm_words=0;truncated_lba=-1;
   spc=scenario==1?8:scenario==2?2:1;make_disk;
   repeat(5)@(negedge clk);rst=0;scan=1;@(negedge clk);scan=0;
   wait(done);repeat(5)@(negedge clk);
   if(total!=4 || seen!=4)$fatal(1,"pack scan lost valid images scenario%0d total%0d seen%0d candidate%0d playlist%0d",scenario,total,seen,dut.candidate_count,dut.playlist_count);
   if(scenario==3 || scenario==5 || scenario==6 || scenario>=9)begin
    if(packed_subtitles || font_ready || n0!=0 || n1!=0 || n2!=0 || n3!=0)$fatal(1,"bad pack was not disabled cleanly");
   end else if(scenario==7)begin
    if(packed_subtitles || n0!=128 || n1!=128 || n2!=128 || n3!=128)$fatal(1,"wrong-size pack damaged UTF8 fallback");
    for(k=0;k<512;k=k+1)if(subtitles[k]!==((k/128)+65))$fatal(1,"128-character fallback page mismatch");
   end else begin
    if(!packed_subtitles || !font_ready || loaded_scene!=1 || loaded_index!=0 || font_writes!=1024 || pack_reads!=4*record_sectors || font_format24!==use24)$fatal(1,"initial pack publication/counts");
    for(k=0;k<4;k=k+1)if(!(scenario==2 && k==2))check_page(k,expected_scene[k]);
    request_font(4,scenario==1?0:3);request_font(2,scenario==1?3:scenario==2?0:1);
    if(scenario==2)request_font(2,2); // Same scene, distinct playlist page.
    if(scenario==4)begin
     disk[pack_byte_addr(3*record_bytes)]="X";
     @(negedge clk);font_scene=4;font_index=3;
     wait(!font_ready);wait(!packed_subtitles);wait(ready);
     if(n0!=0 || n1!=0 || n2!=0 || n3!=0)$fatal(1,"runtime invalid header kept stale captions");
    end else if(scenario==0)begin
     // Request during a real active audio sector; controller restart drains
     // the transaction before the pack loader takes the SPI interface.
     audio_enable=1;wait(dut.state==2 && dut.after_rx==28 && pos>80);
     @(negedge clk);audio_restart=1;
     fork
      begin request_font(3,2);end
      begin repeat(3)@(negedge clk);audio_restart=0;end
     join
     audio_enable=0;
    end
   end
   $display("PASS gallery pack formats scenario%0d SUB%0d spc%0d fontwords%0d reads%0d",scenario,use24?2:1,spc,font_writes,pack_reads);
   end
  end
  if(run_cases==0)$fatal(1,"no matching CASE_SELECT %0d",case_select);
  $display("PASS gallery pack formats: %0d executed SUB1/SUB2 scenarios CASE_SELECT=%0d; native E0/FF and C0/C1 tags, exact18bit words, sector/FAT groups, fresh quiet/idle, legacy16bit compatibility, invalid tag and declared glyph-bound checks; earlier full-suite evidence retained separately",run_cases,case_select);
  $finish;
 end
 initial begin #700000000;$fatal(1,"gallery pack overall timeout scenario%0d state%0d",scenario,dut.state);end
endmodule
