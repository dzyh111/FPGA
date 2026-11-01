`timescale 1ns/1ps
module tb_border_palette_limits;
 media_osd dut();
 integer scene,t,energy,r,g,b,u,checks=0;
 reg [23:0] color,zero_energy,previous;
 initial begin
  for(scene=1;scene<=4;scene=scene+1)begin
   for(t=0;t<32;t=t+1)begin
    u=t%16;
    // Wide integer reference keeps overflow visible before RGB truncation.
    case(scene)
     1:begin r=80+4*t;g=152+t;b=148-2*t;end
     2:begin r=132+3*t;g=56+4*t;b=48+t;end
     3:if(t<16)begin r=60+2*u;g=126+3*u;b=94+4*u;end
       else begin r=92+6*u;g=174+3*u;b=158+4*u;end
     4:if(t<16)begin r=164+3*u;g=44+5*u;b=32+u;end
       else begin r=212+u;g=124+5*u;b=48+5*u;end
    endcase
    if(r<0 || r>227 || g<0 || g>227 || b<0 || b>227)
     $fatal(1,"base palette exceeds safe headroom");
    zero_energy=dut.border_palette(scene,t,0);
    for(energy=0;energy<8;energy=energy+1)begin
     color=dut.border_palette(scene,t,energy);checks=checks+1;
     if(color[23:16]!==r+4*energy || color[15:8]!==g+4*energy || color[7:0]!==b+4*energy)
      $fatal(1,"palette overflow/reference scene%0d t%0d energy%0d RGB%h",scene,t,energy,color);
     if(color[23:16]-zero_energy[23:16]!=4*energy ||
        color[15:8]-zero_energy[15:8]!=4*energy ||
        color[7:0]-zero_energy[7:0]!=4*energy)
      $fatal(1,"whole-border lift must affect all RGB channels");
    end
    if(t>0)begin
     if($signed({1'b0,zero_energy[23:16]})-$signed({1'b0,previous[23:16]})>6 ||
        $signed({1'b0,zero_energy[15:8]})-$signed({1'b0,previous[15:8]})>5 ||
        $signed({1'b0,zero_energy[7:0]})-$signed({1'b0,previous[7:0]})>5)
      $fatal(1,"gradient segment seam");
    end
    previous=zero_energy;
   end
  end
  $display("PASS border palette: %0d exhaustive scene/phase/energy combinations; wide-integer RGB equivalence, base<=227, 0..28 whole-border lift without overflow, continuous segment endpoints",checks);
  $finish;
 end
endmodule
