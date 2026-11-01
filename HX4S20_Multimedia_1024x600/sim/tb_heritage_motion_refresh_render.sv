`timescale 1ns/1ps
// Render the actual ROM sprite and refreshed FX RTL, not a Python animation.
module tb_heritage_motion_refresh_render;
 reg clk=0,rst=1,valid=0;
 reg [2:0] scene=1;
 reg [10:0] x=0,y=0;
 reg [23:0] rgb=0;
 wire motion_valid,fx_valid;
 wire [10:0] motion_x,motion_y,fx_x,fx_y;
 wire [23:0] motion_rgb,fx_rgb;
 reg signed [4:0] bow_offset;
 reg signed [2:0] bow_tilt;
 wire signed [5:0] bow_angle=$signed(bow_tilt)*12;
 reg [3:0] drum_offset,drum_right_offset;
 reg [23:0] source[0:614399];
 integer image_number,variant,pixel,file_handle,written=0;
 reg [4095:0] input_path,output_path;
 heritage_motion_layer motion(.clk(clk),.rst(rst),.scene(scene),
  .bow_offset(bow_offset),.bow_angle(bow_angle),.drum_offset(drum_offset),
  .drum_right_offset(drum_right_offset),.valid(valid),.x(x),.y(y),.rgb(rgb),
  .out_valid(motion_valid),.out_x(motion_x),.out_y(motion_y),.out_rgb(motion_rgb));
 heritage_fx fx(.clk(clk),.rst(rst),.frame_tick(1'b0),.enable(1'b1),
  .stream_reset(1'b0),.scene(scene),.sample_consumed(1'b0),.sample_position(32'd0),
  .valid(motion_valid),.x(motion_x),.y(motion_y),.rgb(motion_rgb),
  .out_valid(fx_valid),.out_x(fx_x),.out_y(fx_y),.out_rgb(fx_rgb));
 always #5 clk=~clk;
 always @(posedge clk)begin
  #1;
  if(!rst && fx_valid)begin
   if(fx_x!=written%1024 || fx_y!=written/1024)$fatal(1,"render coordinate alignment");
   $fwrite(file_handle,"%c%c%c",fx_rgb[23:16],fx_rgb[15:8],fx_rgb[7:0]);
   written=written+1;
  end
 end
 initial begin
  if(!$value$plusargs("SCENE=%d",image_number))$fatal(1,"SCENE missing");
  if(!$value$plusargs("VARIANT=%d",variant))variant=0;
  if(!$value$plusargs("INPUT=%s",input_path))$fatal(1,"INPUT missing");
  if(!$value$plusargs("OUTPUT=%s",output_path))$fatal(1,"OUTPUT missing");
  scene=image_number;
  bow_offset=variant ? -5 : 3;bow_tilt=variant ? 2 : -2;
  drum_offset=variant ? 14 : 0;drum_right_offset=variant ? 0 : 14;
  $readmemh(input_path,source);
  file_handle=$fopen(output_path,"wb");
  $fwrite(file_handle,"P6\n1024 600\n255\n");
  repeat(3)@(negedge clk);rst=0;
  force fx.level=4'd12;
  force fx.note=3'd2;
  force fx.age=6'd4;
  if(variant)begin
   force fx.sparkle=3'd5;
   force fx.drum_left_age=6'd6;
   force fx.drum_right_age=6'd0;
  end else begin
   force fx.sparkle=3'd1;
   force fx.drum_left_age=6'd0;
   force fx.drum_right_age=6'd6;
  end
  for(pixel=0;pixel<614400;pixel=pixel+1)begin
   @(negedge clk);
   valid=1;x=pixel%1024;y=pixel/1024;rgb=source[pixel];
  end
  @(negedge clk);valid=0;
  repeat(5)@(negedge clk);
  if(written!=614400)$fatal(1,"render incomplete %0d",written);
  $fclose(file_handle);
  $display("PASS actual RTL render scene %0d variant %0d pixels %0d",image_number,variant,written);
  $finish;
 end
endmodule
