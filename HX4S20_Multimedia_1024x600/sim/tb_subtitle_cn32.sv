`timescale 1ns/1ps
module tb_subtitle_cn32;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,wr=0,frame=0,enable=1,picture=1,valid=0,sof=0,last=0;
 reg [8:0] addr=0;reg [7:0] data=0;reg [1:0] index=0;
 reg [7:0] len0=1,len3=0;
 wire ov,os,ol;wire [23:0] rgb;
 subtitle_overlay dut(.wr_clk(clk),.wr_en(wr),.wr_addr(addr),.wr_data(data),
 .font_wr_en(1'b0),.font_wr_addr(10'd0),.font_wr_data(16'd0),.font_ready(1'b1),
 .font_quiet_request(1'b0),
 .intro_pause(1'b0),.intro_restart(1'b0),
 .clk(clk),.rst(rst),.frame_tick(frame),.enable(enable),.show_picture(picture),
 .image_index(index),.len0(len0),.len1(8'd0),.len2(8'd0),.len3(len3),
 .valid(valid),.sof(sof),.last(last),.rgb(24'h204060),
 .out_valid(ov),.out_sof(os),.out_last(ol),.out_rgb(rgb));
 integer glyph_id=0,count=0,px,py,ink=0,total_pixels=0,mode;
 reg checking=0;
 reg [23:0] expected;
 task tick;begin @(negedge clk);end endtask
 always @(negedge clk)if(checking && ov)begin
  expected=(count%32<6)?24'h204060:(dut.font[glyph_id*16+(count/32)/2][15-(count%32)/2]?24'h101820:24'hc8d0d8);
  if(rgb!==expected || os!==0 || ol!==(count%32==31))
   $fatal(1,"32-glyph subtitle pixel mismatch id=%0d sample=%0d rgb=%h expected=%h",glyph_id,count,rgb,expected);
  if(rgb==24'h101820)ink=ink+1;
  count=count+1;total_pixels=total_pixels+1;
 end
 task draw_character;
  begin
   valid=0;repeat(5)tick;
   wr=1;data=128+glyph_id;tick;wr=0;repeat(4)tick;
   dut.x=0;dut.y=560;count=0;ink=0;checking=1;
   for(py=0;py<32;py=py+1)for(px=0;px<32;px=px+1)begin
    valid=1;last=px==31;tick;
   end
   valid=0;last=0;repeat(5)tick;checking=0;
   if(count!=1024 || ink==0)$fatal(1,"glyph missing or incomplete id=%0d samples=%0d ink=%0d",glyph_id,count,ink);
  end
 endtask
 initial begin
  repeat(4)tick;rst=0;repeat(4)tick;frame=1;tick;frame=0;repeat(4)tick;
  force dut.scroll=13'd1024;
  for(glyph_id=0;glyph_id<32;glyph_id=glyph_id+1)draw_character;
  release dut.scroll;
  // Full character-RAM address 255 and full glyph-ID value 31 must not alias.
  index=3;len3=64;addr=447;glyph_id=31;
  repeat(4)tick;frame=1;tick;frame=0;repeat(4)tick;
  force dut.scroll=13'd3040;
  draw_character;release dut.scroll;
  if(total_pixels!=33792)$fatal(1,"pixel coverage mismatch");
  $display("PASS subtitle CN32: all 32 legacy glyphs x1024 output pixels, IDs80..9f, legacy fallback glyph rows, page3character63, unchanged3-clock markers/border gutter/white strip");
  $finish;
 end
 initial begin #20000000;$fatal(1,"CN32 timeout");end
endmodule
