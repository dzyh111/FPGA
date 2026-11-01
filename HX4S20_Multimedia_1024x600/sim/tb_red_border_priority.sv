`timescale 1ns/1ps
// Real PCM capture + compositing priority, kept short (no full raster).
module tb_red_border_priority;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,cover_fixture=0,menu=0,spec=0;
 reg audio_valid=0,audio_reset=0,valid=1;
 reg signed [23:0] audio_sample=0;
 reg [2:0] zoom=1,scene=1;
 reg [3:0] state=6;
 reg [4:0] fade=16;
 reg [10:0] x=400,y=522;
 reg [23:0] rgb=24'h204060;
 wire ov,sof,last,rv,rs,rl;
 wire [23:0] color,reference_color;
 integer checks=0,n;
 reg [23:0] border_color;
 reg [23:0] history_rgb[0:20];
 reg history_valid[0:20],history_sof[0:20],history_last[0:20];
 media_osd #(.ENABLE_COVER(1)) dut(
  .clk(clk),.rst(rst),.frame_tick(frame_tick),.cover_active(cover_fixture),
  .state_code(state),.fade_alpha(fade),.manual_transition(1'b0),.manual_phase(6'd63),
  .menu_active(menu),.menu_item(3'd0),.rebuild_busy(1'b0),
  .rebuild_progress(3'd0),.rebuild_total(3'd4),
  .brightness_level(3'd2),.contrast_level(3'd2),.zoom_level(zoom),
  .scale_override(2'd0),.spectrum_enable(spec),.scene(scene),
  .audio_valid(audio_valid),.audio_sample(audio_sample),.audio_stream_reset(audio_reset),
  .valid(valid),.x(x),.y(y),.rgb(rgb),
  .out_valid(ov),.out_sof(sof),.out_last(last),.out_rgb(color));
 // Same real border/curtain inputs, deliberately no menu/wave layers.
 // Used only to observe the RGB entering those layers; palette correctness
 // has its own integer-reference suite, not another copied shader here.
 media_osd #(.ENABLE_COVER(1)) base(
  .clk(clk),.rst(rst),.frame_tick(frame_tick),.cover_active(cover_fixture),
  .state_code(state),.fade_alpha(fade),.manual_transition(1'b0),.manual_phase(6'd63),
  .menu_active(1'b0),.menu_item(3'd0),.rebuild_busy(1'b0),
  .rebuild_progress(3'd0),.rebuild_total(3'd4),
  .brightness_level(3'd2),.contrast_level(3'd2),.zoom_level(zoom),
  .scale_override(2'd0),.spectrum_enable(1'b0),.scene(scene),
  .audio_valid(audio_valid),.audio_sample(audio_sample),.audio_stream_reset(audio_reset),
  .valid(valid),.x(x),.y(y),.rgb(rgb),
  .out_valid(rv),.out_sof(rs),.out_last(rl),.out_rgb(reference_color));
 function [23:0] half_rgb;
  input [23:0] c;
  reg [7:0] r,g,b;
  begin r=c[23:16]/2;g=c[15:8]/2;b=c[7:0]/2;half_rgb={r,g,b};end
 endfunction
 function [23:0] half_wave;
  input [23:0] background;
  integer rr,gg,bb;
  begin
   rr=112/2+background[23:16]/2;
   gg=196/2+background[15:8]/2;
   bb=144/2+background[7:0]/2;
   half_wave={rr[7:0],gg[7:0],bb[7:0]};
  end
 endfunction
 task settle;begin repeat(10)@(negedge clk);end endtask
 task publish;
  begin
   settle;
   frame_tick=1;@(negedge clk);frame_tick=0;
   settle;
  end
 endtask
 task pixel;
  input integer px,py;input [23:0] expected;
  begin
   x=px;y=py;settle;checks=checks+1;
   if(!ov || color!==expected || sof!==(px==0 && py==0) || last!==(px==1023))
    $fatal(1,"priority pixel menu%0b spec%0b zoom%0d (%0d,%0d) got%h expected%h valid/sof/eol=%b%b%b",
           menu,spec,zoom,px,py,color,expected,ov,sof,last);
  end
 endtask
 task same_as_base;
  input integer px,py;
  begin
   x=px;y=py;settle;checks=checks+1;
   if(!ov || !rv || color!==reference_color || sof!==rs || last!==rl)
    $fatal(1,"base restore mismatch (%0d,%0d) rgb%h/%h",px,py,color,reference_color);
  end
 endtask
 initial begin
  settle;rst=0;settle;
  // 512 actual consumed PCM samples fill the real two-sample/column capture.
  // High PCM byte 96 maps exactly to +30 pixels, keeping the original trace
  // at y522 where it still crosses the 75-percent picture border.
  audio_sample=24'h600000;audio_valid=1;
  repeat(512)@(negedge clk);
  audio_valid=0;
  spec=1;publish;
  if(!dut.u_waveform.display_ready)$fatal(1,"real waveform capture not published");
  // Prime the preceding real column endpoint, as the scan does before x400.
  // The waveform joins adjacent column midpoints; a random x400 jump alone
  // would retain the reset midpoint and exercise its zero-to-30 ramp instead.
  x=399;y=522;settle;
  x=400;y=522;settle;
  if(reference_color===24'h70c490)$fatal(1,"test point did not distinguish border and wave");
  pixel(400,522,24'h70c490);
  pixel(401,522,24'h70c490);
  // Original half-mixed halo reaches y519 outside the three-pixel core.
  // Golden blend uses integer arithmetic, independent of the DUT shifts.
  x=400;y=519;settle;checks=checks+1;
  if(!ov || color!==half_wave(reference_color))
   $fatal(1,"original waveform halo/border blend got%h base%h",color,reference_color);
  same_as_base(400,518); // One pixel beyond the original halo margin.

  // Disable wave before checking menu-only compositing.
  spec=0;publish;same_as_base(400,522);
  if(color===rgb)$fatal(1,"expected 75-percent border at y522");

  // At 50%, left and bottom border points lie under opaque, non-text panel.
  zoom=0;publish;same_as_base(258,300);
  menu=1;publish;
  pixel(258,300,24'h192b31);
  pixel(400,447,24'h192b31);
  // Header region is independently opaque and has a different fixed colour.
  pixel(765,152,24'h17272d);
  menu=0;publish;same_as_base(258,300);same_as_base(400,447);

  // At 75%, the top border is outside the menu panel and dims by exactly 1/2.
  zoom=1;publish;x=400;y=77;settle;border_color=reference_color;
  if(border_color===rgb)$fatal(1,"expected top border fixture");
  menu=1;publish;pixel(400,77,half_rgb(border_color));
  menu=0;publish;same_as_base(400,77);
  // Other existing upper-priority pages suppress the border at the same point.
  cover_fixture=1;publish;pixel(400,77,24'h204060);
  cover_fixture=0;state=14;publish;pixel(400,77,24'hf4f6f8);
  state=6;publish;fade=0;pixel(400,77,24'h101c30);
  fade=16;same_as_base(400,77);

  // Stream tags and RGB bubbles through all six unchanged OSD stages.
  zoom=0;publish;
  for(n=0;n<18;n=n+1)begin
   @(negedge clk);
   case(n%3)
    0:begin x=0;y=0;end
    1:begin x=1023;y=10;end
    default:begin x=0;y=599;end
   endcase
   valid=(n%4)!=2;
   rgb={8'(32+n),8'(64+2*n),8'(96+3*n)};
   history_rgb[n]=rgb;history_valid[n]=valid;
   history_sof[n]=valid && x==0 && y==0;history_last[n]=valid && x==1023;
   @(posedge clk);#1;
   if(n>=5)begin
    checks=checks+1;
    if(ov!==history_valid[n-5] || sof!==history_sof[n-5] || last!==history_last[n-5] ||
       (history_valid[n-5] && color!==history_rgb[n-5]))
     $fatal(1,"six-stage priority tags/RGB mismatch n%0d got%h expected%h v/s/e=%b%b%b",
            n,color,history_rgb[n-5],ov,sof,last);
   end
  end
  $display("PASS border layer priority: %0d checks; real512-sample PCM capture, 75-percent border/original 3px-core 50-percent-halo overlap, opaque50-percent menu and external half-dim, exit/cover/error/fade, six-cycle RGB/valid/SOF/EOL bubbles",checks);
  $finish;
 end
 initial begin #1000000;$fatal(1,"border priority timeout");end
endmodule

