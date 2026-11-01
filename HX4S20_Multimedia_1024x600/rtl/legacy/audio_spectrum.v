// Sixteen real frequency measurements, sharing two multipliers across bins.
// A 256-sample block at 48 kHz gives 187.5 Hz spacing. The displayed bins
// become wider apart at high frequencies. |Re|+|Im| approximates magnitude.
module audio_spectrum(
 input clk,input rst,input sample_valid,input signed [23:0] sample,
 output reg [127:0] levels,output reg levels_valid
);
 // Keep the coefficient ROM in synthesizable logic.  TD ignores inferred
 // RAM initial values on this device, which previously made every bin zero
 // in hardware even though the simulation could read spectrum_cos.mem.
 function signed [15:0] quarter_cos;
 input [6:0] index;
 begin case(index)
   0:quarter_cos=16'sh7fff;  1:quarter_cos=16'sh7ff5;
   2:quarter_cos=16'sh7fd8;  3:quarter_cos=16'sh7fa6;
   4:quarter_cos=16'sh7f61;  5:quarter_cos=16'sh7f09;
   6:quarter_cos=16'sh7e9c;  7:quarter_cos=16'sh7e1d;
   8:quarter_cos=16'sh7d89;  9:quarter_cos=16'sh7ce3;
  10:quarter_cos=16'sh7c29; 11:quarter_cos=16'sh7b5c;
  12:quarter_cos=16'sh7a7c; 13:quarter_cos=16'sh7989;
  14:quarter_cos=16'sh7884; 15:quarter_cos=16'sh776b;
  16:quarter_cos=16'sh7641; 17:quarter_cos=16'sh7504;
  18:quarter_cos=16'sh73b5; 19:quarter_cos=16'sh7254;
  20:quarter_cos=16'sh70e2; 21:quarter_cos=16'sh6f5e;
  22:quarter_cos=16'sh6dc9; 23:quarter_cos=16'sh6c23;
  24:quarter_cos=16'sh6a6d; 25:quarter_cos=16'sh68a6;
  26:quarter_cos=16'sh66cf; 27:quarter_cos=16'sh64e8;
  28:quarter_cos=16'sh62f1; 29:quarter_cos=16'sh60eb;
  30:quarter_cos=16'sh5ed7; 31:quarter_cos=16'sh5cb3;
  32:quarter_cos=16'sh5a82; 33:quarter_cos=16'sh5842;
  34:quarter_cos=16'sh55f5; 35:quarter_cos=16'sh539b;
  36:quarter_cos=16'sh5133; 37:quarter_cos=16'sh4ebf;
  38:quarter_cos=16'sh4c3f; 39:quarter_cos=16'sh49b4;
  40:quarter_cos=16'sh471c; 41:quarter_cos=16'sh447a;
  42:quarter_cos=16'sh41ce; 43:quarter_cos=16'sh3f17;
  44:quarter_cos=16'sh3c56; 45:quarter_cos=16'sh398c;
  46:quarter_cos=16'sh36ba; 47:quarter_cos=16'sh33df;
  48:quarter_cos=16'sh30fb; 49:quarter_cos=16'sh2e11;
  50:quarter_cos=16'sh2b1f; 51:quarter_cos=16'sh2826;
  52:quarter_cos=16'sh2528; 53:quarter_cos=16'sh2223;
  54:quarter_cos=16'sh1f1a; 55:quarter_cos=16'sh1c0b;
  56:quarter_cos=16'sh18f9; 57:quarter_cos=16'sh15e2;
  58:quarter_cos=16'sh12c8; 59:quarter_cos=16'sh0fab;
  60:quarter_cos=16'sh0c8c; 61:quarter_cos=16'sh096a;
  62:quarter_cos=16'sh0648; 63:quarter_cos=16'sh0324;
  default:quarter_cos=16'sh0000;
 endcase end
 endfunction
 function signed [15:0] cosine_at;
 input [7:0] angle;
 begin case(angle[7:6])
   2'b00:cosine_at= quarter_cos({1'b0,angle[5:0]});
   2'b01:cosine_at=-quarter_cos(7'd64-{1'b0,angle[5:0]});
   2'b10:cosine_at=-quarter_cos({1'b0,angle[5:0]});
   default:cosine_at=quarter_cos(7'd64-{1'b0,angle[5:0]});
 endcase end
 endfunction
 // Synchronous RAM avoids two large 16-to-1 accumulator multiplexers.
 // The first sample of every block overwrites the old sum, so RAM needs no reset.
 (* ram_style="block" *) reg [63:0] accum[0:15];
 reg [63:0] accum_q;
 reg [7:0] phase[0:15];
 reg [7:0] count;
 reg [3:0] bin;
 reg [2:0] state;
 reg signed [15:0] pcm,c,s;
 reg signed [31:0] pr,pi;
 reg [127:0] pending_levels;
 wire signed [31:0] prior_re=count==0?32'sd0:$signed(accum_q[63:32]);
 wire signed [31:0] prior_im=count==0?32'sd0:$signed(accum_q[31:0]);
 wire signed [31:0] sum_re=prior_re+(pr>>>8);
 wire signed [31:0] sum_im=prior_im+(pi>>>8);
 wire [31:0] abs_re=sum_re[31]?-sum_re:sum_re;
 wire [31:0] abs_im=sum_im[31]?-sum_im:sum_im;
 wire [32:0] magnitude={1'b0,abs_re}+{1'b0,abs_im};
 // Stop the BRAM-read -> sum -> absolute -> compression path here. The
 // four-clock bin schedule still finishes 16 bins before the next sample.
 reg [32:0] magnitude_q;
 // A small high-frequency lift counters the natural roll-off of music.
 // Shifts keep this cheaper than per-band gain multipliers.
 wire [35:0] weighted_magnitude=(bin<4)?{3'b0,magnitude_q}:
                                (bin<8)?({3'b0,magnitude_q}<<1):
                                (bin<12)?({3'b0,magnitude_q}<<2):
                                         ({3'b0,magnitude_q}<<3);
 // Piecewise compression exposes quiet upper bands without inventing energy:
 // true zero and the one-count noise floor still display as zero.
 wire [8:0] raw_level=|weighted_magnitude[35:28]?9'd256:
                       {1'b0,weighted_magnitude[27:19]};
 wire [7:0] height=raw_level>=128?8'd255:
                   raw_level>=64?raw_level[7:0]+8'd104:
                   raw_level>=16?(raw_level[7:0]<<1)+8'd40:
                   raw_level>=2?(raw_level[7:0]<<2)+8'd8:8'd0;
 function [7:0] step;
 input [3:0] n;
 begin case(n)
 0:step=1;1:step=2;2:step=3;3:step=4;4:step=5;5:step=6;
 6:step=8;7:step=10;8:step=12;9:step=15;10:step=19;11:step=24;
 12:step=30;13:step=38;14:step=48;default:step=64;
 endcase end endfunction
 integer j;
 always @(posedge clk)begin
  accum_q<=accum[bin];
  if(!rst && state==3)accum[bin]<={sum_re,sum_im};
 end
 always @(posedge clk or posedge rst)begin
 if(rst)begin
  levels<=0;levels_valid<=0;pending_levels<=0;count<=0;bin<=0;state<=0;
  pcm<=0;c<=0;s<=0;pr<=0;pi<=0;magnitude_q<=0;
  for(j=0;j<16;j=j+1)phase[j]<=0;
 end else begin
  levels_valid<=0;
  case(state)
   0:if(sample_valid)begin pcm<=sample>>>8;bin<=0;state<=1;end
   1:begin c<=cosine_at(phase[bin]);s<=cosine_at(phase[bin]+8'd64);state<=2;end
   2:begin pr<=pcm*c;pi<=pcm*s;state<=3;end
   3:begin
    phase[bin]<=phase[bin]+step(bin);
    magnitude_q<=magnitude;state<=4;
   end
   4:begin
    if(count==255)pending_levels[bin*8+:8]<=height;
    if(bin==15)begin
     count<=count+1'b1;state<=0;
     if(count==255)begin
      levels<={height,pending_levels[119:0]};levels_valid<=1;
     end
    end else begin bin<=bin+1'b1;state<=1;end
   end
  endcase
 end
 end
endmodule
