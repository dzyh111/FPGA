`timescale 1ns/1ps
module tb_round_ripples;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,valid=0;reg [2:0] scene=1;reg [5:0] fixture_age=10;
 reg [10:0] x=0,y=0;reg [23:0] rgb=24'h204060;
 wire ov;wire [10:0] ox,oy;wire [23:0] out_rgb;
 heritage_fx dut(.clk(clk),.rst(rst),.frame_tick(1'b0),.enable(1'b1),
  .stream_reset(1'b0),.scene(scene),.sample_consumed(1'b0),.sample_position(32'd0),
  .valid(valid),.x(x),.y(y),.rgb(rgb),.out_valid(ov),.out_x(ox),.out_y(oy),.out_rgb(out_rgb),
  .bow_offset(),.bow_tilt(),.bow_angle(),.drum_offset(),.drum_right_offset());
 function [23:0] mix_reference;
  input [23:0] background,foreground;input integer alpha;
  integer r,g,b;
  begin
   r=((8-alpha)*background[23:16]+alpha*foreground[23:16])/8;
   g=((8-alpha)*background[15:8]+alpha*foreground[15:8])/8;
   b=((8-alpha)*background[7:0]+alpha*foreground[7:0])/8;
   mix_reference={r[7:0],g[7:0],b[7:0]};
  end
 endfunction
 function [23:0] half_reference;
  input [23:0] foreground;
  integer r,g,b;
  begin
   r=32/2+foreground[23:16]/2;
   g=64/2+foreground[15:8]/2;
   b=96/2+foreground[7:0]/2;
   half_reference={r[7:0],g[7:0],b[7:0]};
  end
 endfunction
 function [23:0] reference;
  input integer xx,yy,sc,elapsed;
  integer dx,dy,r,square,outer,echo,alpha,echo_alpha;reg hit,echo_hit;
  begin
   dx=xx-(sc==4?(xx>=512?661:377):365);
   dy=yy-(sc==4?(xx>=512?229:224):274);
   if(dx<0)dx=-dx;if(dy<0)dy=-dy;
   square=dx*dx+4*dy*dy;r=elapsed*(sc==4?2:3)+(sc==4?5:10);outer=r+4;
   hit=square>=r*r && square<=outer*outer;
   hit=hit && dx<128 && dy<64;
   if(sc==4)hit=hit && elapsed<28 && xx>225 && xx<800 && yy>150 && yy<320;
   else hit=hit && elapsed<28 && yy<390;
   echo=r-18;
   echo_hit=sc==1 && r>=28 && elapsed<28 && yy<390 && dx<128 && dy<64 &&
             square>=echo*echo && square<=(echo+4)*(echo+4);
   alpha=elapsed<28?7-elapsed/4:0;echo_alpha=alpha>2?alpha-2:0;
   reference=24'h204060;
   if(hit)begin
    if(sc==4)reference=mix_reference(24'h204060,24'hffba63,alpha);
    else reference=mix_reference(24'h204060,24'h5deaff,alpha);
   end
   if(echo_hit)reference=mix_reference(24'h204060,24'h57e3d8,echo_alpha);
   if(sc==4 && elapsed<3 && dx+dy<11)reference=24'hfff1cb;
   if(sc==1 && elapsed<7 && dx+dy<10)
    reference=elapsed<3?24'hb6fff1:half_reference(24'hb6fff1);
  end
 endfunction
 reg v0=0,v1=0,v2=0;reg [23:0] c0,c1,c2;reg [10:0] x0,y0,x1,y1,x2,y2;
 integer checked=0,ink_pixels=0;
 always @(posedge clk)begin
  v0<=valid;v1<=v0;v2<=v1;c0<=reference(x,y,scene,fixture_age);c1<=c0;c2<=c1;
  x0<=x;y0<=y;x1<=x0;y1<=y0;x2<=x1;y2<=y1;
  #1;
  if(!rst && v2)begin
   if(!ov || {ox,oy,out_rgb}!=={x2,y2,c2})$fatal(1,"round/opacity mismatch at %0d,%0d: %h vs %h",ox,oy,out_rgb,c2);
   checked=checked+1;if(out_rgb!=rgb)ink_pixels=ink_pixels+1;
  end
 end
 integer s,a,xx,yy,centre_x,centre_y,radius,boundary_probes=0;
 initial begin
  repeat(4)@(negedge clk);rst=0;
  force dut.level=0;force dut.note=0;
  force dut.age=fixture_age;force dut.drum_left_age=fixture_age;force dut.drum_right_age=fixture_age;
  for(s=1;s<=4;s=s+3)for(a=10;a<=17;a=a+7)begin
   scene=s;fixture_age=a;
   for(yy=150;yy<390;yy=yy+1)for(xx=0;xx<1024;xx=xx+1)begin
    valid=1;x=xx;y=yy;@(negedge clk);
   end
  end
  // Every opacity boundary, including late transparent frames, is exercised
  // on both sides of exact quadratic boundaries. The wide raster above
  // separately checks off-axis curvature, both centres and absence of facets.
  for(s=1;s<=4;s=s+3)for(a=0;a<32;a=a+1)begin
   scene=s;fixture_age=a;
   centre_x=s==4?377:365;centre_y=s==4?224:274;
   radius=a*(s==4?2:3)+(s==4?5:10);
   for(xx=radius-1;xx<=radius+5;xx=xx+1)begin
    valid=1;x=centre_x+xx;y=centre_y;@(negedge clk);boundary_probes=boundary_probes+1;
   end
   if(s==1 && radius>=28)for(xx=radius-19;xx<=radius-13;xx=xx+1)begin
    valid=1;x=centre_x-xx;y=centre_y;@(negedge clk);boundary_probes=boundary_probes+1;
   end
  end
  valid=0;repeat(4)@(negedge clk);
  if(checked!=983040+boundary_probes || ink_pixels<2000)$fatal(1,"incomplete round ripple traversal %0d %0d",checked,ink_pixels);
  $display("PASS true ellipse ripples: %0d pixels; exact main/echo quadratic annuli, both drum centres, all 7 alpha bands and zero, independent RGB arithmetic, 3-clock alignment",checked);
  $finish;
 end
endmodule
