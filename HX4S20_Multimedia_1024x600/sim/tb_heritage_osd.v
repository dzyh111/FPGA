`timescale 1ns/1ps
module tb_heritage_osd;
 `include "font5x7.vh"
 reg clk=0,rst=1,frame=0,spectrum=0,menu=0;
 reg [3:0] state=6;
 reg [2:0] scene=4;
 reg [2:0] zoom=2;
 reg [10:0] x=0,y=0;
 wire valid,sof,last;wire [23:0] rgb;
 integer r,c,i,tx,ink=0,logo_ink=0,old_label_pixels=0;
 reg [23:0] expected;
 reg [34:0] glyph_s;
 reg [1:0] logo_reference[0:6143];
 reg [23:0] logo_foreground;
 function [23:0] logo_blend_reference;
  input [23:0] foreground;
  integer rr,gg,bb;
  begin
   rr=foreground[23:16]/2+foreground[23:16]/4+32/4;
   gg=foreground[15:8]/2+foreground[15:8]/4+64/4;
   bb=foreground[7:0]/2+foreground[7:0]/4+96/4;
   logo_blend_reference={rr[7:0],gg[7:0],bb[7:0]};
  end
 endfunction
 function [23:0] silent_wave_reference;
  input integer xx;
  integer t,rr,gg,bb;
  begin
   t=xx/32;rr=100+2*t;gg=174+t;bb=218+t;
   silent_wave_reference={rr[7:0],gg[7:0],bb[7:0]};
  end
 endfunction
 media_osd dut(.clk(clk),.rst(rst),.frame_tick(frame),.state_code(state),
 .cover_active(1'b0),.fade_alpha(5'd16),.manual_transition(1'b0),.menu_active(menu),.menu_item(3'd0),
 .rebuild_busy(1'b0),.rebuild_progress(3'd0),.rebuild_total(3'd4),
 .brightness_level(3'd2),.contrast_level(3'd2),.scale_override(2'd0),.zoom_level(zoom),
 .spectrum_enable(spectrum),.scene(scene),.audio_valid(1'b0),.audio_sample(24'sd0),
 .audio_stream_reset(1'b0),
 .valid(1'b1),.x(x),.y(y),.rgb(24'h204060),
 .out_valid(valid),.out_sof(sof),.out_last(last),.out_rgb(rgb));
 always #5 clk=~clk;
 task settle;begin repeat(8)@(negedge clk);end endtask
 task publish;begin settle;frame=1;@(negedge clk);frame=0;settle;end endtask
 initial begin
  $readmemh("rtl/anlogic_logo.mem",logo_reference);
  settle;rst=0;publish;
  // REAL DRUM was an OSD source-note plaque, not part of the photograph.
  // Its ENTIRE former box must now preserve the picture, including its text.
  for(r=20;r<44;r=r+1)for(c=24;c<200;c=c+1)begin
   x=c;y=r;settle;old_label_pixels=old_label_pixels+1;
   if(rgb!==24'h204060)$fatal(1,"removed REAL DRUM plaque remains at %0d,%0d",x,y);
  end
  menu=1;publish;glyph_s=glyph("D");
  for(r=0;r<7;r=r+1)for(c=0;c<5;c=c+1)begin
   x=384+c*2;y=126+r*2;settle;
   if(glyph_s[34-r*5-c])begin
    ink=ink+1;if(rgb!==24'hede5d4)$fatal(1,"menu ASCII D glyph missing");
   end else if(rgb!==24'h17272d)$fatal(1,"menu ASCII glyph background changed");
  end
  if(ink<8)$fatal(1,"invalid font fixture");
  menu=0;zoom=0;publish;
  // Logo palette comes from an independent ROM load; do not call the DUT's
  // palette/blend functions or weaken this check to merely "not background".
  for(r=0;r<64;r=r+1)for(c=0;c<96;c=c+1)begin
   x=920+c;y=16+r;settle;
   case(logo_reference[r*96+c])
    1:logo_foreground=24'he62b2f;
    2:logo_foreground=24'h1767b1;
    default:logo_foreground=24'h303840;
   endcase
   expected=logo_reference[r*96+c]==0?24'h204060:logo_blend_reference(logo_foreground);
   if(rgb!==expected)$fatal(1,"Anlogic logo differs at %0d,%0d: %h expected %h",x,y,rgb,expected);
   if(logo_reference[r*96+c]!=0)logo_ink=logo_ink+1;
  end
  if(logo_ink<100)$fatal(1,"invalid logo fixture");
  zoom=2;scene=0;x=300;y=400;settle;
  if(rgb!=24'h204060)$fatal(1,"neutral picture changed");
  x=0;y=0;settle;if(!sof || !valid || last)$fatal(1,"SOF alignment");
  x=1023;y=0;settle;if(sof || !last)$fatal(1,"line alignment");
  spectrum=1;publish;
  // No consumed samples: a real silent baseline spans the entire screen.
  // The 6-cycle OSD pipeline must preserve both its color and x boundaries.
  for(i=0;i<192;i=i+1)begin
   @(negedge clk);x=32+i;y=552;
   @(posedge clk);#1;
   if(i>=5)begin
    tx=i+27;expected=silent_wave_reference(tx);
    if(rgb!==expected)$fatal(1,"waveform pixel misaligned x=%d %h %h",tx,rgb,expected);
   end
  end
  state=14;publish;x=300;y=400;settle;
  if(rgb!=24'hf4f6f8)$fatal(1,"no legal picture error background");
  glyph_s=glyph("N");
  for(r=0;r<7;r=r+1)for(c=0;c<5;c=c+1)begin
   x=400+c*2;y=270+r*2;settle;
   expected=glyph_s[34-r*5-c]?24'hc62828:24'hf4f6f8;
   if(rgb!==expected)$fatal(1,"error ASCII N glyph differs");
  end
  $display("PASS heritage OSD: %0d removed-plaque pixels, independent menu/error ASCII and %0d logo pixels, RGB, SOF/last, waveform pixel pipeline",old_label_pixels,logo_ink);
  $finish;
 end
endmodule
