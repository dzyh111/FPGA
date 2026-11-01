`timescale 1ns/1fs
// Complete 1344x635 raster, real generated asynchronous 512x32 read FIFO,
// 40 MHz memory / 51.2 MHz video, accepted read responses three clocks later.
// Refresh scheduling is a timing/ownership model, not a physical SDRAM model.
module tb_video_zoom_rgb565;
 reg mem_clk=0,video_clk=0;
 always #12.5 mem_clk=~mem_clk;
 always #9.765625 video_clk=~video_clk;
 reg rst=1;
 // Use the real scan module and its exported line-start signal. An
 // independently generated hc==0 hid the broken top-level connection.
 wire frame_tick,line_start,active;
 wire [10:0] x,y;
 wire [11:0] hc=scan.hc,vc=scan.vc;
 video_scan #(.IMG_W(1024),.IMG_H(600),.ENABLE_COVER(1)) scan(
  .clk(video_clk),.rst(rst),.commit_toggle(1'b0),.commit_index(2'd0),
  .commit_cover(1'b0),.blank_toggle(1'b0),.read_req_ack(1'b0),
  .frame_tick(frame_tick),.line_start(line_start),.active(active),.x(x),.y(y));
 reg [2:0] requested_zoom=0,zoom_applied=2;
 reg requested_cover=0,cover_applied=0;
 reg [1:0] requested_bank=0,bank_applied=0;
 always @(posedge video_clk)begin
  if(rst)begin zoom_applied<=2;cover_applied<=0;bank_applied<=0;end
  else begin
   if(frame_tick)begin
    zoom_applied<=requested_zoom;cover_applied<=requested_cover;bank_applied<=requested_bank;
   end
  end
 end
 wire [2:0] read_zoom=cover_applied?3'd2:zoom_applied;
 reg read_req=0;
 reg [3:0] delay_req=0;
 reg [1:0] ack_sync=0;
 wire read_ack,read_finish,fifo_clear,rd_busy,app_rd_en;
 wire [20:0] app_rd_addr;
 always @(posedge video_clk)begin
  if(rst)begin read_req<=0;delay_req<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],read_ack};
   if(frame_tick)delay_req<=8;
   if(delay_req!=0)begin delay_req<=delay_req-1'b1;if(delay_req==1)read_req<=1;end
   if(read_req && ack_sync[1])read_req<=0;
  end
 end
 wire read_en,valid;
 wire [10:0] src_x,src_y,screen_x,screen_y;
 wire [23:0] rgb;
 wire [31:0] read_data;
 wire fifo_empty,fifo_full;
 wire [8:0] wrusedw,rdusedw;
 reg ref_valid=0,refresh_pending=0;
 integer refresh_counter=0,refresh_left=0,refreshes=0;
 integer guarded_launches=0;
 reg injected_launch=0;
 reg [2:0] response_valid=0;
 reg [20:0] response_addr[0:2];
 wire data_valid=response_valid[2];
 function [15:0] pixel_pattern;
  input integer sx,sy,bank;
  reg [4:0] r,b;reg [5:0] g;
  begin r=sx*3+sy*5+bank*7;g=sx*7+sy*3+bank*11;
   b=sx*11+sy*13+bank*17;pixel_pattern={r,g,b};end
 endfunction
 function [31:0] word_pattern;
  input [20:0] addr;
  integer bank,offset,sx,sy;
  begin bank=addr/307200;offset=addr%307200;sy=offset/512;sx=(offset%512)*2;
   word_pattern={pixel_pattern(sx,sy,bank),pixel_pattern(sx+1,sy,bank)};end
 endfunction
 wire [31:0] mem_data=word_pattern(response_addr[2]);
 rfifo_32_32_512 fifo(.clkr(video_clk),.clkw(mem_clk),.rst(fifo_clear || rst),
  .we(data_valid),.re(read_en),.di(mem_data),.dout(read_data),
  .empty_flag(fifo_empty),.full_flag(fifo_full),.wrusedw(wrusedw),.rdusedw(rdusedw));
 frame_fifo_read #(.BURST_SIZE(256),.ENABLE_ZOOM(1)) reader(
  .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(!rst),.Sdr_init_ref_vld(ref_valid),
  .Sdr_busy(1'b0),.Sdr_rd_en(data_valid),.App_wr_busy(1'b0),.O_rd_busy(rd_busy),
  .App_rd_en(app_rd_en),.App_rd_addr(app_rd_addr),.read_next_index(bank_applied),
  .read_slide_rows(10'd0),.read_zoom(read_zoom),.read_req(read_req),.read_req_ack(read_ack),
  .read_finish(read_finish),.read_addr_0(cover_applied?21'd1228800:21'd0),
  .read_addr_1(21'd307200),.read_addr_2(21'd614400),.read_addr_3(21'd921600),
  .read_addr_index(bank_applied),.read_len(21'd307200),.fifo_aclr(fifo_clear),
  .wrusedw({1'b0,wrusedw}));
 video_zoom_rgb565 dut(.clk(video_clk),.rst(rst),.frame_tick(frame_tick),
  .line_start(line_start),.active(active),.display_enabled(1'b1),
  .cover_active(cover_applied),.zoom_index(zoom_applied),.x(x),.y(y),.read_data(read_data),
  .read_en(read_en),.valid(valid),.src_x(src_x),.src_y(src_y),
  .screen_x(screen_x),.screen_y(screen_y),.rgb(rgb));
 integer frame_number=-1,reference_zoom=2,reference_bank=0;
 integer frame_pixels=0,frame_pops=0,frame_reads=0,frame_returns=0;
 integer total_pixels=0,total_pops=0,total_reads=0;
 integer expected_width,expected_height,expected_left,expected_top;
 integer numerator,denominator,base_x,base_y,crop_x_rem;
 integer expected_x,expected_y,expected_addr,output_row,source_row;
 integer expected_screen_x=0,expected_screen_y=0,min_fifo=512;
 reg [15:0] expected565;
 reg [23:0] expected_rgb;
 reg image_hit;
 task set_reference;
  input integer mode;
  begin
   expected_width=1024;expected_height=600;expected_left=0;expected_top=0;
   numerator=1;denominator=1;base_x=0;base_y=0;crop_x_rem=0;
   case(mode)
    0:begin expected_width=512;expected_height=300;expected_left=256;expected_top=150;numerator=2;end
    1:begin expected_width=768;expected_height=450;expected_left=128;expected_top=75;numerator=4;denominator=3;end
    3:begin numerator=4;denominator=5;base_x=102;base_y=60;crop_x_rem=2;end
    4:begin numerator=2;denominator=3;base_x=170;base_y=100;crop_x_rem=2;end
    default:;
   endcase
  end
 endtask
 task check_frame;
  begin
   if(frame_pixels!=614400 || frame_pops!=expected_height*512 ||
      frame_reads!=expected_height*512 || frame_returns!=expected_height*512)
    $fatal(1,"frame=%0d zoom=%0d pixels=%0d pops=%0d reads=%0d returns=%0d expectedwords=%0d",
     frame_number,reference_zoom,frame_pixels,frame_pops,frame_reads,frame_returns,expected_height*512);
   $display("ZOOM_FRAME frame=%0d zoom=%0d bank=%0d pixels=%0d words=%0d min_fifo=%0d refreshes=%0d",
    frame_number,reference_zoom,reference_bank,frame_pixels,frame_reads,min_fifo,refreshes);
   $fflush();
  end
 endtask
 always @(posedge video_clk)if(!rst && frame_tick)begin
  if(frame_number>=0)check_frame();
  frame_number=frame_number+1;
  reference_zoom=requested_cover?2:requested_zoom;
  reference_bank=requested_cover?4:requested_bank;
  set_reference(reference_zoom);
  frame_pixels=0;frame_pops=0;frame_reads=0;frame_returns=0;
  expected_screen_x=0;expected_screen_y=0;min_fifo=512;
  injected_launch=0;
 end
 always @(posedge video_clk)if(!rst && read_en)begin
  if(fifo_empty || fifo_clear)$fatal(1,"FIFO underflow frame=%0d screen=%0d,%0d words=%0d",frame_number,x,y,frame_pops);
  frame_pops=frame_pops+1;total_pops=total_pops+1;
  if(rdusedw<min_fifo)min_fifo=rdusedw;
 end
 always @(negedge video_clk)if(!rst && valid)begin
  if(screen_x!==expected_screen_x || screen_y!==expected_screen_y)
   $fatal(1,"screen sequence frame=%0d got=%0d,%0d expected=%0d,%0d",frame_number,screen_x,screen_y,expected_screen_x,expected_screen_y);
  image_hit=screen_x>=expected_left && screen_x<expected_left+expected_width &&
            screen_y>=expected_top && screen_y<expected_top+expected_height;
  if(image_hit)begin
   expected_x=base_x+((screen_x-expected_left)*numerator+crop_x_rem)/denominator;
   expected_y=base_y+((screen_y-expected_top)*numerator)/denominator;
   expected565=pixel_pattern(expected_x,expected_y,reference_bank);
   expected_rgb={{expected565[15:11],expected565[15:13]},
                 {expected565[10:5],expected565[10:9]},
                 {expected565[4:0],expected565[4:2]}};
   if(src_x!==expected_x || src_y!==expected_y || rgb!==expected_rgb)
    $fatal(1,"pixel frame=%0d zoom=%0d screen=%0d,%0d src=%0d,%0d expected=%0d,%0d rgb=%h expected=%h",
      frame_number,reference_zoom,screen_x,screen_y,src_x,src_y,expected_x,expected_y,rgb,expected_rgb);
  end else if(src_x!==11'd2047 || src_y!==11'd2047 || rgb!==24'h101c30)
   $fatal(1,"letterbox not sentinel/clean frame=%0d screen=%0d,%0d src=%0d,%0d rgb=%h",frame_number,screen_x,screen_y,src_x,src_y,rgb);
  frame_pixels=frame_pixels+1;total_pixels=total_pixels+1;
  if(expected_screen_x==1023)begin expected_screen_x=0;expected_screen_y=expected_screen_y+1;end
  else expected_screen_x=expected_screen_x+1;
 end
 always @(posedge mem_clk)begin
  if(rst)begin response_valid<=0;ref_valid<=0;refresh_counter<=0;
   refresh_pending<=0;refresh_left<=0;end
  else begin
   response_valid<={response_valid[1:0],app_rd_en};
   response_addr[0]<=app_rd_addr;response_addr[1]<=response_addr[0];response_addr[2]<=response_addr[1];
   if(refresh_counter==1170)begin refresh_counter<=0;refresh_pending<=1;end
   else refresh_counter<=refresh_counter+1;
   if(ref_valid)begin
    if(app_rd_en)$fatal(1,"SDRAM read/refresh overlap frame=%0d addr=%0d",frame_number,app_rd_addr);
    if(refresh_left==0)ref_valid<=0;else refresh_left<=refresh_left-1;
    if(rd_busy && reader.burst_cnt==0 && reader.App_rd_en_d0)guarded_launches=guarded_launches+1;
   end else if(!rd_busy && !app_rd_en &&
             (refresh_pending || (!injected_launch && reader.state==2)))begin
    ref_valid<=1;refresh_left<=8+(refreshes%17);refresh_pending<=0;
    refreshes=refreshes+1;
    if(reader.state==2)injected_launch=1;
   end
   if(app_rd_en)begin
    output_row=frame_reads/512;
    source_row=base_y+(output_row*numerator)/denominator;
    expected_addr=reference_bank*307200+source_row*512+(frame_reads%512);
    if(app_rd_addr!==expected_addr)
     $fatal(1,"SDRAM address frame=%0d read=%0d got=%0d expected=%0d sourcey=%0d",frame_number,frame_reads,app_rd_addr,expected_addr,source_row);
    frame_reads=frame_reads+1;total_reads=total_reads+1;
   end
   if(data_valid)begin
    if(fifo_full || fifo_clear)$fatal(1,"FIFO overflow/reset response frame=%0d",frame_number);
    frame_returns=frame_returns+1;
   end
  end
 end
 function [2:0] zoom_plan;
  input integer frame_id;
  begin case(frame_id)0:zoom_plan=0;1:zoom_plan=1;2:zoom_plan=2;
   3:zoom_plan=3;4:zoom_plan=4;5:zoom_plan=4;6:zoom_plan=1;
   7:zoom_plan=0;8:zoom_plan=3;default:zoom_plan=4;endcase end
 endfunction
 integer test_frame;
 initial begin
  repeat(12)@(negedge video_clk);rst=0;
  // The next selection arrives midway through the previous frame, as a
  // real button can. Only the following frame_tick may apply it.
  for(test_frame=0;test_frame<10;test_frame=test_frame+1)begin
   wait(active && x==512 && y==300);@(negedge video_clk);
   requested_zoom=zoom_plan(test_frame+1);
   requested_cover=(test_frame+1==5 || test_frame+1==6);
   requested_bank=requested_cover?0:(test_frame+1)%4;
   wait(hc==1343 && vc==634);@(negedge video_clk);
  end
  check_frame();
  if(guarded_launches<10 || refreshes<100)$fatal(1,"Refresh guard coverage missing guarded=%0d refreshes=%0d",guarded_launches,refreshes);
  if(total_pixels!=6144000)$fatal(1,"pixel total mismatch %0d",total_pixels);
  $display("PASS percentage zoom: 10 complete frames, %0d pixels, %0d SDRAM words, no FIFO under/overflow, guarded_launches=%0d refreshes=%0d; 0 extra line BRAM",total_pixels,total_reads,guarded_launches,refreshes);
  $finish;
 end
 initial begin #180000000;$fatal(1,"percentage zoom timeout");end
endmodule
