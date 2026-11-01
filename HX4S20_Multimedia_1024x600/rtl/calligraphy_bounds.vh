// Generated pen-path bounds. Modified 2026-10-22; adapted median data: ARPHICPL.TXT.
function [8:0] title_start;
 input [2:0] instrument;
 begin case(instrument)
  3'd1:title_start=9'd0;
  3'd2:title_start=9'd114;
  3'd3:title_start=9'd216;
  3'd4:title_start=9'd324;
  default:title_start=0;
 endcase end
endfunction
function [8:0] title_end;
 input [2:0] instrument;
 begin case(instrument)
  3'd1:title_end=9'd113;
  3'd2:title_end=9'd215;
  3'd3:title_end=9'd323;
  3'd4:title_end=9'd457;
  default:title_end=0;
 endcase end
endfunction
