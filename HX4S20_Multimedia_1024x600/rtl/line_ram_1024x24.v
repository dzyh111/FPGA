// Two-port source line buffer. TD uses three native 9K BRAMs for each RGB
// line; Icarus uses the equivalent behavioral model below.
module line_ram_1024x24(
 input clk,input we,input [9:0] waddr,input [23:0] din,
 input [9:0] raddr,output [23:0] dout
);
`ifdef __ICARUS__
 reg [23:0] mem[0:1023];
 reg [23:0] q;
 always @(posedge clk)begin
  if(we)mem[waddr]<=din;
  q<=mem[raddr];
 end
 assign dout=q;
`else
 genvar lane;
 generate for(lane=0;lane<3;lane=lane+1)begin:RAM8
  EG_LOGIC_BRAM #(
   .DATA_WIDTH_A(8),.DATA_WIDTH_B(8),
   .ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
   .DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),
   .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
   .WRITEMODE_A("WRITETHROUGH"),.WRITEMODE_B("READBEFOREWRITE"),
   .RESETMODE("SYNC"),.IMPLEMENT("9K"),
   .INIT_FILE("NONE"),.FILL_ALL("NONE")
  ) ram(
   .dia(din[lane*8+:8]),.dib(8'b0),
   .addra(waddr),.addrb(raddr),.cea(1'b1),.ceb(1'b1),
   .ocea(1'b0),.oceb(1'b0),.clka(clk),.clkb(clk),
   .wea(we),.web(1'b0),.bea(1'b0),.beb(1'b0),
   .rsta(1'b0),.rstb(1'b0),.doa(),.dob(dout[lane*8+:8])
  );
 end endgenerate
`endif
endmodule
