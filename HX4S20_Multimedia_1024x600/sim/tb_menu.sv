`timescale 1ns/1ps
module tb_menu;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame=0,menu=0,rebuild=0;reg [2:0] bri=2,con=2;reg [4:0] alpha=16;
 reg [3:0] state=6;reg [10:0] x=100,y=100;
 wire ov,sof,last;wire [23:0] rgb;
 media_osd dut(.clk(clk),.rst(rst),.frame_tick(frame),
 .state_code(state),.fade_alpha(alpha),
 .menu_active(menu),.menu_item(3'd1),.brightness_level(bri),.contrast_level(con),
 .rebuild_busy(rebuild),.rebuild_progress(3'd0),.rebuild_total(3'd2),
 .scale_override(2'd0),.zoom_level(3'd2),.spectrum_enable(1'b0),
 .audio_valid(1'b0),.audio_sample(24'sd0),.audio_stream_reset(1'b0),
 .valid(1'b1),.x(x),.y(y),.rgb(24'h204080),
 .out_valid(ov),.out_sof(sof),.out_last(last),.out_rgb(rgb));
 task tick;begin @(negedge clk);end endtask
 task publish;begin repeat(4)tick;frame=1;tick;frame=0;repeat(7)tick;end endtask
 initial begin
  repeat(4)tick;rst=0;publish;
  if(rgb!==24'h204080)$fatal(1,"neutral adjustment");
  alpha=0;repeat(7)tick;if(rgb!==24'h101c30)$fatal(1,"fade zero");
  alpha=16;bri=0;publish;if(rgb!==24'h102040)$fatal(1,"brightness half: %h",rgb);
  bri=2;con=0;publish;if(rgb!==24'h506080)$fatal(1,"contrast half: %h",rgb);
  if(dut.level_char(2,8)!=" ")$fatal(1,"value text repeats");
  menu=1;publish;x=280;y=110;repeat(7)tick;
  if(rgb===24'h506080)$fatal(1,"menu missing");
  menu=0;rebuild=1;publish;x=340;y=230;repeat(7)tick;
  if(rgb===24'h506080)$fatal(1,"render progress missing");
  rebuild=0;publish;x=958;y=26;repeat(8)tick;
  if(rgb===24'h506080)$fatal(1,"Anlogic logo missing");
  menu=0;state=14;publish;if(rgb!==24'hf4f6f8)$fatal(1,"error background");
  x=0;y=0;repeat(7)tick;if(!sof)$fatal(1,"SOF");
  x=1023;repeat(7)tick;if(!last || sof)$fatal(1,"EOL");
  $display("PASS menu: adjustment, fade, menu, rebuild progress, Anlogic logo, error page, metadata");$finish;
 end
endmodule
