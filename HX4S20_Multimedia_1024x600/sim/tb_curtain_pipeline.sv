`timescale 1ns/1ps
// Pixel integration and frame/cache ownership proof for the manual reveal.
// No TF/BMP/SDRAM model is replaced by a shader-generated image here: the
// full SDRAM/FIFO/zoom test remains tb_video_zoom_rgb565.
module tb_curtain_pipeline;
  reg clk=0;always #5 clk=~clk;
  reg rst=1;
  reg pixel_done=0,scan_done=0;

  // Disable unrelated overlays but retain the REAL six-stage OSD pipeline.
  reg pv=0,ptick=0,pmode=0;
  reg [5:0] phase=63;
  reg [4:0] alpha=16;
  reg [10:0] px=0,py=0;
  reg [23:0] prgb=0;
  wire ov,sof,last;wire [23:0] orgb,reference_rgb;
  media_osd #(.ENABLE_COVER(1)) osd(
    .clk(clk),.rst(rst),.frame_tick(ptick),.cover_active(1'b1),
    .state_code(4'd6),.fade_alpha(alpha),.manual_transition(pmode),.manual_phase(phase),
    .menu_active(1'b0),.menu_item(3'd0),.rebuild_busy(1'b0),
    .rebuild_progress(3'd0),.rebuild_total(3'd4),.brightness_level(3'd2),
    .contrast_level(3'd2),.zoom_level(3'd2),.scale_override(2'd0),
    .spectrum_enable(1'b0),.scene(3'd0),.audio_valid(1'b0),.audio_sample(24'sd0),
    .audio_stream_reset(1'b0),.valid(pv),.x(px),.y(py),.rgb(prgb),
    .out_valid(ov),.out_sof(sof),.out_last(last),.out_rgb(orgb));
  // Independent integer red-cloth reference checks the geometry/blend split
  // without falsely claiming equivalence with the superseded gold curtain.
  gallery_transition_red_ref pixel_reference(.rgb(prgb),.x(px),.y(py),.fade_alpha(alpha),
    .manual_active(pmode),.manual_phase(phase),.valid(pv),.out_rgb(reference_rgb));
  reg [23:0] expected_rgb[0:5];
  reg expected_v[0:5],expected_sof[0:5],expected_last[0:5];
  integer q,pixel_checks=0,valid_checks=0;
  always @(posedge clk)begin
    if(rst)begin
      for(q=0;q<6;q=q+1)begin
        expected_v[q]=0;expected_sof[q]=0;expected_last[q]=0;expected_rgb[q]=0;
      end
    end else begin
      for(q=5;q>0;q=q-1)begin
        expected_v[q]=expected_v[q-1];expected_sof[q]=expected_sof[q-1];
        expected_last[q]=expected_last[q-1];expected_rgb[q]=expected_rgb[q-1];
      end
      expected_v[0]=pv;expected_sof[0]=pv && px==0 && py==0;
      expected_last[0]=pv && px==1023;expected_rgb[0]=reference_rgb;
      #1;
      if(ov!==expected_v[5] || sof!==expected_sof[5] || last!==expected_last[5])
        $fatal(1,"six-stage valid/SOF/EOL alignment got=%b%b%b expected=%b%b%b",ov,sof,last,expected_v[5],expected_sof[5],expected_last[5]);
      valid_checks=valid_checks+1;
      if(expected_v[5])begin
        pixel_checks=pixel_checks+1;
        if(orgb!==expected_rgb[5])$fatal(1,"curtain RGB/x/y misalignment phase=%0d got=%h expected=%h",phase,orgb,expected_rgb[5]);
      end
    end
  end
  integer p,row,col;
  reg [31:0] pixel_random=32'h7d21a953;
  initial begin
    repeat(5)@(negedge clk);rst=0;
    repeat(8)@(negedge clk);ptick=1;
    @(negedge clk);ptick=0;
    repeat(8)@(negedge clk);
    for(p=0;p<64;p=p+1)begin
      // A real phase change happens in vertical blanking, never amid pixels.
      pv=0;repeat(8)@(negedge clk);
      pmode=1;phase=p;alpha=p==63?16:p>>2;
      repeat(8)@(negedge clk);
      for(row=0;row<4;row=row+1)begin
        for(col=0;col<1024;col=col+1)begin
          @(negedge clk);px=col;
          case(row)0:py=0;1:py=191;2:py=383;3:py=599;endcase
          // Valid bubbles verify bypass does not disturb any coordinate tag.
          pv=(col%13)!=7;
          prgb={col[7:0],(col[7:0]^8'hb7),(col[7:0]+row[7:0]+p[7:0])};
        end
      end
    end
    // Phase changes stay in blanking; y jumps between rows on every pixel.
    for(p=0;p<32;p=p+1)begin
      pv=0;repeat(8)@(negedge clk);
      pixel_random={pixel_random[30:0],pixel_random[31]^pixel_random[21]^pixel_random[1]^pixel_random[0]};
      pmode=pixel_random[0];phase=pixel_random[13:8];alpha=pixel_random[20:16];
      repeat(8)@(negedge clk);
      for(col=0;col<256;col=col+1)begin
        @(negedge clk);
        pixel_random={pixel_random[30:0],pixel_random[31]^pixel_random[21]^pixel_random[1]^pixel_random[0]};
        px=pixel_random[9:0];py=pixel_random[20:11]%600;
        pv=(col%11)!=4;prgb=pixel_random[23:0];
        case(col[4:0])
          0:begin px=0;py=0;pv=1;end
          1:py=511;
          2:py=512;
          3:begin px=1023;py=599;pv=1;end
          4:py=1;
          5:py=598;
        endcase
      end
    end
    pv=0;repeat(8)@(negedge clk);pmode=0;alpha=7;
    repeat(8)@(negedge clk);
    for(col=0;col<1024;col=col+1)begin
      @(negedge clk);pv=1;px=col;py=300;prgb={col[7:0],8'h80,8'hfa};
    end
    @(negedge clk);pv=0;repeat(8)@(negedge clk);pixel_done=1;
  end

  reg token=0,manual=0,blank=0,rack=0;
  reg [1:0] target=0;
  wire ack,back,req,enabled,tick,busy,manual_active,line_start;
  wire [1:0] current,next;
  wire [4:0] fade;
  wire [5:0] manual_phase;
  wire [9:0] slide;
  video_scan #(.H_ACTIVE(8),.H_FP(1),.H_SYNC(1),.H_BP(1),
    .V_ACTIVE(2),.V_FP(1),.V_SYNC(1),.V_BP(1),.IMG_W(8),.IMG_H(2)) scan(
    .clk(clk),.rst(rst),.commit_toggle(token),.commit_index(target),
    .commit_cover(1'b0),.commit_manual(manual),.manual_transition(manual_active),
    .manual_phase(manual_phase),.blank_toggle(blank),.blank_ack(back),.commit_ack(ack),
    .read_index(current),.next_index(next),.slide_rows(slide),.fade_alpha(fade),
    .transition_busy(busy),.read_req(req),.read_req_ack(rack),
    .display_enabled(enabled),.frame_tick(tick),.line_start(line_start));
  integer delay_memory=0,requested_delay=5,requests=0;
  always @(posedge clk)begin
    if(rst || !req)begin rack<=0;delay_memory<=requested_delay;end
    else if(!rack)begin
      if(delay_memory==0)begin rack<=1;requests=requests+1;end
      else delay_memory<=delay_memory-1;
    end
  end
  integer close_steps=0,open_steps=0,auto_down=0,auto_up=0,switches=0,frame_checks=0;
  reg old_tick,old_manual,old_busy,old_ack;
  reg [1:0] old_current,old_state;
  reg [4:0] old_fade;
  reg [5:0] old_phase,old_open_count;
  integer wanted;
  always @(posedge clk)begin
    old_tick=tick;old_manual=manual_active;old_busy=busy;old_ack=ack;
    old_current=current;old_state=scan.transition_state;old_fade=fade;old_phase=manual_phase;
    old_open_count=scan.manual_open_count;
    #1;
    if(!rst)begin
      if(line_start!==(scan.hc==0))$fatal(1,"line_start must remain direct hc==0");
      if(next!==current || slide!==0)$fatal(1,"single cached image/no-slide ownership changed");
      if((fade!==old_fade || manual_phase!==old_phase) && !old_tick)
        $fatal(1,"phase changed within raster frame");
      if(current!==old_current)begin
        switches=switches+1;
        if(!old_tick || fade!==0 || (manual_active && manual_phase!==0))
          $fatal(1,"cache swap exposed: tick=%b fade=%0d phase=%0d",old_tick,fade,manual_phase);
      end
      if(ack!==old_ack && (!old_tick || fade!==16 || !enabled || busy))
        $fatal(1,"ACK before full visibility/frame boundary");
      if(old_manual && old_busy && old_state==2 && manual_phase!==0)
        $fatal(1,"memory acknowledgement wait exposed cache");
      if(old_tick && old_manual && old_state==1)begin
        wanted=old_phase<=8?0:old_phase-8;
        if(manual_phase!==wanted)$fatal(1,"manual close step %0d -> %0d",old_phase,manual_phase);
        close_steps=close_steps+1;
      end
      if(old_tick && old_manual && old_state==3)begin
        wanted=(old_open_count+1)*63/48;
        if(manual_phase!==wanted)$fatal(1,"manual open step %0d -> %0d",old_phase,manual_phase);
        open_steps=open_steps+1;
      end
      if(manual_active && busy)begin
        wanted=manual_phase==63?16:manual_phase>>2;
        if(fade!==wanted)$fatal(1,"legacy waveform/OSD alpha disagrees with curtain phase");
      end
      if(old_tick && !old_manual && old_state==1)begin
        wanted=old_fade<=1?0:old_fade-1;
        if(fade!==wanted)$fatal(1,"AUTO fade-out changed");
        auto_down=auto_down+1;
      end
      if(old_tick && !old_manual && old_state==3)begin
        wanted=old_fade>=15?16:old_fade+1;
        if(fade!==wanted)$fatal(1,"AUTO fade-in changed");
        auto_up=auto_up+1;
      end
      if(old_tick)frame_checks=frame_checks+1;
    end
  end
  task commit_scene(input bit is_manual,input [1:0] index,input integer memory_cycles);
    integer timeout,c0,o0,d0,u0,r0;reg enabled_before;
    begin
      @(negedge clk);manual=is_manual;target=index;requested_delay=memory_cycles;
      repeat(4)@(negedge clk);
      c0=close_steps;o0=open_steps;d0=auto_down;u0=auto_up;r0=requests;
      enabled_before=enabled;token=~token;timeout=0;
      while(ack!==token)begin
        @(negedge clk);timeout=timeout+1;
        if(timeout>20000)$fatal(1,"cache acknowledgement timeout");
        if(busy && manual_active!==is_manual)$fatal(1,"transition source changed during commit");
      end
      if(fade!==16 || manual_phase!==63 || !enabled || busy || current!==index)
        $fatal(1,"incomplete scene acknowledgement");
      if(requests<=r0)$fatal(1,"commit never fetched cache");
      if(is_manual)begin
        if(close_steps-c0!=(enabled_before?8:0) || open_steps-o0!=48)
          $fatal(1,"manual duration close=%0d open=%0d",close_steps-c0,open_steps-o0);
      end else if(auto_down-d0!=(enabled_before?16:0) || auto_up-u0!=16)
        $fatal(1,"legacy AUTO 16+16 frame duration changed");
    end
  endtask
  initial begin
    wait(!rst);
    commit_scene(0,1,5);
    commit_scene(1,2,130);
    commit_scene(0,3,1);
    commit_scene(1,0,31);
    @(negedge clk);blank=1;wait(back==blank);@(negedge clk);
    if(enabled || fade!==0)$fatal(1,"blanking handshake failed");
    commit_scene(1,2,77);
    @(negedge clk);manual=1'bz;repeat(4)@(negedge clk);
    if(scan.manual_s1!==0)$fatal(1,"unconnected legacy mode propagated X/Z");
    scan_done=1;
  end
  initial begin
    wait(scan_done && pixel_done);
    $display("PASS red curtain pipeline: %0d exact streamed pixels/%0d valid tags, all64 phases/four rows, unchanged six-cycle OSD; %0d raster frames/%0d fully-hidden cache switches, manual8+48, AUTO16+16, delayed memory ACK, blank restore, direct line_start",pixel_checks,valid_checks,frame_checks,switches);
    $finish;
  end
  initial begin #10000000;$fatal(1,"curtain pipeline timeout");end
endmodule
