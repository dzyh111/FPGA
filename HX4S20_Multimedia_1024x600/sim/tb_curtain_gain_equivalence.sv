`timescale 1ns/1ps
// The optional registered gain must reproduce the standalone shader exactly.
// Reference arithmetic deliberately uses integer division/modulo, including
// the discarded square bit and the y[10] wrap outside the active raster.
module tb_curtain_gain_equivalence;
 reg [23:0] rgb=0;
 reg [10:0] x=0,y=0;
 reg [4:0] fade_alpha=16;
 reg manual_active=1,valid=1;
 reg [5:0] manual_phase=0;
 reg [7:0] injected_gain=0;
 wire [23:0] direct_rgb,injected_rgb,direct_background,injected_background;
 wire [4:0] direct_alpha,injected_alpha;
 gallery_transition #(.PRECOMPUTED_GAIN(0)) direct(
  .rgb(rgb),.x(x),.y(y),.fade_alpha(fade_alpha),.manual_active(manual_active),
  .manual_phase(manual_phase),.valid(valid),.curve_gain_in(8'hxx),
  .out_rgb(direct_rgb),.out_alpha(direct_alpha),.out_background(direct_background));
 gallery_transition #(.PRECOMPUTED_GAIN(1)) injected(
  .rgb(rgb),.x(x),.y(y),.fade_alpha(fade_alpha),.manual_active(manual_active),
  .manual_phase(manual_phase),.valid(valid),.curve_gain_in(injected_gain),
  .out_rgb(injected_rgb),.out_alpha(injected_alpha),.out_background(injected_background));
 integer yy,p,n,a,v,side,distance,half_width,phase_envelope;
 integer checks=0,wrapped_y_checks=0,square_topbit_checks=0;
 reg [31:0] random_state=32'h9127de6b;
 function automatic [7:0] integer_gain(input integer ordinate);
  integer paired,squared;
  begin
   paired=(ordinate%1024)/2;
   squared=paired*paired;
   integer_gain=(squared/512)%256;
  end
 endfunction
 task automatic check(input allow_unknown);
  begin
   injected_gain=integer_gain(y);
   #1;
   if(direct_rgb!==injected_rgb || direct_alpha!==injected_alpha ||
      direct_background!==injected_background)
    $fatal(1,"gain equivalence xy=%0d,%0d phase=%0d fade=%0d manual=%b valid=%b gain=%0d direct=%h/%0d/%h injected=%h/%0d/%h",
      x,y,manual_phase,fade_alpha,manual_active,valid,injected_gain,
      direct_rgb,direct_alpha,direct_background,injected_rgb,injected_alpha,injected_background);
   if(!allow_unknown && ((^direct_rgb)===1'bx || (^direct_alpha)===1'bx ||
                         (^direct_background)===1'bx))
    $fatal(1,"unknown gain result at known input xy=%0d,%0d phase=%0d",x,y,manual_phase);
   if(!valid && direct_rgb!==rgb)$fatal(1,"invalid bypass changed");
   if(valid && manual_active && manual_phase==63 && direct_rgb!==rgb)
    $fatal(1,"open endpoint changed");
   checks=checks+1;
   if(y>=1024)wrapped_y_checks=wrapped_y_checks+1;
   if(((y%1024)/2)*((y%1024)/2)>=131072)
    square_topbit_checks=square_topbit_checks+1;
  end
 endtask
 initial begin
  // Every 11-bit ordinate and every phase, on both sides of the feather.
  // Large off-raster y values exercise the intentional eight-bit truncation.
  for(yy=0;yy<2048;yy=yy+1)for(p=0;p<64;p=p+1)begin
   y=yy;manual_phase=p;manual_active=1;valid=1;fade_alpha=(p+yy)&31;
   phase_envelope=p<32?p:63-p;
   half_width=9*p+((integer_gain(yy)*phase_envelope)/32);
   for(side=0;side<2;side=side+1)begin
    distance=side?half_width+5:half_width-17;
    if(distance<0)distance=0;
    x=side?512+distance:511-distance;
    rgb={yy[7:0],p[5:0],2'b10,yy[7:0]^8'ha7};check(0);
   end
  end
  // All AUTO alpha codes include the >=16 clamp; the ignored optional
  // input on the direct instance remains X throughout the entire test.
  manual_active=0;valid=1;
  for(a=0;a<32;a=a+1)for(v=0;v<256;v=v+1)begin
   fade_alpha=a;manual_phase=v;x=(v*7)&2047;y=(v*13)&2047;
   rgb={v[7:0],~v[7:0],v[7:0]^8'h39};check(0);
  end
  for(n=0;n<65536;n=n+1)begin
   random_state=random_state*32'd1664525+32'd1013904223;
   x=random_state[10:0];y=random_state[26:16];rgb=random_state[23:0];
   manual_phase=n&63;fade_alpha=(n>>6)&31;
   manual_active=(n>>11)&1;valid=(n%13)!=0;check(0);
  end
  manual_active=1;valid=1;rgb=24'hxxxxxx;manual_phase=0;x=511;y=599;check(0);
  manual_phase=63;check(1);
  valid=0;manual_phase=31;check(1);
  if(wrapped_y_checks<131072 || square_topbit_checks==0)$fatal(1,"missing wrap/truncation coverage");
  $display("PASS curtain gain modes: %0d exact RGB/alpha/background comparisons; all2048 y/all64 phases/two feather sides, %0d wrapped-y and %0d discarded-square-bit cases, AUTO clamp, deterministic random pixels, ignored-X input and X endpoints",
    checks,wrapped_y_checks,square_topbit_checks);
  $finish;
 end
 initial begin #10000000;$fatal(1,"gain equivalence timeout");end
endmodule
