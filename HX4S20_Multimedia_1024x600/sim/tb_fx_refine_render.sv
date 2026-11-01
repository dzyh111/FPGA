`timescale 1ns/1ps
// Visual proof only. Real motion -> FX -> title RTL pixels on unchanged TF BMPs.
// Controls below are explicitly synthetic fixtures, NOT audio-sync validation.
module tb_fx_refine_render;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,enable=1,stream_reset=0,sample_consumed=0;
 reg [31:0] sample_position=0;
 reg [2:0] scene=1;
 reg valid=0;reg [10:0] x=0,y=0;reg [23:0] rgb=0;
 wire motion_valid,fx_valid,out_valid;
 wire [10:0] motion_x,motion_y,fx_x,fx_y,out_x,out_y;
 wire [23:0] motion_rgb,fx_rgb,out_rgb;
 wire signed [5:0] bow_offset,bow_angle;
 wire signed [2:0] bow_tilt;
 wire [4:0] drum_offset,drum_right_offset;
 heritage_motion_layer motion(.clk(clk),.rst(rst),.scene(scene),
  .bow_offset(bow_offset),.bow_angle(bow_angle),.drum_offset(drum_offset),
  .drum_right_offset(drum_right_offset),.valid(valid),.x(x),.y(y),.rgb(rgb),
  .out_valid(motion_valid),.out_x(motion_x),.out_y(motion_y),.out_rgb(motion_rgb));
 heritage_fx fx(.clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(enable),
  .stream_reset(stream_reset),.scene(scene),.sample_consumed(sample_consumed),
  .sample_position(sample_position),.valid(motion_valid),.x(motion_x),.y(motion_y),
  .rgb(motion_rgb),.out_valid(fx_valid),.out_x(fx_x),.out_y(fx_y),.out_rgb(fx_rgb),
  .bow_offset(bow_offset),.bow_tilt(bow_tilt),.bow_angle(bow_angle),
  .drum_offset(drum_offset),.drum_right_offset(drum_right_offset));
 calligraphy_title title(.clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(enable),
  .scene(scene),.valid(fx_valid),.x(fx_x),.y(fx_y),.rgb(fx_rgb),
  .out_valid(out_valid),.out_x(out_x),.out_y(out_y),.out_rgb(out_rgb));

 reg [23:0] photo[0:614399];
 reg [3:0] fixture_level=12;
 reg [2:0] fixture_note=2;
 reg [5:0] fixture_age=0,fixture_right_age=8;
 reg [7:0] fixture_flow=0;
 reg signed [5:0] fixture_bow=0,fixture_angle=0;
 reg [4:0] fixture_drum=0,fixture_drum_right=0;
 integer output_file,index_file,capture_count,frame_count=0;
 integer s,f,n,a,yy,xx,rx,ry,rw,rh;
 reg capturing=0;
 reg [1023:0] filename;
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask

 always @(negedge clk)if(capturing && out_valid)begin
  if(out_x!==rx+(capture_count%rw) || out_y!==ry+(capture_count/rw))
   $fatal(1,"capture pipeline order mismatch at pixel %0d: got %0d,%0d",capture_count,out_x,out_y);
  if((^out_rgb)===1'bx)$fatal(1,"unknown output pixel %0d",capture_count);
  // Old portable vvp builds mishandle NUL in %c output. Hex is byte-exact.
  $fwrite(output_file,"%06h\n",out_rgb);
  capture_count=capture_count+1;
 end

 task capture;
  input integer current_scene,current_frame,capture_mode;
  begin
   valid=0;repeat(12)step;
   fixture_age=current_frame;fixture_right_age=(current_frame+8)%40;
   fixture_flow=current_frame;
   fixture_note=current_scene==1?2:3;
   fixture_level=current_scene==2?15:12;
   fixture_bow=current_frame==0?-24:(current_frame==8?0:24);
   fixture_angle=current_frame==0?-18:(current_frame==8?0:18);
   // Keep the actual RTL rebound function in the sprite proof as well.
   fixture_drum=fx.u_drum.rebound(fixture_age,1'b1);
   fixture_drum_right=fx.u_drum.rebound(fixture_right_age,1'b1);
   if(capture_mode==1)begin rx=0;ry=0;rw=1024;rh=600;end
   else if(capture_mode==2)case(current_scene)
    1:begin rx=250;ry=220;rw=260;rh=140;end
    3:begin rx=390;ry=205;rw=300;rh=95;end
    4:begin rx=300;ry=150;rw=440;rh=140;end
    default:begin rx=120;ry=335;rw=830;rh=155;end
   endcase
   else case(current_scene)
    1:begin rx=170;ry=165;rw=720;rh=235;end
    3:begin rx=245;ry=175;rw=620;rh=140;end
    4:begin rx=140;ry=100;rw=760;rh=255;end
    default:begin rx=120;ry=335;rw=830;rh=155;end
   endcase
   $sformat(filename,"sim/fx_refine_preview/final_dizi/scene%0d_frame%02d.rgbhex",current_scene,current_frame);
   output_file=$fopen(filename,"w");
   if(!output_file)$fatal(1,"cannot open preview RGB hex");
   $fwrite(output_file,"RTL_RGB_HEX_V1 %0d %0d\n",rw,rh);
   $fdisplay(index_file,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
    current_scene,current_frame,rx,ry,rw,rh,fixture_level,fixture_note,
    fixture_age,fixture_right_age,fixture_drum,fixture_drum_right);
   repeat(12)step;
   capture_count=0;capturing=1;
   for(yy=ry;yy<ry+rh;yy=yy+1)for(xx=rx;xx<rx+rw;xx=xx+1)begin
    valid=1;x=xx;y=yy;rgb=photo[yy*1024+xx];step;
   end
   valid=0;repeat(12)step;capturing=0;
   if(capture_count!=rw*rh)$fatal(1,"capture pixel count %0d != %0d",capture_count,rw*rh);
   $fclose(output_file);frame_count=frame_count+1;
   $display("CAPTURE scene=%0d frame=%0d ROI=%0d,%0d,%0d,%0d pixels=%0d",
    current_scene,current_frame,rx,ry,rw,rh,capture_count);
  end
 endtask

 initial begin
  index_file=$fopen("sim/fx_refine_preview/final_dizi/capture_index.txt","w");
  if(!index_file)$fatal(1,"create sim/fx_refine_preview before capture");
  $fdisplay(index_file,"RTL_FX_REFINE_CAPTURE_V2 scene3_only fixture_controls_not_audio_or_board");
  repeat(4)step;rst=0;
  force fx.level=fixture_level;force fx.note=fixture_note;force fx.age=fixture_age;
  force fx.flow_phase=fixture_flow;
  force fx.drum_left_age=fixture_age;force fx.drum_right_age=fixture_right_age;
  force fx.bow_offset=fixture_bow;force fx.bow_angle=fixture_angle;
  force fx.drum_offset=fixture_drum;force fx.drum_right_offset=fixture_drum_right;
  force title.state=4;force title.ready=1;force title.done=1;force title.pen_visible=0;
  // Final geometry revision changes only scene 3. Other scene captures remain
  // historical internal QA and are NOT represented by this final manifest.
  for(s=3;s<=3;s=s+1)begin
   scene=s;valid=0;repeat(12)step;
   // Final persistent glyph fixture; title mapping and colour still run in RTL.
   for(n=0;n<8192;n=n+1)begin
    a=(s-1)*8192+((n%128)>=64?4096:0)+(n/128)*64+n%64;
    title.ink_canvas[n]=title.glyph_dictionary_rom[title.glyph_index_rom[a>>4]][a%16];
    if(title.ink_canvas[n]!==title.glyph_rom[a])$fatal(1,"packed fixture differs from glyph reference");
   end
   $sformat(filename,"sim/fx_refine_preview/final_dizi/source_scene%0d.hex",s);
   $readmemh(filename,photo);
   capture(s,0,1);
   if(s!=2)for(f=4;f<=32;f=f+4)capture(s,f,(f==8 || f==20)?0:2);
  end
  $fclose(index_file);
  if(frame_count!=9)$fatal(1,"unexpected capture count %0d",frame_count);
  $display("PASS 9 scene-3-only real RTL pixel captures; synthetic visual fixtures, not audio or board validation");
  $finish;
 end
 initial begin #1000000000;$fatal(1,"FX preview capture timeout");end
endmodule
