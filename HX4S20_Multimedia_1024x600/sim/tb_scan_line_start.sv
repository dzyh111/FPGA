`timescale 1ns/1ps
// Fast regression of the real scan/zoom boundary, plus an intentionally bad
// shadow using the previous expression's constant-folded (zero-160) value.
module tb_scan_line_start;
 reg clk=0;always #5 clk=~clk;
 reg rst=1;wire tick,line_start,active;wire [10:0] x,y;
 video_scan #(.IMG_W(1024),.IMG_H(600)) scan(.clk(clk),.rst(rst),
  .commit_toggle(1'b0),.commit_index(2'd0),.commit_cover(1'b0),
  .blank_toggle(1'b0),.read_req_ack(1'b0),.frame_tick(tick),
  .line_start(line_start),.active(active),.x(x),.y(y));
 wire old_start=(x==(32'd0-32'd160));
 wire good_pop,bad_pop,good_valid;wire [10:0] gx,gy,sx,sy;
 video_zoom_rgb565 good(.clk(clk),.rst(rst),.frame_tick(tick),.line_start(line_start),
  .active(active),.display_enabled(1'b1),.cover_active(1'b0),.zoom_index(3'd2),
  .x(x),.y(y),.read_data(32'h94aad43b),.read_en(good_pop),.valid(good_valid),
  .src_x(gx),.src_y(gy),.screen_x(sx),.screen_y(sy));
 video_zoom_rgb565 old_shadow(.clk(clk),.rst(rst),.frame_tick(tick),.line_start(old_start),
  .active(active),.display_enabled(1'b1),.cover_active(1'b0),.zoom_index(3'd2),
  .x(x),.y(y),.read_data(32'h94aad43b),.read_en(bad_pop));
 integer good_words=0,bad_words=0,first_good=0,first_bad=0,checks=0;
 always @(posedge clk)if(!rst)begin
  if(old_start)$fatal(1,"old truncated expression unexpectedly produced a line pulse");
  if(line_start!==(scan.hc==0))$fatal(1,"line pulse not from actual HC");
  if(line_start)begin
   if(y==1)begin first_good=good_words;first_bad=bad_words;end
   if(y==2)begin
    if(first_good!=512 || first_bad!=512 || good_words!=512 || bad_words!=672)
     $fatal(1,"wrong reproduction good=%0d/%0d bad=%0d/%0d",first_good,good_words,first_bad,bad_words);
    if(checks!=2048)$fatal(1,"source coordinate coverage %0d",checks);
    $display("PASS real scan regression: 2048 source XY probes; correct 512 words/line; old truncated line_start reproduced 672 reads on row two (160 extra), fixed exported HC pulse prevents it");$finish;
   end
   good_words=0;bad_words=0;
  end
  if(good_pop)good_words=good_words+1;
  if(bad_pop)bad_words=bad_words+1;
 end
 always @(negedge clk)if(!rst && good_valid)begin
  if(gx!==sx || gy!==sy)$fatal(1,"real scan source XY mismatch at %0d,%0d source=%0d,%0d",sx,sy,gx,gy);
  checks=checks+1;
 end
 initial begin repeat(4)@(negedge clk);rst=0;end
 initial begin #500000;$fatal(1,"real scan regression timeout");end
endmodule
