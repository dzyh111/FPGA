`include "display_config.vh"
// Same notes, waveform, amplitude and duration as lab_ex5_i2s's
// hdmi_audio_tone_i2s_64fs. PCM feeds HDMI directly at 48 kHz.
module audio_pcm #(parameter PIXEL_HZ=`PIXEL_HZ)(
    input clk,input rst,input mute,
    output reg valid, output reg signed [23:0] left_data,
    output wire signed [23:0] right_data,
    output reg acr_valid, output [19:0] acr_n, output [19:0] acr_cts
);
    reg [31:0] accumulator,phase;
    reg [2:0] note_index;
    reg [14:0] note_count;
    reg [5:0] acr_count;
    reg [31:0] phase_inc;
    assign right_data=left_data;
    assign acr_n=20'd6144;
    assign acr_cts=PIXEL_HZ/1000;
    always @* begin
        case(note_index)
            0:phase_inc=23409862; 1:phase_inc=26276681;
            2:phase_inc=29494578; 3:phase_inc=31248410;
            4:phase_inc=35075155; 5:phase_inc=39370534;
            6:phase_inc=44191930; default:phase_inc=46819716;
        endcase
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            accumulator<=0;phase<=0;note_index<=0;note_count<=0;
            valid<=0;left_data<=0;acr_count<=0;acr_valid<=0;
        end else begin
            valid<=0;acr_valid<=0;
            if(accumulator>=PIXEL_HZ-48000) begin
                accumulator<=accumulator-(PIXEL_HZ-48000);
                valid<=1;
                left_data<=mute ? 24'sd0 : (phase[31] ? 24'sd2000000 : -24'sd2000000);
                phase<=phase+phase_inc;
                if(note_count==23999) begin note_count<=0;note_index<=note_index+1'b1;end
                else note_count<=note_count+1'b1;
                if(acr_count==47) begin acr_count<=0;acr_valid<=1;end
                else acr_count<=acr_count+1'b1;
            end else accumulator<=accumulator+48000;
        end
    end
endmodule
