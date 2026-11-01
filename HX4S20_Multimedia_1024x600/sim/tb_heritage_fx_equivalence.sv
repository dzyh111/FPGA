`timescale 1ns/1ps
module tb_heritage_fx_equivalence #(parameter QUICK_BOUNDARIES=0);
 reg clk=0; always #5 clk=~clk;
 reg rst=1,frame_tick=0,enable=1,stream_reset=0,sample_consumed=0;
 reg [2:0] scene=1;
 reg [31:0] sample_position=0;
 reg valid=1;
 reg [10:0] x=0,y=0;
 reg [23:0] rgb=24'h204060;
 wire ov,rv;wire [10:0] ox,oy,rx,ry;wire [23:0] oc,rc;
 wire signed [4:0] ob,rb;wire [3:0] od,rd;
 wire pv;wire [10:0] px,py;wire [23:0] pc;
 wire signed [4:0] pb;wire [3:0] pd;
 reg ev=0,epv=0;reg [10:0] ex=0,ey=0,epx=0,epy=0;
 reg [23:0] ec=0,epc=0;
 reg [3:0] test_level=15;
 reg [2:0] test_note=3,test_sparkle=3;
 reg [5:0] test_age=4;
 reg [4:0] test_bow=10;
 reg test_hit=0,test_moved=0;
 heritage_fx dut(.clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(enable),
  .stream_reset(stream_reset),.scene(scene),.sample_consumed(sample_consumed),
  .sample_position(sample_position),.valid(valid),.x(x),.y(y),.rgb(rgb),
  .out_valid(ov),.out_x(ox),.out_y(oy),.out_rgb(oc),.bow_offset(ob),.drum_offset(od));
 heritage_fx_reference refdut(.clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(enable),
  .stream_reset(stream_reset),.scene(scene),.sample_consumed(sample_consumed),
  .sample_position(sample_position),.valid(valid),.x(x),.y(y),.rgb(rgb),
  .out_valid(rv),.out_x(rx),.out_y(ry),.out_rgb(rc),.bow_offset(rb),.drum_offset(rd));
 heritage_fx_pre_pipeline_reference pre(.clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(enable),
  .stream_reset(stream_reset),.scene(scene),.sample_consumed(sample_consumed),
  .sample_position(sample_position),.valid(valid),.x(x),.y(y),.rgb(rgb),
  .out_valid(pv),.out_x(px),.out_y(py),.out_rgb(pc),.bow_offset(pb),.drum_offset(pd));
 // Both goldens are one-stage. Delay only pixels by the new extra cycle;
 // sample-clocked bow/drum controls must retain their original timing.
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   ev<=0;ex<=0;ey<=0;ec<=0;epv<=0;epx<=0;epy<=0;epc<=0;
  end else begin
   ev<=rv;ex<=rx;ey<=ry;ec<=rc;epv<=pv;epx<=px;epy<=py;epc<=pc;
  end
 end
 integer checks=0,sc,xx,yy,nn,aa,ee,ll,ss,j,idx;
 integer ages[0:4];integer levels[0:6];
 reg [31:0] rng=32'h012398ab;
 task random_next;
 begin rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);end
 endtask
 task compare_pixel;
 begin
  @(posedge clk);#1;
  if({ov,ox,oy,oc} !== {ev,ex,ey,ec} ||
     {ov,ox,oy,oc} !== {epv,epx,epy,epc} || {ob,od} !== {rb,rd} ||
     {ob,od} !== {pb,pd})begin
   $display("FAIL scene=%0d enable=%0d note=%0d age=%0d level=%0d sparkle=%0d xy=%0d,%0d expected_xy=%0d,%0d valid=%0d rgb=%06h actual=%06h expected=%06h pre=%06h bow=%0d/%0d drum=%0d/%0d",scene,enable,test_note,test_age,test_level,test_sparkle,x,y,ex,ey,valid,rgb,oc,ec,epc,ob,rb,od,rd);
   $fatal(1,"FX equivalence mismatch");
  end
  checks=checks+1;
  @(negedge clk);
 end
 endtask
 initial begin
  ages[0]=0;ages[1]=1;ages[2]=4;ages[3]=20;ages[4]=63;
  levels[0]=0;levels[1]=1;levels[2]=2;levels[3]=3;levels[4]=6;levels[5]=7;levels[6]=15;
  repeat(3)@(negedge clk);rst=0;
  force dut.level=test_level; force refdut.level=test_level;
  force pre.level=test_level;
  force dut.note=test_note;force refdut.note=test_note;
  force pre.note=test_note;
  force dut.age=test_age;force refdut.age=test_age;
  force pre.age=test_age;
  force dut.sparkle=test_sparkle;force refdut.sparkle=test_sparkle;
  force pre.sparkle=test_sparkle;
  force dut.bow_phase=test_bow;force refdut.bow_phase=test_bow;
  force pre.bow_phase=test_bow;
  force dut.hit_pending=test_hit;force refdut.hit_pending=test_hit;
  force pre.hit_pending=test_hit;
  force dut.moved=test_moved;force refdut.moved=test_moved;
  force pre.moved=test_moved;
  // Every on-screen coordinate for each of the four scenes.
  for(sc=1;sc<=(QUICK_BOUNDARIES?0:4);sc=sc+1)begin
   scene=sc;enable=1;test_note=3;test_age=4;test_level=15;
   for(yy=0;yy<600;yy=yy+1)for(xx=0;xx<1024;xx=xx+1)begin
    x=xx;y=yy;valid=(xx[3:0]!=0);rgb={xx[7:0],yy[7:0],xx[7:0]^yy[7:0]};
    compare_pixel;
   end
  end
  // Every encoded note/age/enable/level/sparkle combination, with frame_tick
  // changes and random valid bubbles, including coordinates outside the display.
  for(sc=0;sc<(QUICK_BOUNDARIES?0:8);sc=sc+1)for(nn=0;nn<8;nn=nn+1)
   for(aa=0;aa<64;aa=aa+1)for(ee=0;ee<2;ee=ee+1)
    for(ll=0;ll<16;ll=ll+1)for(ss=0;ss<8;ss=ss+1)begin
     scene=sc;test_note=nn;test_age=aa;enable=ee;
     test_level=ll;test_sparkle=ss;
     for(j=0;j<2;j=j+1)begin
      random_next;x=rng[10:0];random_next;y=rng[10:0];
      random_next;rgb=rng[23:0];valid=rng[24];
      test_bow=rng[29:25];test_hit=rng[30];test_moved=rng[31];
      frame_tick=(j==0);sample_consumed=rng[5];
      compare_pixel;
     end
    end
  // Exercise the real (unforced) cue/frame controller around boundaries, not
  // merely static snapshots. Goldens use the identical ROM fixture.
  release dut.level;release refdut.level;release pre.level;
  release dut.note;release refdut.note;release pre.note;
  release dut.age;release refdut.age;release pre.age;
  release dut.sparkle;release refdut.sparkle;release pre.sparkle;
  release dut.bow_phase;release refdut.bow_phase;release pre.bow_phase;
  release dut.hit_pending;release refdut.hit_pending;release pre.hit_pending;
  release dut.moved;release refdut.moved;release pre.moved;
  rst=1;compare_pixel;rst=0;
  for(idx=0;idx<2048;idx=idx+1)begin
   dut.u_cue.cue_mem[idx]={idx[3:0],idx[0],idx[2:0]};
   refdut.u_cue.cue_mem[idx]={idx[3:0],idx[0],idx[2:0]};
   pre.u_cue.cue_mem[idx]={idx[3:0],idx[0],idx[2:0]};
  end
  sample_position=0;
  for(j=0;j<12000;j=j+1)begin
   random_next;x=rng[10:0];random_next;y=rng[10:0];
   random_next;rgb=rng[23:0];valid=rng[24];
   frame_tick=(j%3==0)||(j%37==0); // adjacent frame ticks included
   sample_consumed=(j%7<5);enable=(j%401!=0);stream_reset=(j%997==0);
   if(j%751==0)begin scene=(scene==4)?1:scene+1'b1;sample_position=0;end
   else if(sample_consumed)sample_position=sample_position+1'b1;
   compare_pixel;
  end
  valid=0;repeat(3)compare_pixel;
  if(QUICK_BOUNDARIES)$display("PASS FX quick boundaries: %0d pixels; both goldens; frame, pause, reset, cue changes; motion timing unchanged (full coverage is a separate run)",checks);
  else $display("PASS FX output equivalence: %0d pixels; both goldens; all four full frames; all scenes/notes/ages/levels/sparkle/enable; frame, pause, reset, cue boundary changes; motion timing unchanged",checks);
  $finish;
 end
endmodule
