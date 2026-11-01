`timescale 1ns/1ps
// Compare parameter-sized state against the unmodified preceding release.
module tb_ui_counter_equivalence;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,kp=1,km=1,kn=1,fast_key=1;
 wire menu,ref_menu,fast_pulse,ref_fast_pulse;
 wire [2:0] item,bri,con,zoom,ref_item,ref_bri,ref_con,ref_zoom;
 wire [1:0] scale,ref_scale;
 integer checks=0,n;
 ui_control #(.CLK_HZ(1000),.IDLE_SECONDS(1)) dut(
  .clk(clk),.rst(rst),.key_prev(kp),.key_menu(km),.key_next(kn),
  .menu_active(menu),.menu_item(item),.brightness_level(bri),.contrast_level(con),
  .scale_override(scale),.zoom_level(zoom));
 ui_control_32bit_ref #(.CLK_HZ(1000),.IDLE_SECONDS(1)) reference(
  .clk(clk),.rst(rst),.key_prev(kp),.key_menu(km),.key_next(kn),
  .menu_active(ref_menu),.menu_item(ref_item),.brightness_level(ref_bri),.contrast_level(ref_con),
  .scale_override(ref_scale),.zoom_level(ref_zoom));
 button_press #(.CLK_HZ(1000),.DEBOUNCE_MS(1)) fast(
  .clk(clk),.rst(rst),.key_n(fast_key),.pulse(fast_pulse));
 button_press_32bit_ref #(.CLK_HZ(1000),.DEBOUNCE_MS(1)) fast_reference(
  .clk(clk),.rst(rst),.key_n(fast_key),.pulse(ref_fast_pulse));
 ui_control production(.clk(clk),.rst(rst),.key_prev(1'b1),.key_menu(1'b1),.key_next(1'b1),
  .menu_active(),.menu_item(),.brightness_level(),.contrast_level(),.scale_override(),.zoom_level());
 always @(posedge clk)begin
  #1;
  if(!rst)begin
   checks=checks+1;
   if({menu,item,bri,con,zoom,scale}!={ref_menu,ref_item,ref_bri,ref_con,ref_zoom,ref_scale})
    $fatal(1,"UI counter equivalence cycle%0d",checks);
   if(fast_pulse!==ref_fast_pulse)$fatal(1,"one-cycle debounce equivalence");
  end
 end
 initial begin
  if($bits(dut.u_prev.count)!=5 || $bits(dut.idle_cnt)!=10 || $bits(fast.count)!=1)
   $fatal(1,"parameter counter sizing");
  if($bits(production.u_prev.count)!=20 || $bits(production.idle_cnt)!=29)
   $fatal(1,"40MHz counter sizing");
  repeat(4)@(negedge clk);rst=0;
  // Sub-threshold bounce, long holds, releases, simultaneous actions, resets.
  for(n=0;n<60000;n=n+1)begin
   @(negedge clk);
   if(n<100)begin km=(n%2)==0;kp=1;kn=1;end
   else if(n%61==0){kp,km,kn}=$urandom_range(0,7);
   if(n%7==0)fast_key=~fast_key;
   if(n==15000 || n==37000)rst=1;
   else if(n==15003 || n==37003)rst=0;
  end
  // Exercise an actual idle timeout after opening the menu.
  kp=1;km=1;kn=1;repeat(30)@(negedge clk);
  if(menu)begin
   rst=1;repeat(3)@(negedge clk);rst=0;repeat(3)@(negedge clk);
  end
  km=0;repeat(30)@(negedge clk);km=1;repeat(30)@(negedge clk);
  if(!menu || item!=0)$fatal(1,"explicit menu entry");
  repeat(1100)@(negedge clk);if(menu)$fatal(1,"explicit idle timeout");
  $display("PASS sized UI counters: %0d lockstep cycles vs frozen32-bit RTL; bounce/holds/simultaneous/reset, LIMIT1, non-power-of-two20/1000, timeout and 40MHz20/29-bit widths",checks);
  $finish;
 end
 initial begin #1000000;$fatal(1,"UI counter equivalence timeout");end
endmodule
