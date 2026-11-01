`timescale 1ns/1ps
// New red-cloth pixels have an independent integer specification. Only AUTO
// must remain equal to the frozen gold release; its manual visual is replaced.
module tb_curtain_equivalence;
 reg [23:0] rgb=0;
 reg [10:0] x=0,y=0;
 reg [4:0] fade_alpha=16;
 reg [5:0] manual_phase=63;
 reg manual_active=1,valid=1;
 wire [23:0] out_rgb,old_rgb,out_background,reference_rgb,reference_background;
 wire [4:0] out_alpha,reference_alpha;
 gallery_transition dut(.*,.curve_gain_in(8'd0));
 gallery_transition_v1 original(.rgb(rgb),.x(x),.y(y),.fade_alpha(fade_alpha),
  .manual_active(manual_active),.manual_phase(manual_phase),.valid(valid),.out_rgb(old_rgb));
 gallery_transition_red_ref reference(.rgb(rgb),.x(x),.y(y),.fade_alpha(fade_alpha),
  .manual_active(manual_active),.manual_phase(manual_phase),.valid(valid),
  .out_rgb(reference_rgb),.out_alpha(reference_alpha),.out_background(reference_background));
 reg [31:0] random_state=32'h16c7a24d;
 reg [23:0] recomposed;
 integer checks=0,frame_no=0,row,col,p,n,a,v;
 function automatic [7:0] blend_ref(input integer fg,bg,amount);
  blend_ref=(fg*amount+bg*(16-amount))>>4;
 endfunction
 task check;
  begin
   #1;
   if(out_rgb!==reference_rgb)
    $fatal(1,"shader equivalence phase=%0d alpha=%0d mode=%b valid=%b xy=%0d,%0d rgb=%h got=%h old=%h",
     manual_phase,fade_alpha,manual_active,valid,x,y,rgb,out_rgb,reference_rgb);
   if(!manual_active && out_rgb!==old_rgb)$fatal(1,"frozen AUTO fade changed");
   if(out_alpha!==reference_alpha || out_background!==reference_background)
    $fatal(1,"exposed geometry differs from red reference phase=%0d xy=%0d,%0d",manual_phase,x,y);
   if(!valid)recomposed=rgb;
   else if(out_alpha==0)recomposed=out_background;
   else if(out_alpha==16)recomposed=rgb;
   else recomposed={blend_ref(rgb[23:16],out_background[23:16],out_alpha),
                    blend_ref(rgb[15:8],out_background[15:8],out_alpha),
                    blend_ref(rgb[7:0],out_background[7:0],out_alpha)};
   if(recomposed!==reference_rgb)
    $fatal(1,"geometry/reblend differs from red reference phase=%0d xy=%0d,%0d",manual_phase,x,y);
   checks=checks+1;
  end
 endtask
 task sample_frame(input [5:0] phase);
  begin
   manual_active=1;manual_phase=phase;valid=1;
   fade_alpha=phase==63?16:{1'b0,phase[5:2]};
   for(row=0;row<4;row=row+1)begin
    case(row)0:y=0;1:y=191;2:y=383;3:y=599;endcase
    for(col=0;col<1024;col=col+1)begin
     x=col;
     // A distinct source pattern after the opaque bank-switch frame.
     rgb={col[7:0]^((frame_no>=9)?8'hfe:8'h13),y[7:0],col[7:0]+y[7:0]};
     check;
    end
   end
   frame_no=frame_no+1;
  end
 endtask
 initial begin
  sample_frame(63);
  for(p=55;p>=7;p=p-8)sample_frame(p);
  sample_frame(0);sample_frame(0);
  for(p=1;p<=48;p=p+1)sample_frame((p*63)/48);
  if(frame_no!=58)$fatal(1,"red native phase sequence changed");
  // Exhaust every channel value and AUTO alpha code against the old output.
  manual_active=0;valid=1;
  for(a=0;a<32;a=a+1)for(v=0;v<256;v=v+1)begin
   fade_alpha=a;manual_phase=v;x=v*4;y=v*2;
   rgb={v[7:0],~v[7:0],v[7:0]^8'h96};check;
  end
  // Reproducible pseudo-random pixels cover every phase/fade code, both modes
  // and invalid bubbles. Arithmetic reference uses independent integer blend.
  for(n=0;n<65536;n=n+1)begin
   random_state=random_state*32'd1664525+32'd1013904223;
   x=random_state[9:0];y=random_state[27:16]%600;
   rgb=random_state[23:0];manual_phase=n&63;fade_alpha=(n>>6)&31;
   manual_active=(n>>11)&1;valid=(n%17)!=0;check;
  end
  // Explicit bypasses must hide undefined source data at phase zero and
  // preserve source data at fully-open/invalid endpoints.
  manual_active=1;valid=1;rgb=24'hxxxxxx;manual_phase=0;x=511;y=599;check;
  manual_phase=63;check;valid=0;manual_phase=31;check;
  $display("PASS red curtain integer equivalence: %0d exact reference and geometry-reblend checks; 58 native frame phases/four rows; frozen AUTO alpha/channel equality; 65536 deterministic random pixels; X endpoints",checks);
  $finish;
 end
endmodule
