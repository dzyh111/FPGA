`timescale 1ns/1ps
module tb_audio_waveform;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,stream_reset=0,frame_tick=0,sample_valid=0,valid=0;
 reg signed [23:0] sample=0;
 reg [2:0] scene=1;
 reg [10:0] x=0,y=0;
 wire line_hit,halo_hit;wire [23:0] line_rgb;
 audio_waveform dut(.clk(clk),.rst(rst),.stream_reset(stream_reset),
  .frame_tick(frame_tick),.sample_valid(sample_valid),.sample(sample),.scene(scene),
  .valid(valid),.x(x),.y(y),.line_hit(line_hit),.halo_hit(halo_hit),.line_rgb(line_rgb));
 integer shown_lo[0:255],shown_hi[0:255],next_lo[0:255],next_hi[0:255];
 integer checked_pixels=0,checked_core=0,checked_halo=0,commits=0;
 reg expect_line1=0,expect_line2=0,expect_halo1=0,expect_halo2=0;
 reg expect_line3=0,expect_line4=0,expect_halo3=0,expect_halo4=0;
 reg check_enabled=0;

 // Independent integer golden renderer: source PCM -> sample-pair extrema
 // -> linear midpoint bridge -> retained single-sample transient endpoint.
 function automatic integer quantise(input signed [23:0] pcm);
  integer signed_byte;
  begin signed_byte=$signed(pcm)>>>16;quantise=(signed_byte*5)>>>4;end
 endfunction
 function automatic integer hit(input integer px,py,margin);
  integer c,a,b,d,p,q,lo,hi;
  begin
   hit=0;
   if(px>=0&&px<1024&&py>=0&&py<600)begin
    c=px/4;b=(shown_lo[c]+shown_hi[c])>>>1;
    a=c==0?b:((shown_lo[c-1]+shown_hi[c-1])>>>1);d=b-a;
    case(px%4)
     0:begin p=a;q=a+(d>>>2);end
     1:begin p=a+(d>>>2);q=a+(d>>>1);end
     2:begin p=a+(d>>>1);q=b-(d>>>2);end
     default:begin p=b-(d>>>2);q=b;end
    endcase
    lo=p<q?p:q;hi=p>q?p:q;
    if(px%4==3)begin
     if(shown_lo[c]<lo)lo=shown_lo[c];
     if(shown_hi[c]>hi)hi=shown_hi[c];
    end
    hit=py>=552-hi-margin&&py<=552-lo+margin;
   end
  end
 endfunction
 always @(posedge clk)begin
  if(rst||stream_reset)begin
   expect_line1<=0;expect_line2<=0;expect_halo1<=0;expect_halo2<=0;
   expect_line3<=0;expect_line4<=0;expect_halo3<=0;expect_halo4<=0;
  end else begin
   expect_line1<=valid&&hit(x,y,1);expect_halo1<=valid&&hit(x,y,3);
   expect_line2<=expect_line1;expect_halo2<=expect_halo1;
   expect_line3<=expect_line2;expect_halo3<=expect_halo2;
   expect_line4<=expect_line3;expect_halo4<=expect_halo3;
  end
  #1;
  if(check_enabled)begin
   if(line_hit!==expect_line4||halo_hit!==expect_halo4)
    $fatal(1,"waveform pixel mismatch: x=%0d y=%0d got=%b%b expected=%b%b",x,y,
      line_hit,halo_hit,expect_line4,expect_halo4);
   checked_pixels=checked_pixels+1;
   if(line_hit)checked_core=checked_core+1;
   if(halo_hit)checked_halo=checked_halo+1;
  end
 end
 task send(input signed [23:0] pcm);
  begin
   @(negedge clk);sample=pcm;sample_valid=1;
   @(negedge clk);sample_valid=0;
  end
 endtask
 task capture(input integer pattern);
  integer c,v0,v1,a,b;
  begin
   for(c=0;c<256;c=c+1)begin
    case(pattern)
     0:begin v0=0;v1=0;end
     1:begin v0=8388607;v1=8388607;end
     2:begin v0=-8388608;v1=-8388608;end
     default:begin
      // Includes isolated +/- full-scale transients, both signs, low level,
      // asymmetrical pairs and very steep consecutive-column transitions.
      case(c%8)
       0:begin v0=0;v1=8388607;end
       1:begin v0=-8388608;v1=0;end
       2:begin v0=8388607;v1=8388607;end
       3:begin v0=-8388608;v1=-8388608;end
       4:begin v0=65536;v1=-65536;end
       5:begin v0=3200000;v1=1000000;end
       6:begin v0=-3200000;v1=-1000000;end
       default:begin v0=-8388608;v1=8388607;end
      endcase
     end
    endcase
    a=quantise(v0);b=quantise(v1);next_lo[c]=a<b?a:b;next_hi[c]=a>b?a:b;
    send(v0);send(v1);
   end
   @(negedge clk);
   if(!dut.capture_pending||dut.write_column!=0||dut.sample_phase!=0)
    $fatal(1,"complete capture did not wait atomically for frame boundary");
  end
 endtask
 task commit_capture;
  integer c;
  begin
   valid=0;check_enabled=0;
   repeat(5)@(negedge clk);
   frame_tick=1;@(negedge clk);frame_tick=0;
   for(c=0;c<256;c=c+1)begin shown_lo[c]=next_lo[c];shown_hi[c]=next_hi[c];end
   repeat(5)@(negedge clk);
   if(!dut.display_ready||dut.capture_pending)$fatal(1,"frame commit failed");
   for(c=0;c<256;c=c+1)begin
    if($signed(dut.wave_ram[{dut.display_bank,c[7:0]}][13:7])!==shown_lo[c] ||
       $signed(dut.wave_ram[{dut.display_bank,c[7:0]}][6:0])!==shown_hi[c])
      $fatal(1,"PCM extrema mismatch column %0d",c);
   end
   check_enabled=1;commits=commits+1;
  end
 endtask
 task scan_rows(input integer first_y,last_y);
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
 integer c,n;
 reg saved_bank;
 initial begin
  for(c=0;c<256;c=c+1)begin shown_lo[c]=0;shown_hi[c]=0;next_lo[c]=0;next_hi[c]=0;end
  repeat(4)@(negedge clk);rst=0;check_enabled=1;
  scan_rows(548,556); // No initialised RAM is required for a flat silence line.
  capture(1);
  if(dut.display_ready)$fatal(1,"capture appeared before frame_tick");
  repeat(20)send(-8388608); // Pending bank may not be overwritten.
  scan_rows(551,553); // Still initial silence despite the pending full-scale capture.
  commit_capture;scan_rows(510,516);
  capture(2);saved_bank=dut.display_bank;
  scan_rows(512,514); // A completed next capture cannot tear the visible bank.
  if(dut.display_bank!==saved_bank)$fatal(1,"visible bank changed during active scan");
  commit_capture;scan_rows(589,595);
  capture(3);commit_capture;scan_rows(508,596);
  // Pause/underflow: no consumed samples means neither bank nor waveform moves.
  saved_bank=dut.display_bank;
  repeat(4)begin @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;end
  if(dut.display_bank!==saved_bank||dut.capture_pending)$fatal(1,"pause changed the waveform");
  // A partial capture likewise cannot replace the complete displayed snapshot.
  repeat(17)send(0);
  @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;
  if(dut.display_bank!==saved_bank)$fatal(1,"partial snapshot became visible");
  scan_rows(549,555);
  // Stream reset discards the partial column as well as stale scene data.
  check_enabled=0;@(negedge clk);stream_reset=1;@(negedge clk);stream_reset=0;
  for(c=0;c<256;c=c+1)begin shown_lo[c]=0;shown_hi[c]=0;end
  repeat(5)@(negedge clk);check_enabled=1;
  if(dut.display_ready||dut.capture_pending||dut.sample_phase||dut.write_column!=0)
   $fatal(1,"stream reset retained capture state");
  capture(0);commit_capture;scan_rows(548,556);
  // Out-of-screen coordinates and invalid pixels must never draw a waveform.
  @(negedge clk);valid=1;x=1024;y=552;
  repeat(5)@(negedge clk);
  @(negedge clk);valid=1;x=0;y=600;
  repeat(5)@(negedge clk);
  @(negedge clk);valid=0;x=0;y=552;
  repeat(5)@(negedge clk);
  if(line_hit||halo_hit)$fatal(1,"invalid pixel emitted a waveform");
  if(commits!=4||checked_core<1000||checked_halo<=checked_core)
   $fatal(1,"insufficient waveform coverage");
  $display("PASS waveform: %0d checked pixels, %0d core/%0d halo; PCM sign/extrema, transient, zero, pause, double buffer, 4-clock alignment and full-width bridges",checked_pixels,checked_core,checked_halo);
  $finish;
 end
 initial begin #5000000;$fatal(1,"waveform timeout");end
endmodule
