`include "display_config.vh"

// 48 kHz, 16-bit stereo PCM source for the HDMI audio input.  The upstream
// asynchronous FIFO uses show-ahead mode, therefore fifo_data is sampled on
// the same clock edge that asserts fifo_read.
module wav_audio_player #(parameter PIXEL_HZ=`PIXEL_HZ)(
    input clk,input rst,input play_enable,input mute,
    input stream_reset,input [31:0] sample_total,
    input [31:0] fifo_data,input fifo_empty,output reg fifo_read,
    output reg valid,output reg signed [23:0] left_data,
    output reg signed [23:0] right_data,
    output reg signed [23:0] analysis_sample,
    output reg acr_valid,output [19:0] acr_n,output [19:0] acr_cts,
    output reg sample_consumed,output reg [31:0] sample_position,
    output reg loop_toggle
);
    reg [31:0] accumulator;
    reg [5:0] acr_count;
    assign acr_n=20'd6144;
    assign acr_cts=PIXEL_HZ/1000;
    always @(posedge clk or posedge rst)begin
      if(rst)begin
        accumulator<=0;acr_count<=0;fifo_read<=0;valid<=0;acr_valid<=0;
        left_data<=0;right_data<=0;analysis_sample<=0;
        sample_consumed<=0;sample_position<=0;loop_toggle<=0;
      end else begin
        fifo_read<=0;valid<=0;acr_valid<=0;sample_consumed<=0;
        if(stream_reset) sample_position<=0;
        if(accumulator>=PIXEL_HZ-48000)begin
          accumulator<=accumulator-(PIXEL_HZ-48000);
          valid<=1;
          if(play_enable && !fifo_empty && !stream_reset)begin
            fifo_read<=1;
            sample_consumed<=1;
            if(sample_total!=0 && sample_position==sample_total-1'b1)begin
              sample_position<=0;loop_toggle<=~loop_toggle;
            end else sample_position<=sample_position+1'b1;
            // Left-justify 16-bit PCM.  The spectrum input converts it back
            // with >>>8; sign-extension alone made real WAV levels 256x low.
            analysis_sample<={$signed(fifo_data[15:0]),8'h00};
            if(mute)begin left_data<=0;right_data<=0;end
            else begin
              left_data<={$signed(fifo_data[15:0]),8'h00};
              right_data<={$signed(fifo_data[31:16]),8'h00};
            end
          end else begin
            left_data<=0;right_data<=0;analysis_sample<=0;
          end
          if(acr_count==47)begin acr_count<=0;acr_valid<=1;end
          else acr_count<=acr_count+1'b1;
        end else accumulator<=accumulator+48000;
      end
    end
endmodule
