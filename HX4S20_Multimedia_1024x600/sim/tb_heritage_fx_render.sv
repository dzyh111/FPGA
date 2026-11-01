`timescale 1ns/1ps
module tb_heritage_fx_render;
 reg clk=0,rst=1,valid=0;
 reg [2:0] scene=1;
 reg [10:0] x=0,y=0;
 reg [23:0] rgb=0;
 wire out_valid;
 wire [10:0] out_x,out_y;
 wire [23:0] out_rgb;
 wire signed [4:0] bow;
 wire [3:0] drum;
 reg [23:0] source[0:614399];
 integer image_number,pixel,file_handle;
 reg [4095:0] input_path,output_path;
 heritage_fx dut(.clk(clk),.rst(rst),.frame_tick(1'b0),.enable(1'b1),
  .stream_reset(1'b0),.scene(scene),.sample_consumed(1'b0),.sample_position(32'd0),
  .valid(valid),.x(x),.y(y),.rgb(rgb),.out_valid(out_valid),.out_x(out_x),.out_y(out_y),
  .out_rgb(out_rgb),.bow_offset(bow),.drum_offset(drum));
 always #5 clk=~clk;
 initial begin
  if(!$value$plusargs("SCENE=%d",image_number))$fatal(1,"SCENE missing");
  if(!$value$plusargs("INPUT=%s",input_path))$fatal(1,"INPUT missing");
  if(!$value$plusargs("OUTPUT=%s",output_path))$fatal(1,"OUTPUT missing");
  scene=image_number;
  $readmemh(input_path,source);
  file_handle=$fopen(output_path,"wb");
  $fwrite(file_handle,"P6\n1024 600\n255\n");
  @(negedge clk);rst=0;
  force dut.level=4'd12;
  force dut.note=3'd2;
  force dut.age=6'd4;
  force dut.sparkle=3'd1;
  for(pixel=0;pixel<614400;pixel=pixel+1)begin
   @(negedge clk);
   valid=1;x=pixel%1024;y=pixel/1024;rgb=source[pixel];
   @(posedge clk);#1;
   if(pixel==0)begin
    if(out_valid)$fatal(1,"pipeline initial bubble");
   end else begin
    if(!out_valid || out_x!=(pixel-1)%1024 || out_y!=(pixel-1)/1024)
     $fatal(1,"pipeline coordinates");
    $fwrite(file_handle,"%c%c%c",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
   end
  end
  @(negedge clk);valid=0;
  @(posedge clk);#1;
  if(!out_valid || out_x!=1023 || out_y!=599)$fatal(1,"pipeline final pixel");
  $fwrite(file_handle,"%c%c%c",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
  $fclose(file_handle);
  $display("PASS rendered scene %0d %s",image_number,output_path);
  $finish;
 end
endmodule
