`timescale 1ns/1ps
module tb_gallery_subtitle;
 reg clk=0;always #5 clk=~clk;
 reg wr_clk=0;always #7 wr_clk=~wr_clk;
 reg rst=1,wr_en=0,font_wr_en=0,font_ready=0,font_quiet_request=0;
 reg [8:0] wr_addr=0;reg [7:0] wr_data=0;
 reg [9:0] font_wr_addr=0;reg [15:0] font_wr_data=0;
 reg frame_tick=0,enable=1,show_picture=0,intro_pause=0,intro_restart=0;
 reg [1:0] image_index=0;
 reg [7:0] len0=0,len1=0,len2=0,len3=0;
 reg valid=0,sof=0,last=0;
 wire intro_done,intro_restart_ack;wire [1:0] intro_done_index;
 wire font_cache_idle,font_quiet_ack;
 wire out_valid,out_sof,out_last;wire [23:0] out_rgb;
 subtitle_overlay dut(.*,.rgb(24'h204060));
 reg [7:0] pack_bytes[0:10239],codes[0:511],lens[0:3];
 reg [4:0] ascii[0:1023];
 integer scene,n,piece,xx,yy,output_count,total_pixels=0,expected_scroll;
 integer gx,gy,lx,code,row,col,row_word,base,steps,saved_scroll,frames,full_frames,expected_frames;
 reg checking=0,ink;reg [23:0] expected_rgb;
 task tick;begin @(negedge clk);end endtask
 task frame;begin repeat(4)tick;frame_tick=1;tick;frame_tick=0;repeat(4)tick;end endtask
 task write_character(input integer address,input integer value);
 begin @(negedge wr_clk);wr_en=1;wr_addr=address;wr_data=value;
  @(negedge wr_clk);wr_en=0;end endtask
 task load_scene(input integer which);
 begin
  show_picture=0;font_ready=0;font_quiet_request=!font_quiet_request;
  repeat(4)tick;
  if(font_quiet_ack===font_quiet_request)$fatal(1,"font quiet token acknowledged without a video frame");
  frame;
  if(!font_cache_idle || font_quiet_ack!==font_quiet_request)$fatal(1,"font cache quiet handshake not drained");
  for(n=0;n<1024;n=n+1)begin
   @(negedge wr_clk);font_wr_en=1;font_wr_addr=n;
   font_wr_data={pack_bytes[which*2560+513+2*n],pack_bytes[which*2560+512+2*n]};
  end
  @(negedge wr_clk);font_wr_en=0;
  for(n=0;n<128;n=n+1)write_character(which*128+n,codes[which*128+n]);
  image_index=which;font_ready=1;show_picture=1;frame;frame;
 end endtask
 always @(negedge clk)if(checking && out_valid)begin
  gx=output_count%1024;gy=output_count/1024;
  lx=gx+expected_scroll-1024;ink=0;
  if(lx>=0 && lx<32*lens[scene])begin
   code=codes[scene*128+lx/32];col=(lx%32)/2;row=gy/2;
   if(code>=128 && code<192)begin
    base=scene*2560+512+2*((code-128)*16+row);
    row_word={pack_bytes[base+1],pack_bytes[base]};ink=(row_word>>(15-col))&1;
   end else if(col>=2 && col<12)ink=(ascii[code*8+row/2]>>(4-(col-2)/2))&1;
  end
  expected_rgb=(gx<6 || gx>=1018)?24'h204060:(ink?24'h101820:24'hc8d0d8);
  if(out_rgb!==expected_rgb || out_sof!==0 || out_last!==(gx==1023))
   $fatal(1,"gallery subtitle pixel scene=%0d piece=%0d xy=%0d,%0d got=%h want=%h",scene,piece,gx,gy,out_rgb,expected_rgb);
  output_count=output_count+1;total_pixels=total_pixels+1;
 end
 initial begin
  $readmemh("sim/gallery_subs_pack.hex",pack_bytes);
  $readmemh("sim/gallery_subtitle_codes.hex",codes);
  $readmemh("sim/gallery_subtitle_lengths.hex",lens);
  $readmemh("rtl/ascii_font_rows.hex",ascii);
  repeat(4)tick;rst=0;len0=lens[0];len1=lens[1];len2=lens[2];len3=lens[3];
  for(scene=0;scene<4;scene=scene+1)begin
   load_scene(scene);
   if(dut.scroll<512 || dut.scroll>513 || intro_done || intro_done_index!==scene[1:0])$fatal(1,"gallery scene entry");
   for(piece=0;piece<3;piece=piece+1)begin
    expected_scroll=1024+1024*piece;
    force dut.scroll=expected_scroll;
    dut.x=0;dut.y=560;output_count=0;checking=1;
    for(yy=0;yy<32;yy=yy+1)for(xx=0;xx<1024;xx=xx+1)begin valid=1;last=xx==1023;tick;end
    valid=0;last=0;repeat(5)tick;checking=0;release dut.scroll;
    if(output_count!=32768)$fatal(1,"pipeline output count");
   end
   intro_restart=!intro_restart;frame;
   if(dut.scroll!==512 || intro_done || intro_restart_ack!==intro_restart)$fatal(1,"restart did not clear completion/acknowledge epoch");
   // SW2 hides pixels, not timing. Pause freezes the two-step scroll phase.
   enable=0;frame;frame;saved_scroll=dut.scroll;
   frame;if(dut.scroll<=saved_scroll || dut.en_d)$fatal(1,"hidden subtitle did not progress");
   intro_pause=1;saved_scroll=dut.scroll;repeat(4)frame;
   if(dut.scroll!==saved_scroll || intro_done)$fatal(1,"paused subtitle advanced");
   intro_pause=0;enable=1;intro_restart=!intro_restart;frame;
   frames=0;
   while(!intro_done && frames<4000)begin frame;frames=frames+1;end
   if(!intro_done || intro_done_index!==scene[1:0] || dut.scroll<448+32*lens[scene] || dut.scroll>449+32*lens[scene])
    $fatal(1,"AUTO readiness missing or not at trailing edge x575..576 scene=%0d scroll=%0d",scene,dut.scroll);
   expected_frames=(2*(32*lens[scene]-64)+2)/3;
   if(frames!=expected_frames)$fatal(1,"AUTO readiness timing scene=%0d frames=%0d expected=%0d",scene,frames,expected_frames);
   if(1024+32*lens[scene]-dut.scroll<=512)$fatal(1,"AUTO readiness did not precede screen centre");
   intro_pause=1;saved_scroll=dut.scroll;repeat(4)frame;
   if(dut.scroll!==saved_scroll || !intro_done)$fatal(1,"pause lost latched readiness or advanced scroll");
   intro_pause=0;full_frames=frames;
   while(dut.scroll!=0 && full_frames<4000)begin
    frame;full_frames=full_frames+1;
    if(!intro_done || intro_done_index!==scene[1:0])$fatal(1,"manual tail lost tagged readiness");
   end
   if(dut.scroll!==0 || full_frames!=(2*(512+32*lens[scene])+2)/3)
    $fatal(1,"manual loop shortened scene=%0d full_frames=%0d",scene,full_frames);
   repeat(3)frame;if(!intro_done)$fatal(1,"completion must remain latched during manual repeat");
  end
  // A loader can invalidate the ready signal in the middle of an active
  // scan line. It must not receive permission until a frame boundary masks
  // the subtitle and the full three-stage RGB pipeline has drained.
  if(font_cache_idle)$fatal(1,"font cache should be visible before quiet test");
  valid=1;last=0;dut.x=512;dut.y=560;
  repeat(5)tick;
  font_ready=0;font_quiet_request=!font_quiet_request;
  repeat(5)tick;
  if(font_cache_idle || font_quiet_ack===font_quiet_request)$fatal(1,"midframe invalidation bypassed quiet token");
  frame_tick=1;tick;frame_tick=0;
  if(!font_cache_idle || font_quiet_ack===font_quiet_request || intro_done)$fatal(1,"quiet request frame was not masked/reset");
  tick;if(font_quiet_ack===font_quiet_request)$fatal(1,"quiet acknowledged before drain cycle1");
  tick;if(font_quiet_ack===font_quiet_request)$fatal(1,"quiet acknowledged before drain cycle2");
  tick;
  if(font_quiet_ack!==font_quiet_request || out_rgb!==24'h204060)$fatal(1,"quiet drain did not remove old subtitle pixels");
  valid=0;repeat(4)tick;font_ready=1;frame;frame;
  // Custom page capacity is unchanged; readiness also precedes the centre.
  show_picture=0;frame;frame;len3=100;show_picture=1;frame;frame;
  intro_restart=!intro_restart;frame;frames=0;
  while(!intro_done && frames<4000)begin frame;frames=frames+1;end
  if(!intro_done || frames!=2091 || dut.scroll<3648 || dut.scroll>3649)$fatal(1,"100-character readiness timing %0d",frames);
  // Maximum page address511 and glyphIDbf must not alias page255/glyph1f.
  show_picture=0;frame;frame;len3=128;
  write_character(511,191);image_index=3;show_picture=1;font_ready=1;frame;frame;
  force dut.scroll=13'd5088;dut.x=0;dut.y=560;repeat(4)tick;
  if(dut.address!==511 || dut.code!==191)$fatal(1,"128-character page endpoint alias");
  release dut.scroll;intro_restart=!intro_restart;frame;
  frames=0;while(!intro_done && frames<4000)begin frame;frames=frames+1;end
  if(!intro_done || frames!=2688 || dut.scroll!==4544)$fatal(1,"128-character readiness timing %0d",frames);
  font_ready=0;frame;frame;
  if(intro_done || dut.scroll!==512 || dut.ready_d)$fatal(1,"unpublished font was not hidden/reset");
  $display("PASS gallery subtitle: four introductions, %0d exact output pixels with KaiTi, stronger contrast and border gutters, 3-clock RGB/markers, dual-clock font cache, atomic three-cycle quiet drain, AUTO at tail x575..576 before centre, hidden timing/pause/restart/tagged readiness, full manual loop retained,100/128-character/page511 endpoint",total_pixels);
  $finish;
 end
 initial begin #20000000;$fatal(1,"gallery subtitle timeout");end
endmodule
