`timescale 1ns/1ps
// Real FX pixel output on the unchanged TF photograph. Phrase/level and phase
// are static art fixtures, NOT a recorded-audio sync test or a board capture.
module tb_flute_notes_render;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,valid=0;reg [10:0] x=0,y=0;reg [23:0] rgb=0;
 wire out_valid;wire [10:0] out_x,out_y;wire [23:0] out_rgb;
 wire signed [5:0] bow_offset,bow_angle;wire signed [2:0] bow_tilt;
 wire [4:0] drum_offset,drum_right_offset;
 heritage_fx dut(.clk(clk),.rst(rst),.frame_tick(1'b0),.enable(1'b1),
  .stream_reset(1'b0),.scene(3'd3),.sample_consumed(1'b0),.sample_position(32'd0),
  .valid(valid),.x(x),.y(y),.rgb(rgb),.out_valid(out_valid),.out_x(out_x),
  .out_y(out_y),.out_rgb(out_rgb),.bow_offset(bow_offset),.bow_tilt(bow_tilt),
  .bow_angle(bow_angle),.drum_offset(drum_offset),.drum_right_offset(drum_right_offset));
 reg [23:0] photo[0:614399];
 reg [7:0] phase=0;reg [3:0] strength=12;
 integer file,capture_count=0,f,h,xx,yy;
 reg capturing=0;reg [1023:0] filename;
 always @(negedge clk)if(capturing && out_valid)begin
  if(out_x!==100+capture_count%700 || out_y!==212+capture_count/700)
   $fatal(1,"note preview pixel coordinates mismatch at %0d",capture_count);
  if((^out_rgb)===1'bx)$fatal(1,"unknown note preview pixel");
  $fdisplay(file,"%06h",out_rgb);capture_count=capture_count+1;
 end
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask
 initial begin
  $readmemh("sim/notes_red_preview/source_dizi.hex",photo);
  repeat(4)step;rst=0;
  force dut.level=strength;force dut.flow_phase=phase;
  for(f=0;f<4;f=f+1)begin
   valid=0;repeat(6)step;phase=f*16;
   // Show successive cue-art combinations, with fully eased active rings.
   for(h=0;h<6;h=h+1)dut.hole_glow[h]=(h<(6-f*2)?15:0);
   $sformat(filename,"sim/notes_red_preview/dizi_phase%02d.rgbhex",phase);
   file=$fopen(filename,"w");if(!file)$fatal(1,"cannot open preview capture");
   $fdisplay(file,"RTL_FLUTE_NOTES_RGB_V1 100 212 700 132 %0d",phase);
   capture_count=0;capturing=1;
   for(yy=212;yy<344;yy=yy+1)for(xx=100;xx<800;xx=xx+1)begin
    valid=1;x=xx;y=yy;rgb=photo[yy*1024+xx];step;
   end
   valid=0;repeat(5)step;capturing=0;$fclose(file);
   if(capture_count!=92400)$fatal(1,"incomplete note capture %0d",capture_count);
   $display("CAPTURE note phase %0d: %0d actual RTL pixels",phase,capture_count);
  end
  $display("PASS flute note preview: 4 actual RTL ROI captures, photograph RGB input, three-clock FX pipeline; fixtures, not board/audio-sync proof");
  $finish;
 end
 initial begin #10000000;$fatal(1,"flute note preview timeout");end
endmodule
