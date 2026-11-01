`timescale 1ns/1ps
// Visual QA only: replay the released WAV's left channel, then render an RTL
// snapshot over the original BMP. This excludes OSD/RGB565/monitor response.
module tb_engraving_render;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,stream_reset=1,consumed=0,valid=0;
 reg [2:0] scene=1;
 reg [31:0] sample_position=0;
 reg signed [23:0] sample=0;
 reg [10:0] x=0,y=0;reg [23:0] rgb=0;
 wire mv,fv,ev;wire [10:0] mx,my,fx,fy,ex,ey;wire [23:0] mr,fr,er;
 wire signed [4:0] bow_offset;wire signed [2:0] bow_tilt;wire signed [5:0] bow_angle;
 wire [3:0] drum_offset,drum_right_offset;
 heritage_motion_layer motion(.clk(clk),.rst(rst),.scene(scene),.bow_offset(bow_offset),
  .bow_angle(bow_angle),.drum_offset(drum_offset),.drum_right_offset(drum_right_offset),
  .valid(valid),.x(x),.y(y),.rgb(rgb),.out_valid(mv),.out_x(mx),.out_y(my),.out_rgb(mr));
 heritage_fx effect(.clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(1'b1),
  .stream_reset(stream_reset),.scene(scene),.sample_consumed(consumed),.sample_position(sample_position),
  .valid(mv),.x(mx),.y(my),.rgb(mr),.out_valid(fv),.out_x(fx),.out_y(fy),.out_rgb(fr),
  .bow_offset(bow_offset),.bow_tilt(bow_tilt),.bow_angle(bow_angle),
  .drum_offset(drum_offset),.drum_right_offset(drum_right_offset));
 sonic_engraving ink(.clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(1'b1),
  .stream_reset(stream_reset),.scene(scene),.sample_valid(consumed),.sample(sample),
  .valid(fv),.x(fx),.y(fy),.rgb(fr),.out_valid(ev),.out_x(ex),.out_y(ey),.out_rgb(er));
 reg [15:0] pcm[0:767999];reg [23:0] photo[0:614399];
 string pcm_path,photo_path,output_path;
 integer selected_scene,count=600000,n,xx,yy,fd,pixels=0;
 reg saving=0;
 always @(negedge clk)if(saving && ev && ex<1024 && ey<600)begin
  $fwrite(fd,"%c%c%c",er[23:16],er[15:8],er[7:0]);pixels=pixels+1;
 end
 initial begin
  if(!$value$plusargs("SCENE=%d",selected_scene) || !$value$plusargs("PCM=%s",pcm_path) ||
     !$value$plusargs("PHOTO=%s",photo_path) || !$value$plusargs("OUT=%s",output_path))
   $fatal(1,"missing render arguments");
  if($value$plusargs("COUNT=%d",count))begin end
  scene=selected_scene;$readmemh(pcm_path,pcm);$readmemh(photo_path,photo);
  repeat(4)@(negedge clk);rst=0;stream_reset=0;
  frame_tick=1;@(negedge clk);frame_tick=0;
  for(n=0;n<count;n=n+1)begin
   consumed=1;sample={pcm[n],8'd0};sample_position=n==767999?0:n+1;
   frame_tick=(n%800)==799;@(negedge clk);
   consumed=0;frame_tick=0;@(negedge clk);
  end
  repeat(3)@(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;
  fd=$fopen(output_path,"wb");$fwrite(fd,"P6\n1024 600\n255\n");saving=1;
  for(yy=0;yy<600;yy=yy+1)for(xx=0;xx<1024;xx=xx+1)begin
   valid=1;x=xx;y=yy;rgb=photo[yy*1024+xx];@(negedge clk);
  end
  valid=0;repeat(12)@(negedge clk);saving=0;$fclose(fd);
  if(pixels!=614400)$fatal(1,"render pixel count %0d",pixels);
  $display("PASS render scene %0d: %0d real PCM samples, %0d visible columns, %0d pixels",scene,count,ink.visible_count,pixels);
  $finish;
 end
endmodule
