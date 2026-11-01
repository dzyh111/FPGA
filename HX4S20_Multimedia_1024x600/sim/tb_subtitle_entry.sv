`timescale 1ns/1ps
module tb_subtitle_entry;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,wr=0,frame=0,enable=0,picture=0,valid=0,last=0;
 reg [8:0] addr=0;reg [7:0] data=0;reg [1:0] index=0;
 wire ov,os,ol;wire [23:0] rgb;
 subtitle_overlay dut(.wr_clk(clk),.wr_en(wr),.wr_addr(addr),.wr_data(data),
  .font_wr_en(1'b0),.font_wr_addr(10'd0),.font_wr_data(16'd0),.font_ready(1'b1),
  .font_quiet_request(1'b0),
  .intro_pause(1'b0),.intro_restart(1'b0),
  .clk(clk),.rst(rst),.frame_tick(frame),.enable(enable),.show_picture(picture),
  .image_index(index),.len0(8'd16),.len1(8'd16),.len2(8'd16),.len3(8'd16),
  .valid(valid),.sof(1'b0),.last(last),.rgb(24'h204060),
  .out_valid(ov),.out_sof(os),.out_last(ol),.out_rgb(rgb));
 reg [7:0] text[0:255];reg [4:0] ascii[0:1023];
 integer n,scene,xx,yy,count,ink,total=0,entry_scroll;
 integer gx,gy,local_x,cell_id,font_col;reg checking=0,hit;
 reg [7:0] code;reg [23:0] expected;
 task step;begin @(negedge clk);end endtask
 task publish;begin repeat(4)step;frame=1;step;frame=0;repeat(4)step;end endtask
 always @(negedge clk)if(checking && ov)begin
  gx=count%1024;gy=560+count/1024;local_x=gx+entry_scroll-1024;
  hit=0;
  if(local_x>=0 && local_x<512)begin
   cell_id=local_x/32;font_col=(local_x%32)/2;code=text[scene*64+cell_id];
   if(code>=128)hit=dut.font[(code-128)*16+(gy-560)/2][15-font_col];
   else if(font_col>=2 && font_col<12)hit=ascii[code*8+(gy-560)/4][4-(font_col-2)/2];
  end
  if(gx<6 || gx>=1018)hit=0;
  expected=(gx<6 || gx>=1018)?24'h204060:(hit?24'h101820:24'hc8d0d8);
  if(rgb!==expected || os!==0 || ol!==(gx==1023))
   $fatal(1,"subtitle entry pixels scene=%0d xy=%0d,%0d got=%h want=%h",scene,gx,gy,rgb,expected);
  if(hit)ink=ink+1;
  count=count+1;total=total+1;
 end
 initial begin
  $readmemh("sim/subtitle_cn_expected.hex",text);$readmemh("rtl/ascii_font_rows.hex",ascii);
  repeat(4)step;rst=0;
  for(n=0;n<256;n=n+1)begin wr=1;addr=(n/64)*128+(n%64);data=text[n];step;end
  wr=0;publish;
  if(dut.scroll!==512)$fatal(1,"subtitle hidden entry reset");
  enable=1;picture=1;
  for(scene=0;scene<4;scene=scene+1)begin
   index=scene;publish;entry_scroll=dut.scroll;
   if(entry_scroll<512 || entry_scroll>514)$fatal(1,"subtitle entry scroll=%0d must be on-screen immediately",entry_scroll);
   dut.x=0;dut.y=560;count=0;ink=0;checking=1;
   for(yy=560;yy<592;yy=yy+1)for(xx=0;xx<1024;xx=xx+1)begin
    valid=1;last=xx==1023;step;
   end
   valid=0;last=0;repeat(5)step;checking=0;
   if(count!=32768 || ink<1000)$fatal(1,"subtitle entry not legible scene=%0d pixels=%0d ink=%0d",scene,count,ink);
  end
  enable=0;publish;if(dut.en_d)$fatal(1,"subtitle disable visibility");
  enable=1;picture=0;publish;if(dut.scroll!==512 || dut.pic_d)$fatal(1,"cover subtitle suppression");
  $display("PASS subtitle entry: 4 legacy introduction lines, %0d exact pixels, text visible at entry without forcing scroll, border gutters/disabledvisibility/coverreset",total);$finish;
 end
 initial begin #3000000;$fatal(1,"subtitle entry timeout");end
endmodule
