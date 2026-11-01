`timescale 1ns/1ps
module tb_gallery_transition;
  reg [23:0] rgb=0;
  reg [10:0] x=0,y=0;
  reg [5:0] manual_phase=0;
  reg [4:0] fade_alpha=0;
  reg manual_active=0,valid=1;
  wire [23:0] out_rgb;
  wire [4:0] out_alpha;
  wire [23:0] out_background;
 gallery_transition dut(.*,.curve_gain_in(8'd0));
  integer level,px,value,depth,distance,amount,checks=0;
  reg [23:0] expected;

  function automatic [7:0] blend_ref(input integer fg,bg,a);
    blend_ref=(fg*a+bg*(16-a))>>4;
  endfunction
  task automatic check_pixel;
    begin
      #1;
      amount=(fade_alpha>=16)?16:fade_alpha;
      expected=valid?{blend_ref(rgb[23:16],8'h10,amount),
                      blend_ref(rgb[15:8],8'h1c,amount),
                      blend_ref(rgb[7:0],8'h30,amount)}:rgb;
      if(out_rgb!==expected)$fatal(1,"pixel x=%0d alpha=%0d manual=%0d rgb=%h got=%h expected=%h",x,fade_alpha,manual_active,rgb,out_rgb,expected);
      checks=checks+1;
    end
  endtask

  reg clk=0,rst=1,commit_toggle=0,commit_manual=0;
  reg [1:0] commit_index=0;
  wire commit_ack,read_req,manual_transition,transition_busy,display_enabled,frame_tick,line_start;
  wire [4:0] scan_alpha;
  reg read_req_ack=0;
  video_scan #(.H_ACTIVE(8),.H_FP(1),.H_SYNC(1),.H_BP(1),
               .V_ACTIVE(2),.V_FP(1),.V_SYNC(1),.V_BP(1),.IMG_W(8),.IMG_H(2)) scan(
      .clk(clk),.rst(rst),.commit_toggle(commit_toggle),.commit_index(commit_index),
      .commit_cover(1'b0),.commit_manual(commit_manual),.manual_transition(manual_transition),
      .blank_toggle(1'b0),.commit_ack(commit_ack),.read_req(read_req),.read_req_ack(read_req_ack),
      .fade_alpha(scan_alpha),.transition_busy(transition_busy),.display_enabled(display_enabled),
      .frame_tick(frame_tick),.line_start(line_start));
  always #5 clk=~clk;
  always @(posedge clk)read_req_ack<=read_req;
  always @(negedge clk)if(!rst && line_start!==(scan.hc==0))$fatal(1,"line_start no longer directly matches hc==0");

  task automatic commit_scene(input bit is_manual,input [1:0] index);
    integer timeout;
    reg token;
    begin
      @(negedge clk);commit_manual=is_manual;commit_index=index;
      // Payload is held before the toggle and throughout its acknowledgement.
      repeat(4)@(negedge clk);
      token=~commit_toggle;commit_toggle=token;
      timeout=0;
      while(commit_ack!==token)begin
        @(negedge clk);timeout=timeout+1;
        if(timeout>10000)$fatal(1,"transition acknowledgement timeout");
        if(transition_busy && manual_transition!==is_manual)$fatal(1,"manual source changed during transition");
      end
      if(scan_alpha!==16 || !display_enabled)$fatal(1,"incomplete visible transition");
      if(scan.read_index!==index)$fatal(1,"wrong image committed");
    end
  endtask

  initial begin
    // All channel values and alpha codes: automatic mode equals old fade.
    for(level=0;level<32;level=level+1)begin
      fade_alpha=level;
      for(value=0;value<256;value=value+1)begin
        rgb={value[7:0],(8'hff-value[7:0]),(value[7:0]^8'h96)};
        check_pixel;
      end
    end
    // Manual pixel geometry is no longer the old rectangular mask. Its
    // independent shader proof is in tb_curtain_shader; frame/cache safety
    // and exact duration are checked by tb_curtain_pipeline.
    valid=0;fade_alpha=0;rgb=24'habcdef;check_pixel;valid=1;
    rst=0;
    commit_scene(0,1);commit_scene(1,2);commit_scene(0,3);
    // Legacy/unconnected mode inputs are deterministically automatic.
    @(negedge clk);commit_manual=1'bz;
    repeat(4)@(negedge clk);
    if(scan.manual_s1!==0)$fatal(1,"unconnected commit mode propagated unknown");
    $display("PASS gallery transition: %0d exact legacy AUTO pixels; manual/automatic commit handshake; direct line_start",checks);
    $finish;
  end
endmodule
