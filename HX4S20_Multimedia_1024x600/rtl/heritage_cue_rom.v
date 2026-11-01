// Generated data from prepare_heritage_audio.py. Both ports read in one cycle.
// addr = {scene[1:0], window[8:0]}, one window = 1500 played samples.
module heritage_cue_rom(
    input wire clk,
    input wire [10:0] addr,
    output reg [7:0] data,
    input wire [10:0] ahead_addr,
    output reg [7:0] ahead_data
);
(* ram_style="block" *) reg [7:0] cue_mem [0:2047];
initial begin
`ifdef __ICARUS__
    $readmemh("rtl/heritage_cue.hex", cue_mem);
`else
    $readmemh("heritage_cue.hex", cue_mem);
`endif
end
always @(posedge clk) begin
    data <= cue_mem[addr];
    ahead_data <= cue_mem[ahead_addr];
end
endmodule
