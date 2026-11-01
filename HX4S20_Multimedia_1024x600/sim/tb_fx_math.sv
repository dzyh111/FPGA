`timescale 1ns/1ps
module tb_fx_math;
 reg clk=0;always #5 clk=~clk;
 reg [2:0] selected_note=0;
 reg [10:0] x=0;
 heritage_fx dut(.clk(clk),.rst(1'b1),.frame_tick(1'b0),.enable(1'b0),
  .stream_reset(1'b0),.scene(3'd1),.sample_consumed(1'b0),.sample_position(32'd0),
  .valid(1'b0),.x(x),.y(11'd0),.rgb(24'd0));
 integer a,b,f,n,px,want,checks=0,slope,r,echo;
 reg [63:0] qb;
 reg [31:0] db;
 initial begin
  // Exhaust all colors/alpha, not just a few attractive screenshot samples.
  for(a=0;a<8;a=a+1)for(b=0;b<256;b=b+1)for(f=0;f<256;f=f+1)begin
   want=((8-a)*b+a*f)/8;
   if(dut.mix_channel(b,f,a)!==want[7:0])
    $fatal(1,"shared mixer overflow/rounding b=%0d f=%0d a=%0d",b,f,a);
   checks=checks+1;
  end
  for(n=0;n<28;n=n+1)begin
   qb=dut.qin_wave_bounds(n);db=dut.drum_wave_bounds(n);
   r=n*3+10;echo=r-18;
   if(qb[63:48]!==r*r || qb[47:32]!==(r+4)*(r+4))$fatal(1,"qin bounds table age%0d",n);
   if(n>=6 && (qb[31:16]!==echo*echo || qb[15:0]!==(echo+4)*(echo+4)))$fatal(1,"echo table age%0d",n);
   r=n*2+5;
   if(db[31:16]!==r*r || db[15:0]!==(r+4)*(r+4))$fatal(1,"drum table age%0d",n);
  end
  force dut.note=selected_note;
  for(n=0;n<8;n=n+1)begin
   selected_note=n;
   case(n)0,1,7:slope=45;2:slope=46;3,6:slope=48;4:slope=49;5:slope=51;endcase
   for(px=0;px<2048;px=px+1)begin
    x=px;#1;want=px*slope;
    if(dut.string_product!==want[16:0])$fatal(1,"shift-add string mismatch note%0d x%0d",n,px);
   end
  end
  $display("PASS shared FX arithmetic: %0d exact blend cases, 16384 shift-add/string products, 56 exact quadratic age tables; no overflow or geometry change",checks);
  $finish;
 end
endmodule
