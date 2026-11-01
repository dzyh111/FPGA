`include "display_config.vh"
// Frame-boundary scan controller with a bandwidth-neutral fade transition.
// Only one SDRAM frame is read at a time: fade out, switch, then fade in.
module video_scan #(
    parameter H_ACTIVE=`H_ACTIVE, H_FP=`H_FP, H_SYNC=`H_SYNC, H_BP=`H_BP,
    parameter V_ACTIVE=`V_ACTIVE, V_FP=`V_FP, V_SYNC=`V_SYNC, V_BP=`V_BP,
    parameter IMG_W=800, IMG_H=600,
    parameter FADE_STEP_FRAMES=1,
    parameter ENABLE_COVER=0
)(
    input clk, input rst,
    input commit_toggle, input [1:0] commit_index,
    input commit_cover, output reg read_cover,
    input commit_manual, output reg manual_transition,
    output reg [5:0] manual_phase,
    input blank_toggle, output reg blank_ack,
    output reg commit_ack,
    output reg [1:0] read_index,
    output reg [1:0] next_index,
    output reg [9:0] slide_rows,
    output reg [4:0] fade_alpha,
    output reg transition_busy,
    output reg read_req, input read_req_ack,
    output reg display_enabled,
    output frame_tick, output line_start, output active, output image_active,
    output [10:0] x, output [10:0] y
);
    localparam HT=H_ACTIVE+H_FP+H_SYNC+H_BP, VT=V_ACTIVE+V_FP+V_SYNC+V_BP;
    localparam X0=H_SYNC+H_BP, Y0=V_SYNC+V_BP;
    localparam IX=(H_ACTIVE-IMG_W)/2, IY=(V_ACTIVE-IMG_H)/2;
    localparam ST_STEADY=2'd0,ST_FADE_OUT=2'd1,ST_SWITCH=2'd2,ST_FADE_IN=2'd3;
    reg [11:0] hc,vc;
    (* ASYNC_REG = "TRUE" *) reg [1:0] commit_sync, ack_sync, blank_sync;
    reg [1:0] index_s0,index_s1,pending_index;
    (* ASYNC_REG = "TRUE" *) reg cover_s0,cover_s1;
    (* ASYNC_REG = "TRUE" *) reg manual_s0,manual_s1;
    reg pending_cover;
    reg pending_token;
    reg [1:0] transition_state;
    reg blanking,pending_blank_token;
    reg [3:0] delay_req;
    reg [3:0] fade_div;
    reg [5:0] manual_open_count;
    // Eight quick closing frames plus 48 lighter opening frames (~0.933 s).
    // Close quickly, then reveal the new cache more gently. The old 0..16
    // alpha remains available to waveform/OSD gating and automatic fades.
    wire [5:0] manual_close=manual_phase<=6'd8 ? 6'd0 : manual_phase-6'd8;
    // floor(frame*63/48) = floor(frame*21/16), exact for frames 1..48.
    // A narrow shift/add mapping needs neither a divider nor a multiplier.
    wire [5:0] open_frame_next=manual_open_count+6'd1;
    wire [9:0] open_phase_product={open_frame_next,4'b0000}+
                                 {2'b00,open_frame_next,2'b00}+{4'b0000,open_frame_next};
    wire [5:0] manual_open=open_phase_product[9:4];
    function [4:0] curtain_alpha;
      input [5:0] phase;
      begin curtain_alpha=phase==6'd63 ? 5'd16 : {1'b0,phase[5:2]};end
    endfunction
    assign frame_tick=(hc==0 && vc==0);
    assign line_start=(hc==0);
    assign active=(hc>=X0 && hc<X0+H_ACTIVE && vc>=Y0 && vc<Y0+V_ACTIVE);
    assign x=hc-X0;
    assign y=vc-Y0;
    assign image_active=active && x>=IX && x<IX+IMG_W && y>=IY && y<IY+IMG_H;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            hc<=0;vc<=0;commit_sync<=0;ack_sync<=0;blank_sync<=0;index_s0<=0;index_s1<=0;
            pending_index<=0;pending_token<=0;read_index<=0;next_index<=0;
            cover_s0<=0;cover_s1<=0;pending_cover<=0;read_cover<=0;
            manual_s0<=0;manual_s1<=0;manual_transition<=0;manual_phase<=0;manual_open_count<=0;
            slide_rows<=0;fade_alpha<=0;fade_div<=0;transition_state<=ST_STEADY;
            transition_busy<=0;commit_ack<=0;blank_ack<=0;blanking<=0;pending_blank_token<=0;
            delay_req<=0;read_req<=0;
            display_enabled<=0;
        end else begin
            commit_sync<={commit_sync[0],commit_toggle};
            blank_sync<={blank_sync[0],blank_toggle};
            index_s0<=commit_index;index_s1<=index_s0;
            cover_s0<=ENABLE_COVER?commit_cover:1'b0;cover_s1<=cover_s0;
            // Legacy named-port test benches may omit commit_manual. Treat
            // an unconnected input as automatic, never an unknown mask mode.
            if(commit_manual)manual_s0<=1'b1;else manual_s0<=1'b0;
            manual_s1<=manual_s0;
            ack_sync<={ack_sync[0],read_req_ack};
            if(hc==HT-1) begin hc<=0;if(vc==VT-1)vc<=0;else vc<=vc+1'b1;end
            else hc<=hc+1'b1;

            // Legacy reader selects one buffer when both indices match.
            next_index<=read_index;
            slide_rows<=0;

            if(frame_tick) begin
                // Refresh FIFO every displayed frame, including both fade phases.
                if(display_enabled && !read_req && !ack_sync[1] && transition_state!=ST_SWITCH)
                    delay_req<=8;
                if(fade_div==FADE_STEP_FRAMES-1)fade_div<=0;
                else fade_div<=fade_div+1'b1;
                case(transition_state)
                  ST_STEADY: begin
                    transition_busy<=0;
                    if(blank_sync[1]!=blank_ack)begin
                      manual_transition<=0;
                      manual_open_count<=0;
                      pending_blank_token<=blank_sync[1];blanking<=1;transition_busy<=1;fade_div<=0;
                      if(display_enabled)transition_state<=ST_FADE_OUT;
                      else begin blank_ack<=blank_sync[1];blanking<=0;end
                    end else if(commit_sync[1]!=commit_ack)begin
                      pending_index<=index_s1;pending_token<=commit_sync[1];
                      pending_cover<=cover_s1;
                      manual_transition<=manual_s1;
                      manual_open_count<=0;
                      manual_phase<=display_enabled ? 6'd63 : 6'd0;
                      transition_busy<=1;fade_div<=0;blanking<=0;
                      if(display_enabled)transition_state<=ST_FADE_OUT;
                      else begin
                        fade_alpha<=0;read_index<=index_s1;next_index<=index_s1;
                        read_cover<=cover_s1;
                        transition_state<=ST_SWITCH;delay_req<=8;
                      end
                    end else if(display_enabled && !read_req && !ack_sync[1])delay_req<=8;
                  end
                  ST_FADE_OUT: if(fade_div==FADE_STEP_FRAMES-1)begin
                    if((manual_transition && manual_phase<=8) || (!manual_transition && fade_alpha<=1))begin
                      fade_alpha<=0;manual_phase<=0;
                      if(blanking)begin
                        display_enabled<=0;blank_ack<=pending_blank_token;blanking<=0;
                        transition_state<=ST_STEADY;transition_busy<=0;
                      end else begin
                        read_index<=pending_index;next_index<=pending_index;
                        read_cover<=pending_cover;
                        transition_state<=ST_SWITCH;delay_req<=8;
                      end
                    end else if(manual_transition)begin
                      manual_phase<=manual_close;fade_alpha<=curtain_alpha(manual_close);
                    end else fade_alpha<=fade_alpha-1'b1;
                  end
                  ST_SWITCH: transition_busy<=1;
                  ST_FADE_IN: if(fade_div==FADE_STEP_FRAMES-1)begin
                    if((manual_transition && manual_open_count>=47) || (!manual_transition && fade_alpha>=15))begin
                      fade_alpha<=16;transition_state<=ST_STEADY;transition_busy<=0;
                      manual_phase<=63;
                      commit_ack<=pending_token;
                    end else if(manual_transition)begin
                      manual_phase<=manual_open;fade_alpha<=curtain_alpha(manual_open);
                      manual_open_count<=manual_open_count+1'b1;
                    end else fade_alpha<=fade_alpha+1'b1;
                  end
                endcase
            end

            if(delay_req!=0)begin
                delay_req<=delay_req-1'b1;
                if(delay_req==1)read_req<=1;
            end
            if(read_req && ack_sync[1])begin
                read_req<=0;
                if(transition_state==ST_SWITCH)begin
                    display_enabled<=1;
                    transition_state<=ST_FADE_IN;fade_alpha<=0;fade_div<=0;manual_open_count<=0;
                end
            end
        end
    end
endmodule
