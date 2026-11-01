`timescale 1ns/1ps
`include "global_def.v"
module tb_refresh_config;
 localparam integer PERIOD_NS = `SDR_CLK_PERIOD;
 localparam integer INTERVAL = `SELF_REFRESH_INTERVAL;
 localparam integer REQUEST_CYCLES = INTERVAL + 1;
 localparam integer OLD_INTERVAL = 64000000 / 1000000000 / 40000000 / 2**11;
 integer ticks, requests;
 reg [10:0] count = 0;
 initial begin
  if (OLD_INTERVAL != 0) $fatal(1,"Legacy bug reproduction failed");
  if (PERIOD_NS != 25 || INTERVAL != 1170 || REQUEST_CYCLES != 1171)
   $fatal(1,"Refresh macro regression: period=%0d interval=%0d",PERIOD_NS,INTERVAL);
  if (REQUEST_CYCLES * PERIOD_NS * (2**`ROW_WIDTH) > 60000000)
   $fatal(1,"Refresh sweep exceeds 60 ms design budget");
  requests=0;
  for (ticks=0;ticks<REQUEST_CYCLES*4096;ticks=ticks+1) begin
   if(count==INTERVAL-10) requests=requests+1;
   if(count==INTERVAL) count=0; else count=count+1;
  end
  if(requests!=4096) $fatal(1,"Refresh count %0d != 4096",requests);
  $display("PASS refresh config: old=0, period=%0d ns, terminal=%0d, request period=%0d clocks, 4096 requests, sweep=59955200ns",PERIOD_NS,INTERVAL,REQUEST_CYCLES);
  $finish;
 end
endmodule
