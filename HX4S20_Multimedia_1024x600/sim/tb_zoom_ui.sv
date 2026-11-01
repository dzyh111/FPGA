`timescale 1ns/1ps
module tb_zoom_ui;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,kp=1,km=1,kn=1;
 wire menu;wire [2:0] item,bri,con,zoom;wire [1:0] legacy_scale;
 ui_control #(.CLK_HZ(1000),.IDLE_SECONDS(8)) dut(.clk(clk),.rst(rst),
  .key_prev(kp),.key_menu(km),.key_next(kn),.menu_active(menu),.menu_item(item),
  .brightness_level(bri),.contrast_level(con),.scale_override(legacy_scale),.zoom_level(zoom));
 task press;
  input integer key;
  begin
   @(negedge clk);case(key)0:kp=0;1:km=0;2:kn=0;endcase
   repeat(30)@(negedge clk);kp=1;km=1;kn=1;repeat(30)@(negedge clk);
  end
 endtask
 integer n;
 always @(posedge clk)if(!rst && legacy_scale!==0)$fatal(1,"zoom reached legacy TF-rebuild control");
 initial begin
  repeat(4)@(negedge clk);rst=0;repeat(4)@(negedge clk);
  if(zoom!=2 || menu || bri!=2 || con!=2)$fatal(1,"reset/default100");
  press(0);press(2);if(zoom!=2 || menu)$fatal(1,"outside keys changed zoom");
  press(1);if(!menu || item!=0)$fatal(1,"ZOOM first row");
  press(0);if(zoom!=1)$fatal(1,"75 percent");
  press(0);if(zoom!=0)$fatal(1,"50 percent");
  press(0);if(zoom!=0)$fatal(1,"zoom lower clamp");
  for(n=1;n<=4;n=n+1)begin press(2);if(zoom!=n)$fatal(1,"zoom step %0d",n);end
  press(2);if(zoom!=4)$fatal(1,"zoom upper clamp");
  press(1);press(0);if(item!=1 || bri!=1 || zoom!=4)$fatal(1,"brightness isolation");
  press(1);press(2);if(item!=2 || con!=3 || zoom!=4)$fatal(1,"contrast isolation");
  press(1);press(0);if(menu)$fatal(1,"exit");
  press(1);if(!menu || item!=0 || zoom!=4)$fatal(1,"reopen preserves zoom");
  repeat(8100)@(negedge clk);if(menu || zoom!=4)$fatal(1,"timeout preserves zoom");
  $display("PASS zoom UI: default100, all five levels, endpoint clamps, menu/brightness/contrast isolation, no legacy rebuild changes, exit/timeout");
  $finish;
 end
 initial begin #200000;$fatal(1,"zoom UI timeout");end
endmodule
