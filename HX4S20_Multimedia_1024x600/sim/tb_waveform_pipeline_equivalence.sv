`timescale 1ns/1ps
module tb_waveform_pipeline_equivalence;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,stream_reset=0,frame_tick=0,sample_valid=0,valid=0;
 reg signed [23:0] sample=0;reg [2:0] scene=0;
 reg [10:0] x=0,y=0;
 wire old_core,old_halo,new_core,new_halo;
 wire [23:0] old_rgb,new_rgb;
 audio_waveform_reference golden(.clk(clk),.rst(rst),.stream_reset(stream_reset),
  .frame_tick(frame_tick),.sample_valid(sample_valid),.sample(sample),.scene(scene),
  .valid(valid),.x(x),.y(y),.line_hit(old_core),.halo_hit(old_halo),.line_rgb(old_rgb));
 audio_waveform candidate(.clk(clk),.rst(rst),.stream_reset(stream_reset),
  .frame_tick(frame_tick),.sample_valid(sample_valid),.sample(sample),.scene(scene),
  .valid(valid),.x(x),.y(y),.line_hit(new_core),.halo_hit(new_halo),.line_rgb(new_rgb));
 reg [25:0] delay0=0,delay1=0;
 integer checked=0,drawn=0,captures=0,resets=0;
 always @(posedge clk)begin
  if(rst||stream_reset)begin delay0<=0;delay1<=0;end
  else begin delay0<={old_core,old_halo,old_rgb};delay1<=delay0;end
  #1;
  if({new_core,new_halo,new_rgb}!==delay1)
   $fatal(1,"waveform pipeline is not exactly old+2 clocks at x%0d y%0d old-delay=%h new=%h",x,y,delay1,{new_core,new_halo,new_rgb});
  if(!rst&&!stream_reset)begin
   checked=checked+1;if(new_core)drawn=drawn+1;
   if({candidate.sample_phase,candidate.write_bank,candidate.display_bank,
       candidate.capture_pending,candidate.display_ready,candidate.write_column} !==
      {golden.sample_phase,golden.write_bank,golden.display_bank,
       golden.capture_pending,golden.display_ready,golden.write_column})
     $fatal(1,"pipeline changed capture/control timing");
  end
 end
 task send(input signed [23:0] value);
  begin
   @(negedge clk);sample=value;sample_valid=1;
   @(negedge clk);sample_valid=0;
  end
 endtask
 task capture(input integer pattern);
  integer col,v;
  begin
   for(col=0;col<512;col=col+1)begin
    case(pattern)
     0:v=0;
     1:v=col[0]?8388607:-8388608;
     2:v=((col*1103515245+12345)&16777215)-8388608;
     default:v=col<256?8388607:-8388608;
    endcase
    send(v);
   end
   if(!candidate.capture_pending||!golden.capture_pending)$fatal(1,"capture did not complete");
   @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;
   captures=captures+1;
  end
 endtask
 task scan(input integer first_y,last_y);
  integer xx,yy;
  begin
   for(yy=first_y;yy<=last_y;yy=yy+1)begin
    for(xx=0;xx<1024;xx=xx+1)begin
     @(negedge clk);valid=1;x=xx;y=yy;
    end
    @(negedge clk);valid=0;
    repeat(5)@(negedge clk);
   end
  end
 endtask
 integer s;
 initial begin
  repeat(4)@(negedge clk);rst=0;
  scan(548,556);capture(1);
  for(s=0;s<5;s=s+1)begin scene=s;scan(508,596);end
  capture(2);scan(508,596);capture(3);scan(508,596);
  // Reset while valid pixels and an odd partial sample pair are in flight.
  send(8388607);@(negedge clk);valid=1;x=511;y=552;stream_reset=1;
  repeat(2)@(negedge clk);stream_reset=0;resets=resets+1;
  scan(548,556);capture(0);scan(548,556);
  @(negedge clk);valid=1;x=1024;y=552;
  repeat(6)@(negedge clk);
  @(negedge clk);valid=1;x=1023;y=600;
  repeat(6)@(negedge clk);
  @(negedge clk);valid=0;
  repeat(6)@(negedge clk);
  if(drawn<1000||captures!=4||resets!=1)$fatal(1,"equivalence coverage too small");
  $display("PASS waveform pipeline equivalence: %0d checked clocks, %0d drawn pixels; exact old+2 clocks for 4-clock output, all five palettes, PCM extrema/random/zero, frame swaps, reset and invalid bounds",checked,drawn);
  $finish;
 end
 initial begin #12000000;$fatal(1,"waveform equivalence timeout");end
endmodule
