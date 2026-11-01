`timescale 1ns/1ps
module tb_menu_visibility;
 `include "font5x7.vh"
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,menu=1,rebuild=0;
 reg [2:0] item=0,bri=2,con=2,zoom=2;
 reg [1:0] scale=0;
 reg [3:0] state=6;
 reg [10:0] x=0,y=0;
 reg [23:0] bg=0;
 wire ov,sof,last;wire [23:0] color;
 integer checks=0,i,j,c,r,n,level,mode;
 reg [79:0] value;
 media_osd dut(.clk(clk),.rst(rst),.frame_tick(frame_tick),.cover_active(1'b0),
  .state_code(state),.fade_alpha(5'd16),.manual_transition(1'b0),.menu_active(menu),.menu_item(item),
  .rebuild_busy(rebuild),.rebuild_progress(3'd0),.rebuild_total(3'd4),
  .brightness_level(bri),.contrast_level(con),.scale_override(scale),.zoom_level(zoom),
  .spectrum_enable(1'b0),.scene(3'd4),.audio_valid(1'b0),.audio_sample(24'sd0),
  .audio_stream_reset(1'b0),.valid(1'b1),.x(x),.y(y),.rgb(bg),
  .out_valid(ov),.out_sof(sof),.out_last(last),.out_rgb(color));
 task settle;begin repeat(8)@(negedge clk);end endtask
 task publish;begin settle;frame_tick=1;@(negedge clk);frame_tick=0;settle;end endtask
 task pixel;
  input integer xx,yy;input [23:0] expected;
  begin x=xx;y=yy;settle;checks=checks+1;
   if(!ov || color!==expected)$fatal(1,"menu pixel (%0d,%0d) item%0d %h != %h",xx,yy,item,color,expected);
  end
 endtask
 task word_pixels;
  input [255:0] text;input integer length,xx,yy;
  input [23:0] ink,paper;
  integer a,b,d;reg [7:0] letter;reg [34:0] bits;
  begin
   for(a=0;a<length;a=a+1)begin
    letter=(text>>(8*(length-1-a)))&255;bits=glyph(letter);
    for(b=0;b<14;b=b+1)for(d=0;d<16;d=d+1)
     pixel(xx+a*16+d,yy+b,(d<10 && bits[34-(b/2)*5-(d/2)])?ink:paper);
   end
  end
 endtask
 initial begin
  settle;rst=0;publish;
  word_pixels("DISPLAY SETTINGS",16,384,126,24'hede5d4,24'h17272d);
  word_pixels("K2 -   K3 SELECT   K4 +",23,328,480,24'hc2c9c6,24'h192b31);
  for(n=0;n<4;n=n+1)begin
   item=n;publish;
   for(i=0;i<4;i=i+1)begin
    pixel(266,202+i*64,i==n?24'hb54b3d:24'h192b31);
    pixel(300,234+i*64,i==n?24'h345257:24'h192b31);
    pixel(554,212+i*64,i==n?24'h243d43:24'h20343b);
    pixel(482+i*16,161,i==n?24'hf1cf91:24'h45545a);
   end
  end
  item=0;publish;
  word_pixels("ZOOM      ",10,296,212,24'hede5d4,24'h345257);
  for(mode=0;mode<5;mode=mode+1)begin
   zoom=mode;publish;
   case(mode)0:value="50%       ";1:value="75%       ";2:value="100%      ";
    3:value="125%      ";4:value="150%      ";endcase
   word_pixels(value,10,568,212,24'hede5d4,24'h243d43);
   for(j=0;j<5;j=j+1)begin
    pixel(560+j*32,240,j<=mode?24'hbfa575:24'h45545a);
    pixel(583+j*32,243,j<=mode?24'hbfa575:24'h45545a);
    pixel(584+j*32,243,24'h345257);
   end
   pixel(635,237,24'h345257);pixel(637,239,24'h345257);
   pixel(634,239,24'h345257);pixel(638,239,24'h345257);
   pixel(635,301,24'h192b31);pixel(637,367,24'h192b31);
  end
  for(n=1;n<=2;n=n+1)begin
   item=n;
   for(level=0;level<5;level=level+1)begin
    if(n==1)bri=level;else con=level;publish;
    case(level)0:value="50%       ";1:value="75%       ";2:value="100%      ";
     3:value="125%      ";4:value="150%      ";endcase
    word_pixels(value,10,568,212+n*64,24'hede5d4,24'h243d43);
    for(j=0;j<5;j=j+1)begin
     pixel(560+j*32,241+n*64,j<=level?24'hbfa575:24'h45545a);
     pixel(585+j*32,241+n*64,24'h345257);
    end
   end
  end
  item=3;publish;word_pixels("RETURN    ",10,568,404,24'hede5d4,24'h243d43);
  // Opacity is deliberate: the panel must not wash out on bright photos.
  for(i=0;i<32;i=i+1)begin bg=$urandom;pixel(500,446,24'h345257);pixel(260,100,24'h17272d);end
  bri=2;con=2;publish;bg=24'h406080;
  pixel(0,0,24'h203040);if(!sof || last)$fatal(1,"SOF metadata");
  pixel(1023,0,24'h203040);if(sof || !last)$fatal(1,"EOL metadata");
  menu=0;publish;pixel(500,450,bg);
  menu=1;state=14;publish;pixel(500,450,24'hf4f6f8);
  state=6;rebuild=1;publish;pixel(500,450,bg);
  $display("PASS menu visibility: %0d exact pixels; full 2x glyph replicas and six-pixel cell gaps, five percentages, four-pixel bars/no added tick, 4 selections, brightness/contrast, key hints, opacity/close/error/rebuild and metadata",checks);
  $finish;
 end
 initial begin #15000000;$fatal(1,"menu visibility timeout");end
endmodule
