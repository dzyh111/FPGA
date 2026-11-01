`timescale 1ns/1ps
module tb_heritage_motion_layer;
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg [2:0] scene=0;
    reg signed [5:0] bow_offset=0;
    reg signed [5:0] bow_angle=0;
    reg [4:0] drum_offset=0,drum_right_offset=0;
    reg valid=0;
    reg [10:0] x=0,y=0;
    reg [23:0] rgb=0;
    wire out_valid;
    wire [10:0] out_x,out_y;
    wire [23:0] out_rgb;
    heritage_motion_layer #(.SPAN_FILE("rtl/heritage_motion_spans.hex"),
      .PIXEL_FILE("rtl/heritage_motion_pixels.hex")) dut(.*);
    reg [23:0] meta [0:1251];
    reg [3:0] tex [0:19181];
    initial begin
        $readmemh("rtl/heritage_motion_spans.hex",meta);
        $readmemh("rtl/heritage_motion_pixels.hex",tex);
    end
    function [23:0] reference_color;
        input [2:0] sc;
        input signed [5:0] bo;
        input signed [5:0] angle;
        input [4:0] d_off,r_off;
        input [10:0] px,py;
        input [23:0] background;
        integer sx,sy,h,offset,row,idx,selected,delta,skew;
        reg [3:0] p;
        begin
            sx=px; sy=py; h=0; selected=0;
            if(sc==2) begin
                sx=sx-$signed(bo);
                delta=sx-523;skew=(delta*(-$signed(angle)))>>>10;
                sy=sy+skew;
                if(sx>=133 && sx<=920) begin h=sx-133; selected=1; end
            end
            if(sc==4) begin
                if(sx>=154 && sx<=387) begin
                    h=788+sx-154; selected=1;delta=sx-377;skew=0;
                    skew=(delta*$signed({1'b0,d_off})*2)>>>10;
                    sy=py+d_off+skew;
                end else if(sx>=647 && sx<=875) begin
                    h=1022+sx-647; selected=1;delta=sx-661;skew=0;
                    skew=(delta*(-$signed({1'b0,r_off}))*2)>>>10;
                    sy=py+r_off+skew;
                end
            end
            reference_color=background;
            if(selected) begin
                offset=meta[h]&32767;
                row=sy-(meta[h]>>15);
                if(row>=0 && row<((meta[h+1]&32767)-offset)) begin
                    idx=offset+row;
                    p=tex[idx];
                    if(p!=0) reference_color=dut.palette_rgb(p);
                end
            end
        end
    endfunction
    reg e_valid0=0,e_valid1=0,e_valid2=0;
    reg [10:0] e_x0=0,e_x1=0,e_y0=0,e_y1=0,e_x2=0,e_y2=0;
    reg [23:0] e_rgb0=0,e_rgb1=0,e_rgb2=0;
    integer errors=0,checked=0;
    always @(posedge clk) begin
        if(rst) begin
            e_valid0<=0;e_valid1<=0;
            e_x0<=0;e_x1<=0;e_y0<=0;e_y1<=0;
            e_rgb0<=0;e_rgb1<=0;
            e_valid2<=0;e_x2<=0;e_y2<=0;e_rgb2<=0;
        end else begin
            e_valid0<=valid;e_x0<=x;e_y0<=y;
            e_rgb0<=reference_color(scene,bow_offset,bow_angle,
                                    drum_offset,drum_right_offset,x,y,rgb);
            e_valid1<=e_valid0;e_x1<=e_x0;e_y1<=e_y0;e_rgb1<=e_rgb0;
            e_valid2<=e_valid1;e_x2<=e_x1;e_y2<=e_y1;e_rgb2<=e_rgb1;
        end
        #1;
        if(!rst) begin
            checked=checked+1;
            if({out_valid,out_x,out_y,out_rgb} !== {e_valid2,e_x2,e_y2,e_rgb2}) begin
                errors=errors+1;
                if(errors<8) $display("Mismatch %0d: out %h %d,%d v%b expected %h %d,%d v%b",
                  checked,out_rgb,out_x,out_y,out_valid,e_rgb2,e_x2,e_y2,e_valid2);
            end
        end
    end
    integer i,s,xx,yy;
    initial begin
        repeat(3) @(negedge clk);
        rst=0;
        // Full image traversal verifies every sparse span and transparent hole.
        for(s=0;s<=4;s=s+1) begin
            scene=s;bow_offset=(s==2)?-24:24;bow_angle=-24;
            drum_offset=30;drum_right_offset=8;
            for(yy=0;yy<600;yy=yy+1)
                for(xx=0;xx<1024;xx=xx+1) begin
                    @(negedge clk);x=xx;y=yy;valid=1;
                    rgb={xx[7:0],yy[7:0],8'h3a};
                end
        end
        // Scene/offset changes and bubbles cannot misalign RGB and coordinates.
        for(i=0;i<20000;i=i+1) begin
            @(negedge clk);
            x=$random&2047;y=$random&2047;valid=$random&1;
            scene=($random&7);bow_offset=($random&63)-31;
            bow_angle=($random&31)-15;
            drum_offset=$random&31;drum_right_offset=$random&31;rgb=$random;
        end
        repeat(3) @(negedge clk);
        if(errors!=0) $fatal(1,"FAIL %0d errors in %0d pixels",errors,checked);
        $display("PASS: %0d pixels; continuous signed shear, exact 3-stage valid/xy/RGB alignment",checked);
        $finish;
    end
endmodule
