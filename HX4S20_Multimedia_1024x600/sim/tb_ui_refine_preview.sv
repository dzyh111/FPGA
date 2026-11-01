`timescale 1ns/1ps
// Actual six-stage media_osd on unchanged local photo RGB.
// This isolates border/menu/logo from the separate motion/title/subtitle chain.
module tb_ui_refine_preview;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,audio_valid=0,valid=0;
 reg [2:0] scene=1;
 reg menu=0;
 reg signed [23:0] audio_sample=0;
 reg [10:0] x=0,y=0;
 reg [23:0] rgb=0;
 wire ov,sof,last;
 wire [23:0] out_rgb;
 media_osd #(.ENABLE_COVER(1)) dut(
  .clk(clk),.rst(rst),.frame_tick(frame_tick),.cover_active(1'b0),
  .state_code(4'd6),.fade_alpha(5'd16),.manual_transition(1'b0),.manual_phase(6'd63),
  .menu_active(menu),.menu_item(3'd1),.rebuild_busy(1'b0),
  .rebuild_progress(3'd0),.rebuild_total(3'd4),
  .brightness_level(3'd2),.contrast_level(3'd2),.zoom_level(3'd2),
  .scale_override(2'd0),.spectrum_enable(1'b0),.scene(scene),
  .audio_valid(audio_valid),.audio_sample(audio_sample),.audio_stream_reset(1'b0),
  .valid(valid),.x(x),.y(y),.rgb(rgb),
  .out_valid(ov),.out_sof(sof),.out_last(last),.out_rgb(out_rgb));
 reg [23:0] photo[0:614399];
 integer scene_no,row,col,n,fd=0,pixels=0,rows=0;
 reg collect=0,started=0,done=0;
 reg [511:0] filename;
 always @(posedge clk)begin
  #1;
  if(collect && ov)begin
   if(sof)begin
    if(started)$fatal(1,"unexpected second preview SOF");
    started=1;
   end
   if(started)begin
    if((^out_rgb)===1'bx)$fatal(1,"unknown border preview pixel");
    if(last!==(pixels%1024==1023))$fatal(1,"border preview EOL mismatch");
    $fwrite(fd,"%c%c%c",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
    pixels=pixels+1;
    if(last)rows=rows+1;
    if(pixels==614400)done=1;
   end
  end
 end
 initial begin
  repeat(12)@(negedge clk);rst=0;
  for(scene_no=1;scene_no<=6;scene_no=scene_no+1)begin
   scene=scene_no<=4?scene_no:1;menu=scene_no==6;valid=0;
   $sformat(filename,"sim/ui_refine_preview/photo_%0d.hex",scene);
   $readmemh(filename,photo);
   repeat(12)@(negedge clk);
   // Deterministic pre-mute PCM fixture, one consumed sample per shown frame.
   // Its purpose is repeatable response visibility, not musical beat detection.
   for(n=0;n<64;n=n+1)begin
    audio_sample=scene_no==5?24'sd0:(n[0]?24'sh600000:-24'sh600000);
    audio_valid=1;@(negedge clk);audio_valid=0;
    frame_tick=1;@(negedge clk);frame_tick=0;
    repeat(6)@(negedge clk);
   end
   $sformat(filename,"sim/ui_refine_preview/scene_%0d.ppm",scene_no);
   fd=$fopen(filename,"wb");if(!fd)$fatal(1,"missing border preview output directory");
   $fwrite(fd,"P6\n1024 600\n255\n");
   pixels=0;rows=0;started=0;done=0;collect=1;
   for(row=0;row<600;row=row+1)for(col=0;col<1024;col=col+1)begin
    @(negedge clk);valid=1;x=col;y=row;rgb=photo[row*1024+col];
   end
   @(negedge clk);valid=0;
   wait(done);@(negedge clk);collect=0;
   if(pixels!=614400 || rows!=600)$fatal(1,"incomplete border raster");
   $fclose(fd);fd=0;
   $display("RED_BORDER_CAPTURE scene=%0d pixels=%0d rows=%0d",scene_no,pixels,rows);
   $fflush();
   repeat(12)@(negedge clk);
  end
  $display("PASS red border preview: six native 1024x600 actual media_osd frames, six-stage RGB/SOF/EOL");
  $finish;
 end
 initial begin #90000000;$fatal(1,"border preview timeout");end
endmodule

