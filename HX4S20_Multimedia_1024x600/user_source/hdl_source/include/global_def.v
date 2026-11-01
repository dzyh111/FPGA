


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

// Both copies must agree; protect expression macros from textual precedence.
`define   SDR_CLK_PERIOD                    (1000000000 / 40000000)
// Inclusive vendor counter: 1170 terminal -> 1171 clocks at 40 MHz; the
// complete nominal sweep is 59.9552 ms, leaving margin below 64 ms.
`define   SELF_REFRESH_INTERVAL             ((60000000 / `SDR_CLK_PERIOD / (2 ** `ROW_WIDTH)) - 1)

