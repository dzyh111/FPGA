`timescale 1ns/1ps
// Source-space motion/FX/title and screen-space OSD coordinates must arrive
// together. Test real overlay modules, not three stand-in delay registers.
module tb_zoom_overlay_alignment;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,valid=0;
 reg [2:0] scene=1;
 reg [10:0] source_x=0,source_y=0,screen_x=0,screen_y=0;
 reg [23:0] rgb=0;
 wire mv,fv,tv;wire [10:0] mx,my,fx,fy,tx,ty,sx,sy;
 wire [23:0] mr,fr,tr;
 heritage_motion_layer motion(.clk(clk),.rst(rst),.scene(scene),
  .bow_offset(6'sd12),.bow_angle(6'sd10),.drum_offset(5'd16),.drum_right_offset(5'd9),
  .valid(valid),.x(source_x),.y(source_y),.rgb(rgb),
  .out_valid(mv),.out_x(mx),.out_y(my),.out_rgb(mr));
 heritage_fx effect(.clk(clk),.rst(rst),.frame_tick(1'b0),.enable(1'b1),
  .stream_reset(1'b0),.scene(scene),.sample_consumed(1'b0),.sample_position(32'd0),
  .valid(mv),.x(mx),.y(my),.rgb(mr),.out_valid(fv),.out_x(fx),.out_y(fy),.out_rgb(fr));
 calligraphy_title title(.clk(clk),.rst(rst),.frame_tick(1'b0),.enable(1'b0),.scene(scene),
  .valid(fv),.x(fx),.y(fy),.rgb(fr),.out_valid(tv),.out_x(tx),.out_y(ty),.out_rgb(tr));
 video_xy_delay #(.STAGES(9)) screen(.clk(clk),.rst(rst),.x(screen_x),.y(screen_y),.out_x(sx),.out_y(sy));
 reg [8:0] vp=0;
 reg [10:0] xp[0:8],yp[0:8],screen_xp[0:8],screen_yp[0:8];
 reg [23:0] rp[0:8];
 integer stage,checks=0,sentinels=0;
 always @(posedge clk)begin
  if(rst)begin
   vp=0;
   for(stage=0;stage<9;stage=stage+1)begin
    xp[stage]=0;yp[stage]=0;screen_xp[stage]=0;screen_yp[stage]=0;rp[stage]=0;
   end
  end else begin
   for(stage=8;stage>0;stage=stage-1)begin
    vp[stage]=vp[stage-1];xp[stage]=xp[stage-1];yp[stage]=yp[stage-1];
    screen_xp[stage]=screen_xp[stage-1];screen_yp[stage]=screen_yp[stage-1];rp[stage]=rp[stage-1];
   end
   vp[0]=valid;xp[0]=source_x;yp[0]=source_y;screen_xp[0]=screen_x;screen_yp[0]=screen_y;rp[0]=rgb;
   #1;
   if({mv,mx,my}!=={vp[2],xp[2],yp[2]})$fatal(1,"Motion source XY/valid is not 3 clocks");
   if({fv,fx,fy}!=={vp[5],xp[5],yp[5]})$fatal(1,"Motion+FX source XY/valid is not 6 clocks");
   if({tv,tx,ty}!=={vp[8],xp[8],yp[8]})$fatal(1,"Motion+FX+title source XY/valid is not 9 clocks");
   if({sx,sy}!=={screen_xp[8],screen_yp[8]})$fatal(1,"Screen-space coordinates not aligned to final artwork");
   if(vp[8] && xp[8]==2047 && yp[8]==2047)begin
    if(tr!==rp[8])$fatal(1,"Sentinel letterbox altered by artwork layer");
    sentinels=sentinels+1;
   end
   checks=checks+1;
  end
 end
 integer mode,n,xx,yy,numerator,denominator,left_edge,top_edge,width,height,base_x,base_y,rem_x;
 initial begin
  repeat(4)@(negedge clk);rst=0;
  for(mode=0;mode<5;mode=mode+1)begin
   numerator=1;denominator=1;left_edge=0;top_edge=0;width=1024;height=600;base_x=0;base_y=0;rem_x=0;
   case(mode)
    0:begin numerator=2;left_edge=256;top_edge=150;width=512;height=300;end
    1:begin numerator=4;denominator=3;left_edge=128;top_edge=75;width=768;height=450;end
    3:begin numerator=4;denominator=5;base_x=102;base_y=60;rem_x=2;end
    4:begin numerator=2;denominator=3;base_x=170;base_y=100;rem_x=2;end
    default:;
   endcase
   for(n=0;n<1024;n=n+1)begin
    @(negedge clk);
    xx=(n*17)%1024;yy=(n*13)%600;screen_x=xx;screen_y=yy;
    valid=n%5!=0;scene=1+((n/64)%4);rgb=(n*24'h010101)^24'h8ca751;
    if(xx<left_edge || xx>=left_edge+width || yy<top_edge || yy>=top_edge+height || n%13==0)begin
     source_x=2047;source_y=2047;
    end else begin
     source_x=base_x+((xx-left_edge)*numerator+rem_x)/denominator;
     source_y=base_y+((yy-top_edge)*numerator)/denominator;
    end
   end
  end
  @(negedge clk);valid=0;repeat(12)@(negedge clk);
  if(checks<5120 || sentinels<100)$fatal(1,"Insufficient overlay alignment coverage");
  $display("PASS zoom overlay alignment: %0d real-chain cycles, source motion/FX/title 3+3+3 clocks, screen XY 9 clocks, %0d clean sentinel pixels across 5 zooms/4 scenes",checks,sentinels);
  $finish;
 end
 initial begin #100000;$fatal(1,"zoom overlay alignment timeout");end
endmodule
