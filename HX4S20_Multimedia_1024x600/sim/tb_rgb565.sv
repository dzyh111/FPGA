`timescale 1ns/1ps
module tb_rgb565;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,clear=0,pv=0;reg [23:0] pin=0;
 wire we,half;wire [31:0] word;
 rgb565_packer pack(.clk(clk),.rst(rst),.clear(clear),.valid(pv),.rgb(pin),
  .write_en(we),.write_data(word),.half_pending(half));
 reg active=0,img=0,enable=1;reg [10:0] x=0,y=0;reg [31:0] rd=0;
 wire re,valid;wire [10:0] px,py;wire [23:0] rgb;
 video_pixels_rgb565 unpack(.clk(clk),.rst(rst),.active(active),.image_active(img),
  .display_enabled(enable),.x(x),.y(y),.read_data(rd),.read_en(re),
  .valid(valid),.px(px),.py(py),.rgb(rgb));
 reg [31:0] memory[0:1];integer request=0,seen=0;
 task tick;begin @(negedge clk);end endtask
 always @(posedge clk)if(re)begin rd<=memory[request];request<=request+1;end
 always @(negedge clk)if(valid && py==0 && px<4)begin
  case(px)0:if(rgb!==24'hff0000)$fatal(1,"red %h",rgb);
           1:if(rgb!==24'h00ff00)$fatal(1,"green %h",rgb);
           2:if(rgb!==24'h0000ff)$fatal(1,"blue %h",rgb);
           3:if(rgb!==24'hffffff)$fatal(1,"white %h",rgb);endcase
  seen=seen+1;
 end
 initial begin
  memory[0]={16'hf800,16'h07e0};memory[1]={16'h001f,16'hffff};
  repeat(3)tick;rst=0;
  pv=1;pin=24'hff0000;tick;pin=24'h00ff00;tick;
  if(!we||word!==memory[0]||half)$fatal(1,"packer pair %h",word);
  pv=0;tick;
  clear=1;tick;clear=0;if(half)$fatal(1,"packer clear");
  active=1;img=1;
  for(x=0;x<4;x=x+1)tick;
  active=0;img=0;repeat(4)tick;
  if(seen!=4||request!=2)$fatal(1,"unpack count %0d requests %0d",seen,request);
  $display("PASS RGB565: pair packing, exact primary colours, one SDRAM read per two pixels");$finish;
 end
endmodule
