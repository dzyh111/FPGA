`timescale 1ns/1ps
module tb_fade_ui;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,token=0,blank=0;reg [1:0] index=0;
 wire ack,blank_ack,req,display_on,tick,busy;wire [1:0] current,next;
 wire [4:0] alpha;wire [9:0] slide;
 video_scan #(.H_ACTIVE(32),.H_FP(8),.H_SYNC(4),.H_BP(8),
 .V_ACTIVE(8),.V_FP(2),.V_SYNC(1),.V_BP(2),.IMG_W(32),.IMG_H(8)) scan(
 .clk(clk),.rst(rst),.commit_toggle(token),.commit_index(index),.commit_ack(ack),
 .blank_toggle(blank),.blank_ack(blank_ack),
 .read_index(current),.next_index(next),.slide_rows(slide),.fade_alpha(alpha),
 .transition_busy(busy),.read_req(req),.read_req_ack(req),.display_enabled(display_on),.frame_tick(tick));
 reg kp=1,km=1,kn=1;
 wire menu;wire [2:0] item,bri,con;wire [1:0] scale;
 ui_control #(.CLK_HZ(1000),.IDLE_SECONDS(8)) ui(.clk(clk),.rst(rst),
 .key_prev(kp),.key_menu(km),.key_next(kn),.menu_active(menu),.menu_item(item),
 .brightness_level(bri),.contrast_level(con),.scale_override(scale));
 integer read_frames=0;
 reg req_old=0;reg [1:0] old_current=0;
 always @(posedge clk)begin
  if(req&&!req_old)read_frames=read_frames+1;
  req_old<=req;
  if(!rst)begin
   if(slide!=0)$fatal(1,"slide must be disabled");
   if(alpha>16)$fatal(1,"alpha out of range");
   if(current!=old_current && alpha!=0)$fatal(1,"visible buffer swap");
  end
  old_current<=current;
 end
 task press(input integer key);
 begin
  @(negedge clk);case(key)0:kp=0;1:km=0;2:kn=0;endcase
  repeat(30)@(negedge clk);kp=1;km=1;kn=1;
  repeat(30)@(negedge clk);
 end endtask
 initial begin
 repeat(5)@(negedge clk);rst=0;token=1;
 wait(ack==token);if(alpha!=16 || current!=0)$fatal(1,"initial fade");
 @(negedge clk);index=1;token=0;
 wait(busy);wait(ack==token);
 if(alpha!=16||current!=1||read_frames<30)$fatal(1,"fade/refresh failed %d",read_frames);
 blank=1;wait(blank_ack==blank);if(display_on||alpha!=0)$fatal(1,"blank fade failed");
 token=1;index=1;wait(ack==token);if(!display_on||alpha!=16)$fatal(1,"blank restore failed");
 press(1);if(!menu||item!=0)$fatal(1,"menu entry");
 press(1);press(2);if(bri!=3)$fatal(1,"menu routing");
 repeat(2)press(1);if(item!=3)$fatal(1,"exit selection");
 press(2);if(menu)$fatal(1,"menu exit");
 press(0);press(2);if(menu)$fatal(1,"buttons reopened menu");
 $display("PASS fade/UI: invisible buffer swap, frame refresh, full fade and menu isolation");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
