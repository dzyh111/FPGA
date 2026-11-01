`timescale 1ns/1ps
module tb_gallery_border;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,cover_fixture=0,menu=0,manual=0,audio_valid=0,audio_reset=0;
 reg signed [23:0] audio_sample=0;
 reg [2:0] zoom=2,scene=1;reg [4:0] fade=16;
 reg [5:0] manual_phase=63;reg [3:0] state=6;
 reg [10:0] x=0,y=0;wire ov,sof,last;wire [23:0] color,cloth;
 integer l=2,r=1021,t=2,b=597,head=0,step_size=4,perimeter=3228,energy=0;
 integer checks=0,mode,xx,yy,f,s,level,k;reg [23:0] wanted;
 media_osd #(.ENABLE_COVER(1)) dut(.clk(clk),.rst(rst),.frame_tick(frame_tick),
  .cover_active(cover_fixture),.state_code(state),.fade_alpha(fade),.manual_transition(manual),
  .manual_phase(manual_phase),.menu_active(menu),.menu_item(3'd0),.rebuild_busy(1'b0),
  .rebuild_progress(3'd0),.rebuild_total(3'd4),.brightness_level(3'd2),.contrast_level(3'd2),
  .zoom_level(zoom),.scale_override(2'd0),.spectrum_enable(1'b0),.scene(scene),
  .audio_valid(audio_valid),.audio_sample(audio_sample),.audio_stream_reset(audio_reset),
  .valid(1'b1),.x(x),.y(y),.rgb(24'h204060),
  .out_valid(ov),.out_sof(sof),.out_last(last),.out_rgb(color));
 // Curtain priority only; its visual formula is independently tested elsewhere.
 gallery_transition priority_shader(.curve_gain_in(8'd0),.rgb(24'h204060),.x(x),.y(y),.fade_alpha(fade),
  .manual_active(manual),.manual_phase(manual_phase),.valid(1'b1),
  .out_rgb(cloth),.out_alpha(),.out_background());
 function [23:0] reference_pixel;
  input integer px,py;
  integer pos,d,triangle,q,rr,gg,bb,v,boost;reg hit;
  begin
   hit=0;pos=0;reference_pixel=24'h204060;
   if(!cover_fixture && scene>=1 && scene<=4 && px>=l && px<=r && py>=t && py<=b)begin
    if(py<t+4)begin hit=1;pos=px-l;end
    else if(px>=r-3)begin hit=1;pos=(r-l)+(py-t);end
    else if(py>=b-3)begin hit=1;pos=(r-l)+(b-t)+(r-px);end
    else if(px<l+4)begin hit=1;pos=2*(r-l)+(b-t)+(b-py);end
    d=(head-pos+perimeter)%perimeter;
    triangle=d<perimeter-d?d:perimeter-d;
    if(zoom==0)q=triangle/32+triangle/128;
    else if(zoom==1)q=triangle/64+triangle/128+triangle/256;
    else q=triangle/64+triangle/256;
    if(q>31)$fatal(1,"reference palette overflow");
    v=q%16;boost=energy*4;
    case(scene)
     1:begin rr=80+4*q;gg=152+q;bb=148-2*q;end
     2:begin rr=132+3*q;gg=56+4*q;bb=48+q;end
     3:if(q<16)begin rr=60+2*v;gg=126+3*v;bb=94+4*v;end
       else begin rr=92+6*v;gg=174+3*v;bb=158+4*v;end
     default:if(q<16)begin rr=164+3*v;gg=44+5*v;bb=32+v;end
       else begin rr=212+v;gg=124+5*v;bb=48+5*v;end
    endcase
    rr=rr+boost;gg=gg+boost;bb=bb+boost;
    if(rr>255 || gg>255 || bb>255 || rr<0 || gg<0 || bb<0)$fatal(1,"reference colour overflow");
    if(hit)reference_pixel={rr[7:0],gg[7:0],bb[7:0]};
   end
  end
 endfunction
 task settle;begin repeat(8)@(negedge clk);end endtask
 task tick;
  input play;input [23:0] sample;integer a;
  begin
   settle;
   if(play)begin audio_sample=sample;audio_valid=1;@(negedge clk);audio_valid=0;end
   frame_tick=1;@(negedge clk);frame_tick=0;
   if(play)begin
    a=$signed(sample)>>>16;if(a<0)a=-a;
    level=a/16;if(level>7)level=7;
    if(level>=energy)energy=level;else if(energy>0)energy=energy-1;
    head=(head+step_size+2*energy)%perimeter;
   end
   settle;
   if(dut.border_head!==head || dut.border_energy!==energy)
    $fatal(1,"audio/frame mismatch head%0d/%0d energy%0d/%0d",dut.border_head,head,dut.border_energy,energy);
  end
 endtask
 task pixel;
  input integer px,py;input [23:0] expected;
  begin x=px;y=py;settle;checks=checks+1;
   if(!ov || color!==expected || sof!==(px==0 && py==0) || last!==(px==1023))
    $fatal(1,"pixel scene%0d zoom%0d (%0d,%0d) got%h expected%h",scene,zoom,px,py,color,expected);
  end
 endtask
 task point;
  input integer px,py;
  begin if(!(px>=920 && px<1016 && py>=16 && py<80))pixel(px,py,reference_pixel(px,py));end
 endtask
 task geometry;
  input integer z,instrument;
  begin
   zoom=z;scene=instrument;settle;head=0;energy=0;
   case(z)
    0:begin l=258;r=765;t=152;b=447;step_size=2;end
    1:begin l=130;r=893;t=77;b=522;step_size=3;end
    default:begin l=2;r=1021;t=2;b=597;step_size=4;end
   endcase
   perimeter=2*((r-l)+(b-t));
   if(dut.border_head!==0 || dut.border_energy!==0)$fatal(1,"scene/zoom reset missing");
  end
 endtask
 initial begin
  settle;rst=0;settle;
  for(mode=0;mode<5;mode=mode+1)begin
   geometry(mode,mode%4+1);
   for(xx=l-1;xx<=r+1;xx=xx+1)begin
    for(k=-1;k<=4;k=k+1)begin point(xx,t+k);point(xx,b-k);end
   end
   for(yy=t+5;yy<b-4;yy=yy+1)begin
    for(k=-1;k<=4;k=k+1)begin point(l+k,yy);point(r-k,yy);end
   end
   for(s=1;s<=4;s=s+1)begin
    geometry(mode,s==scene?(s%4+1):s);geometry(mode,s);
    tick(1,24'h000000);point(l,t);point(r,b);
    tick(1,24'h7fffff);point((l+r)/2,t);point(l,(t+b)/2);
    tick(0,24'h000000);point(l,t);point(r,b);
    tick(1,24'h800000);point(l,t);point(r,b);
    for(f=0;f<9;f=f+1)begin tick(1,0);point(l+50,t);end
   end
   for(f=0;f<perimeter/step_size+2;f=f+1)begin
    tick(1,0);point(l,t);point(r,t);point(r,b);point(l,b);
   end
  end
  geometry(0,1);
  tick(1,24'h700000);audio_reset=1;@(negedge clk);audio_reset=0;head=0;energy=0;settle;point(l,t);
  cover_fixture=1;tick(0,0);point(l,t);point(r,b);
  cover_fixture=0;scene=0;settle;head=0;energy=0;tick(0,0);point(l,t);
  scene=4;settle;head=0;energy=0;point(l,t);
  fade=0;manual=0;pixel(l,t,24'h101c30);pixel(r,b,24'h101c30);
  manual=1;manual_phase=0;x=l;y=t;settle;pixel(l,t,cloth);
  x=r;y=b;settle;pixel(r,b,cloth);
  fade=16;manual=0;state=14;tick(0,0);pixel(l,t,24'hf4f6f8);
  state=6;tick(0,0);geometry(0,1);
  pixel(0,0,24'h204060);pixel(1023,10,24'h204060);pixel(0,599,24'h204060);
  for(xx=0;xx<180;xx=xx+1)begin
   @(negedge clk);x=250+xx;y=t;@(posedge clk);#1;
   if(xx>=5)begin wanted=reference_pixel(245+xx,t);
    if(color!==wanted || !ov)$fatal(1,"six-stage border alignment x%0d",245+xx);
   end
  end
  $display("PASS music border: %0d independent pixels; five zooms inset2/width4, four bounded palettes, 0..28 energy boost and doubled energy speed, circular seams/wraps, PCM-zero/pause/negative peaks/decay/reset, cover/error/fade/curtain priority, six-stage RGB/markers",checks);
  $finish;
 end
 initial begin #30000000;$fatal(1,"music border timeout");end
endmodule
