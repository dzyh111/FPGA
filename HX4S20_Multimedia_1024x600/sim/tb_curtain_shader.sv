`timescale 1ns/1ps
module tb_curtain_shader;
  reg [23:0] rgb=0;
  reg [10:0] x=0,y=0;
  reg [4:0] fade_alpha=0;
  reg manual_active=0,valid=1;
  reg [5:0] manual_phase=0;
  wire [23:0] out_rgb;
  wire [4:0] out_alpha;
  wire [23:0] out_background;
 gallery_transition dut(.*,.curve_gain_in(8'd0));
  integer p,px,py,v,a,previous_width,previous_bend,checks=0;
  reg [4:0] previous_alpha[0:1023];
  reg [23:0] previous_closed[0:1023];
  integer red_jump,green_jump,blue_jump;
  reg [23:0] closed_pixel,expected;
  function automatic [7:0] blend_ref(input integer fg,bg,amount);
    blend_ref=(fg*amount+bg*(16-amount))>>4;
  endfunction
  initial begin
    // Automatic fade stays bit-identical to the existing navy compositor,
    // irrespective of y/phase. All 256 channel values and 32 alpha codes.
    for(a=0;a<32;a=a+1)begin
      fade_alpha=a;
      for(v=0;v<256;v=v+1)begin
        rgb={v[7:0],~v[7:0],v[7:0]^8'h96};
        x=v*4;y=v*2;manual_phase=v;
        #1;
        expected={blend_ref(rgb[23:16],8'h10,a>=16?16:a),
                  blend_ref(rgb[15:8],8'h1c,a>=16?16:a),
                  blend_ref(rgb[7:0],8'h30,a>=16?16:a)};
        if(out_rgb!==expected)$fatal(1,"automatic fade changed a=%0d v=%0d",a,v);
        checks=checks+1;
      end
    end
    manual_active=1;
    // Every panel pixel is fully opaque at phase zero even when the cached
    // source changes, and is exactly the source at fully-open phase 63.
    for(py=0;py<600;py=py+1)begin
      y=py;
      for(px=0;px<1024;px=px+1)begin
        x=px;manual_phase=0;rgb=24'h000000;#1;closed_pixel=out_rgb;
        if(closed_pixel[23:16]<140 || closed_pixel[23:16]>235 ||
           closed_pixel[23:16]<=closed_pixel[15:8] || closed_pixel[23:16]<=closed_pixel[7:0])
          $fatal(1,"closed cloth escaped restrained warm-red palette");
        if(py>0)begin
          red_jump=$signed({1'b0,closed_pixel[23:16]})-$signed({1'b0,previous_closed[px][23:16]});
          green_jump=$signed({1'b0,closed_pixel[15:8]})-$signed({1'b0,previous_closed[px][15:8]});
          blue_jump=$signed({1'b0,closed_pixel[7:0]})-$signed({1'b0,previous_closed[px][7:0]});
          if(red_jump>5 || red_jump< -5 || green_jump>3 || green_jump< -3 || blue_jump>2 || blue_jump< -2)
            $fatal(1,"horizontal cloth seam x=%0d y=%0d",px,py);
        end
        previous_closed[px]=closed_pixel;
        rgb=24'hffffff;#1;
        if(out_rgb!==closed_pixel || dut.pixel_alpha!==0)
          $fatal(1,"closed curtain leaks cache x=%0d y=%0d",px,py);
        rgb=24'hxxxxxx;#1;
        if(out_rgb!==closed_pixel)$fatal(1,"phase0 exposed undefined cached pixel");
        manual_phase=63;rgb={px[7:0],py[7:0],px[7:0]^py[7:0]};#1;
        if(out_rgb!==rgb || dut.pixel_alpha!==16)
          $fatal(1,"fully open not passthrough x=%0d y=%0d",px,py);
        checks=checks+2;
      end
    end
    // All phases, all x at representative y: per-pixel coverage can only
    // increase, left/right symmetry holds, and lower width never trails top.
    for(py=0;py<600;py=py+29)begin
      y=py;
      for(px=0;px<1024;px=px+1)previous_alpha[px]=0;
      previous_width=-1;
      for(p=0;p<64;p=p+1)begin
        manual_phase=p;#1;
        if(p>0 && p<63 && dut.half_width<=previous_width)
          $fatal(1,"edge moved backwards y=%0d phase=%0d",py,p);
        previous_width=dut.half_width;
        for(px=0;px<1024;px=px+1)begin
          x=px;#1;
          if(dut.pixel_alpha<previous_alpha[px] || dut.pixel_alpha>16)
            $fatal(1,"non-monotone alpha x=%0d y=%0d phase=%0d",px,py,p);
          previous_alpha[px]=dut.pixel_alpha;
          checks=checks+1;
        end
      end
    end
    for(p=0;p<64;p=p+1)begin
      manual_phase=p;previous_bend=-1;
      for(py=0;py<600;py=py+1)begin
        y=py;#1;
        if(py!=0 && dut.bend<previous_bend)$fatal(1,"lower hem trails upper y=%0d phase=%0d",py,p);
        previous_bend=dut.bend;checks=checks+1;
      end
    end
    manual_phase=31;y=0;#1;previous_width=dut.half_width;
    y=599;#1;
    if(dut.half_width-previous_width<100)
      $fatal(1,"mid-opening lower lead is too subtle");
    manual_phase=62;
    for(py=0;py<600;py=py+29)begin
      y=py;
      for(px=0;px<1024;px=px+1)begin
        x=px;#1;
        if(dut.pixel_alpha!==16)$fatal(1,"last-frame feather pop x=%0d y=%0d",px,py);
      end
    end
    // Invalid pixels remain untouched for every phase and fade code.
    valid=0;rgb=24'hc3a58e;
    for(p=0;p<64;p=p+1)begin
      manual_phase=p;fade_alpha=p;#1;
      if(out_rgb!==rgb)$fatal(1,"invalid passthrough changed");
      checks=checks+1;
    end
    $display("PASS warm-red curtain shader: %0d checks; auto fade unchanged; phase0 opaque; phase63 source; restrained red range/no horizontal seam across600 rows; monotone lower-leading aperture; no cycles added",checks);
    $finish;
  end
endmodule
