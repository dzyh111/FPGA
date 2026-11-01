`ifndef DISPLAY_CONFIG_VH
`define DISPLAY_CONFIG_VH
// Candidate panel timing: verify against the actual panel EDID.
`define PIXEL_HZ 51200000
`define H_ACTIVE 1024
`define H_FP 160
`define H_SYNC 20
`define H_BP 140
`define V_ACTIVE 600
`define V_FP 12
`define V_SYNC 3
`define V_BP 20
`define H_TOTAL (`H_ACTIVE+`H_FP+`H_SYNC+`H_BP)
`define V_TOTAL (`V_ACTIVE+`V_FP+`V_SYNC+`V_BP)
`endif
