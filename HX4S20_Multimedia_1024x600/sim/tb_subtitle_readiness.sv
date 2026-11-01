`timescale 1ns/1ps
module tb_subtitle_readiness;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,enable=1,show_picture=0,font_ready=0;
 reg font_quiet_request=0,intro_pause=0,intro_restart=0;
 reg [1:0] image_index=0;
 reg [7:0] len0=0,len1=0,len2=0,len3=0;
 wire intro_done,intro_restart_ack,font_cache_idle,font_quiet_ack;
 wire [1:0] intro_done_index;
 wire out_valid,out_sof,out_last;wire [23:0] out_rgb;
 subtitle_overlay dut(.wr_clk(clk),.wr_en(1'b0),.wr_addr(9'd0),.wr_data(8'd0),
  .font_wr_en(1'b0),.font_wr_addr(10'd0),.font_wr_data(16'd0),
  .font_ready(font_ready),.font_quiet_request(font_quiet_request),
  .clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(enable),.show_picture(show_picture),
  .intro_pause(intro_pause),.intro_restart(intro_restart),.image_index(image_index),
  .len0(len0),.len1(len1),.len2(len2),.len3(len3),
  .valid(1'b0),.sof(1'b0),.last(1'b0),.rgb(24'h345678),
  .intro_done(intro_done),.intro_done_index(intro_done_index),.intro_restart_ack(intro_restart_ack),
  .font_cache_idle(font_cache_idle),.font_quiet_ack(font_quiet_ack),
  .out_valid(out_valid),.out_sof(out_sof),.out_last(out_last),.out_rgb(out_rgb));
 integer checks=0,samples=0,n,length,model_scroll,model_half,model_ready;
 integer frames,ready_frame,expected_ready_frames,full_frames,paused,saved_scroll;
 integer lengths[0:8];
 task tick;begin @(negedge clk);end endtask
 task frame;begin repeat(4)tick;frame_tick=1;tick;frame_tick=0;repeat(4)tick;end endtask
 task configure(input integer size,input integer scene);
 begin
  show_picture=0;font_ready=0;frame;frame;
  len0=size;len1=size;len2=size;len3=size;image_index=scene;
  show_picture=1;font_ready=1;intro_pause=0;enable=1;frame;frame;
  intro_restart=!intro_restart;frame;
  if(dut.scroll!==512 || dut.scroll_half!==0 || intro_done ||
     intro_done_index!==scene[1:0] || intro_restart_ack!==intro_restart)
   $fatal(1,"configured epoch did not reset size=%0d scene=%0d",size,scene);
 end endtask
 initial begin
  lengths[0]=0;lengths[1]=1;lengths[2]=2;lengths[3]=3;lengths[4]=4;
  lengths[5]=40;lengths[6]=41;lengths[7]=100;lengths[8]=128;
  repeat(4)tick;rst=0;
  for(n=0;n<9;n=n+1)begin
   length=lengths[n];configure(length,n%4);
   if(length==0)begin
    frame;if(!intro_done || dut.scroll!==512 || dut.scroll_half!==0)$fatal(1,"empty page readiness");
    intro_pause=1;repeat(3)frame;
    if(!intro_done || dut.scroll!==512)$fatal(1,"empty page pause");
    intro_pause=0;checks=checks+1;
   end else begin
    model_scroll=512;model_half=0;model_ready=0;frames=0;ready_frame=0;paused=0;
    expected_ready_frames=32*length-64;
    expected_ready_frames=expected_ready_frames<=0?1:(2*expected_ready_frames+2)/3;
    full_frames=(2*(512+32*length)+2)/3;
    while(frames<full_frames)begin
     // Hiding the subtitle must not defer AUTO or change frame phase.
     if(frames==3)enable=0;if(frames==11)enable=1;
     if(!paused && length>=3 && model_scroll>=448+32*length-3 && !model_ready)begin
      intro_pause=1;saved_scroll=model_scroll;repeat(5)frame;
      if(dut.scroll!==saved_scroll || intro_done || dut.scroll_half!==model_half[0])
       $fatal(1,"pause crossed readiness threshold length=%0d",length);
      intro_pause=0;paused=1;checks=checks+1;
     end
     model_scroll=model_scroll+(model_half?2:1);model_half=!model_half;
     if(model_scroll>=448+32*length)model_ready=1;
     if(model_scroll>=1024+32*length)model_scroll=0;
     frame;frames=frames+1;samples=samples+1;
     if(dut.scroll!==model_scroll || dut.scroll_half!==model_half[0] ||
        intro_done!==model_ready[0] || intro_done_index!==(n%4))
      $fatal(1,"readiness model mismatch length=%0d frame=%0d scroll=%0d expected=%0d done=%b expected=%b tag=%d",length,frames,dut.scroll,model_scroll,intro_done,model_ready[0],intro_done_index);
     if(intro_done && !ready_frame)begin
      ready_frame=frames;
      if(length>=2 && (1024+32*length-dut.scroll<575 || 1024+32*length-dut.scroll>576))
       $fatal(1,"tail did not trigger before screen centre length=%0d",length);
      if(dut.scroll==0)$fatal(1,"readiness truncated manual scroll");
      intro_pause=1;saved_scroll=model_scroll;repeat(3)frame;
      if(dut.scroll!==saved_scroll || !intro_done)$fatal(1,"pause did not retain ready epoch");
      intro_pause=0;checks=checks+1;
     end
    end
    if(ready_frame!=expected_ready_frames || dut.scroll!==0 || !intro_done)
     $fatal(1,"ready/full-loop frame count length=%0d ready=%0d expected=%0d",length,ready_frame,expected_ready_frames);
    frame;frame;if(!intro_done || dut.scroll!==3)$fatal(1,"manual repeated loop lost readiness");
    checks=checks+1;
   end
   // A quiet request must invalidate even a latched ready epoch, and clear
   // it only at a frame boundary; its token follows the three-clock drain.
   font_quiet_request=!font_quiet_request;repeat(4)tick;
   if(!intro_done || font_quiet_ack===font_quiet_request)$fatal(1,"quiet invalidated epoch before frame");
   frame_tick=1;tick;frame_tick=0;
   if(intro_done || dut.scroll!==512 || !font_cache_idle || font_quiet_ack===font_quiet_request)
    $fatal(1,"quiet frame did not clear readiness atomically");
   tick;tick;if(font_quiet_ack===font_quiet_request)$fatal(1,"early quiet token");
   tick;if(font_quiet_ack!==font_quiet_request)$fatal(1,"quiet token missing after drain");
   checks=checks+1;
  end
  $display("PASS subtitle readiness: %0d frame-model samples, %0d boundary checks,0/1/2/3/4/40/41/100/128-character pages,1/2-pixel threshold crossing at x575..576, complete manual loop, hidden timing,pause,scene tags,restart epoch,quiet token three-cycle drain",samples,checks);
  $finish;
 end
 initial begin #3000000;$fatal(1,"subtitle readiness timeout");end
endmodule
