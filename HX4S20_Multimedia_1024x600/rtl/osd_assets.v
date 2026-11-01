module osd_assets(
 input clk,
 input [12:0] logo_addr, output [1:0] logo_palette
);
(* ram_style="block" *) reg [1:0] logo_mem[0:6143];
reg [1:0] logo_q;
initial begin
`ifdef __ICARUS__
 $readmemh("rtl/anlogic_logo.mem",logo_mem);
`else
 $readmemh("anlogic_logo.mem",logo_mem);
`endif
end
always @(posedge clk)begin
 logo_q<=logo_mem[logo_addr];
end
assign logo_palette=logo_q;
endmodule
