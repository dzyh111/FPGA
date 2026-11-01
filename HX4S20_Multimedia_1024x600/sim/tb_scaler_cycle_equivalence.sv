`timescale 1ns/1ps
module tb_scaler_cycle_equivalence;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0,go=0,pause_output=0,pv=0;
 reg [15:0] width=1,height=1;
 reg [1:0] mode=1;
 reg [23:0] pixel=0;
 wire ready,ref_ready,input_ready,ref_input_ready,valid,ref_valid,done,ref_done,overrun,ref_overrun;
 wire [23:0] rgb,ref_rgb;
 bmp_mode_scaler dut(.clk(clk),.rst(rst),.image_start(start),.output_start(go),
  .output_pause(pause_output),.source_width(width),.source_height(height),.mode(mode),
  .pixel_valid(pv),.pixel_rgb(pixel),.config_ready(ready),.input_start_ready(input_ready),
  .output_valid(valid),.output_rgb(rgb),.output_done(done),.input_overrun(overrun));
 bmp_mode_scaler_preparallel_ref reference(.clk(clk),.rst(rst),.image_start(start),.output_start(go),
  .output_pause(pause_output),.source_width(width),.source_height(height),.mode(mode),
  .pixel_valid(pv),.pixel_rgb(pixel),.config_ready(ref_ready),.input_start_ready(ref_input_ready),
  .output_valid(ref_valid),.output_rgb(ref_rgb),.output_done(ref_done),.input_overrun(ref_overrun));
 integer cycles=0,outputs=0,pauses=0,rows=0,restarts=0,wrapped=0,configs=0;
 integer scenario,i,mi,config_wait,source_row,source_col,wrap_probes=0;
 integer widths[0:13],heights[0:13];
 reg feeding;
 reg [9:0] last_y;
 always @(posedge clk)begin
  if(!rst && start && dut.running)restarts=restarts+1;
  #1;
  cycles=cycles+1;
  if({ready,input_ready,valid,rgb,done,overrun}!==
     {ref_ready,ref_input_ready,ref_valid,ref_rgb,ref_done,ref_overrun})
   $fatal(1,"external mismatch cycle=%0d scenario=%0d mode=%0d",cycles,scenario,mode);
  if({dut.cstate,dut.gstate,dut.src_w,dut.src_h,dut.virtual_w,dut.virtual_h,
      dut.x_first,dut.x_last,dut.y_first,dut.y_last,dut.x_base,dut.y_base,
      dut.x_rem_start,dut.x_rem,dut.y_rem,dut.crop_x,dut.crop_y,
      dut.div_num,dut.div_den,dut.div_start,dut.size_is_width,
      dut.input_bank,dut.in_x,dut.in_y,dut.bank0_valid,dut.bank1_valid,
      dut.bank0_y,dut.bank1_y,dut.read_bank,dut.running,dut.out_x,dut.out_y,
      dut.source_x,dut.source_y,dut.x_step,dut.y_step,dut.x_rem_next,dut.y_rem_next,
      dut.u_div.work,dut.u_div.den,dut.u_div.count,dut.div_busy,dut.div_done,dut.div_q,dut.div_r}!==
     {reference.cstate,reference.gstate,reference.src_w,reference.src_h,reference.virtual_w,reference.virtual_h,
      reference.x_first,reference.x_last,reference.y_first,reference.y_last,reference.x_base,reference.y_base,
      reference.x_rem_start,reference.x_rem,reference.y_rem,reference.crop_x,reference.crop_y,
      reference.div_num,reference.div_den,reference.div_start,reference.size_is_width,
      reference.input_bank,reference.in_x,reference.in_y,reference.bank0_valid,reference.bank1_valid,
      reference.bank0_y,reference.bank1_y,reference.read_bank,reference.running,reference.out_x,reference.out_y,
      reference.source_x,reference.source_y,reference.x_step,reference.y_step,reference.x_rem_next,reference.y_rem_next,
      reference.u_div.work,reference.u_div.den,reference.u_div.count,reference.div_busy,reference.div_done,reference.div_q,reference.div_r})
   $fatal(1,"internal state mismatch cycle=%0d scenario=%0d mode=%0d",cycles,scenario,mode);
  if(!rst)begin
   if(valid)outputs=outputs+1;
   if(dut.running && dut.gstate==4 && pause_output)pauses=pauses+1;
   if(dut.out_y!=last_y)rows=rows+1;
  end
  last_y=dut.out_y;
 end
 task tick;begin @(negedge clk);end endtask
 task configure;
 begin
  start=1;tick;start=0;config_wait=0;
  while(!ready)begin tick;config_wait=config_wait+1;if(config_wait>150)$fatal(1,"configuration timeout");end
  tick;configs=configs+1;
  if(dut.virtual_w==0 || dut.virtual_h==0 ||
     (mode!=1 && (dut.virtual_w!=1024 && dut.virtual_h!=600)))wrapped=wrapped+1;
  go=1;tick;go=0;source_row=0;source_col=0;feeding=0;
 end endtask
 initial begin
  widths[0]=4;heights[0]=2;widths[1]=1024;heights[1]=600;
  widths[2]=1;heights[2]=1024;widths[3]=1024;heights[3]=1;
  widths[4]=1;heights[4]=8;widths[5]=1024;heights[5]=128;
  widths[6]=41;heights[6]=82;widths[7]=511;heights[7]=601;
  widths[8]=1023;heights[8]=599;widths[9]=7;heights[9]=1024;
  widths[10]=1024;heights[10]=7;widths[11]=512;heights[11]=512;
  widths[12]=3;heights[12]=1024;widths[13]=1024;heights[13]=3;
  repeat(4)tick;rst=0;
  for(scenario=0;scenario<14;scenario=scenario+1)for(mi=0;mi<4;mi=mi+1)begin
   width=widths[scenario];height=heights[scenario];mode=mi;pv=0;pause_output=0;
   configure;
   // On a missing requested line, stream consecutive source rows until it
   // becomes available. Random bubbles and pauses exercise both banks.
   for(i=0;i<12000;i=i+1)begin
    pause_output=($random&7)==0;
    if(dut.gstate==2 && !dut.wanted_in_bank0 && !dut.wanted_in_bank1 && source_row<=dut.source_y && source_row<height)feeding=1;
    pv=feeding && (($random&3)!=0);
    pixel={source_row[7:0],source_col[7:0],8'h69};
    tick;
    if(pv)begin
     if(source_col==width-1)begin
      source_col=0;source_row=source_row+1;feeding=0;
     end else source_col=source_col+1;
    end
   end
   // The next configuration interrupts an active output without a reset.
  end
  // Probe the documented legacy 16-bit storage boundary directly. These
  // states model a wrapped small virtual dimension with a large source;
  // do not silently turn the capped-two-step recurrence into modulo D.
  pv=0;pause_output=0;
  for(i=0;i<256;i=i+1)begin
   dut.running=1;reference.running=1;dut.gstate=4;reference.gstate=4;
   dut.out_x=100;reference.out_x=100;dut.out_y=100;reference.out_y=100;
   dut.x_first=0;reference.x_first=0;dut.x_last=1024;reference.x_last=1024;
   dut.y_first=0;reference.y_first=0;dut.y_last=600;reference.y_last=600;
   dut.virtual_w=83;reference.virtual_w=83;dut.src_w=1024;reference.src_w=1024;
   dut.x_rem=65535-i;reference.x_rem=65535-i;
   tick;
   if(dut.x_rem!==((65535-i+1024-166)&65535))$fatal(1,"x legacy storage wrap");
   wrap_probes=wrap_probes+1;
   dut.running=1;reference.running=1;dut.gstate=4;reference.gstate=4;
   dut.out_x=1023;reference.out_x=1023;dut.out_y=100;reference.out_y=100;
   dut.virtual_h=81;reference.virtual_h=81;dut.src_h=1024;reference.src_h=1024;
   dut.y_rem=65535-i;reference.y_rem=65535-i;
   tick;
   if(dut.y_rem!==((65535-i+1024-162)&65535))$fatal(1,"y legacy storage wrap");
   wrap_probes=wrap_probes+1;
  end
  pv=0;pause_output=1;rst=1;repeat(3)tick;rst=0;repeat(3)tick;
  if(configs!=56 || outputs<50000 || pauses<1000 || rows<100 || restarts<20 || wrapped<1)
   $fatal(1,"coverage configs%0d outputs%0d pauses%0d rows%0d restarts%0d wrapped%0d",configs,outputs,pauses,rows,restarts,wrapped);
  $display("PASS scaler cycle equivalence: %0d cycles, %0d configs all modes, %0d outputs, %0d paused pixels, %0d row changes, %0d active restarts, %0d wrapped geometries, %0d forced 16-bit storage-wrap probes",cycles,configs,outputs,pauses,rows,restarts,wrapped,wrap_probes);
  $finish;
 end
 initial begin #20000000;$fatal(1,"cycle equivalence timeout");end
endmodule
