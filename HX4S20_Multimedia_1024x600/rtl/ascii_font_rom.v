// 128 characters x eight rows x five pixels. Lowercase duplicates uppercase.
// One synchronous 9K block replaces replicated character decode/row muxes.
module ascii_font_rom(input clk,input [6:0] code,input [2:0] row,
                      output reg [4:0] pixels);
 (* ram_style="block" *) reg [4:0] rows[0:1023];
 initial begin
`ifdef __ICARUS__
  $readmemh("rtl/ascii_font_rows.hex",rows);
`else
  $readmemh("ascii_font_rows.hex",rows);
`endif
 end
 always @(posedge clk)pixels<=rows[{code,row}];
endmodule
