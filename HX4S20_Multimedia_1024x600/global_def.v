


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

// Both copies must agree; protect expression macros from textual precedence.
`define   SDR_CLK_PERIOD                    (1000000000 / 40000000)
// The vendor counter includes BOTH zero and this terminal value. A 60 ms
// all-row sweep leaves margin below the 64 ms retention limit and for bursts.
`define   SELF_REFRESH_INTERVAL             ((60000000 / `SDR_CLK_PERIOD / (2 ** `ROW_WIDTH)) - 1)

