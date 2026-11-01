`include "display_config.vh"
module media_osd #(parameter ENABLE_COVER=0,parameter SUBTITLE_PALETTE=0,parameter DEFER_WAVEFORM=0)(
    input clk,input rst,input frame_tick,
    input cover_active,
    input [3:0] state_code,
    input [4:0] fade_alpha,input manual_transition,input [5:0] manual_phase,
    input menu_active,input [2:0] menu_item,
    input rebuild_busy,input [2:0] rebuild_progress,input [2:0] rebuild_total,
    input [2:0] brightness_level,input [2:0] contrast_level,input [2:0] zoom_level,
    input [1:0] scale_override,input spectrum_enable,input [2:0] scene,
    input audio_valid,input signed [23:0] audio_sample,input audio_stream_reset,
    input valid,input [10:0] x,input [10:0] y,input [23:0] rgb,
    output reg out_valid,output reg out_sof,output reg out_last,output reg [23:0] out_rgb,
    output [23:0] subtitle_paper_rgb,output [23:0] subtitle_ink_rgb,
    output reg waveform_line,output reg waveform_halo,output reg [23:0] waveform_rgb
);
    reg menu0,menu1,menu_d;
    reg cover_d;
    reg rebuild0,rebuild1,rebuild_d;
    reg [2:0] progress0,progress1,progress_d,total0,total1,total_d;
    reg [2:0] item0,item1,item_d,bri0,bri1,bri_d,con0,con1,con_d,zoom_d;
    reg [1:0] scale0,scale1,scale_d;
    reg spec0,spec1,spec_d;
    reg [3:0] state0,state1,state_d;
    reg valid_d;
    reg [10:0] x_d,y_d;
    reg [23:0] rgb_d;
    reg valid_adjusted;
    reg [10:0] x_adjusted,y_adjusted;
    reg [23:0] rgb_adjusted;
    wire [8:0] curtain_y_pair=y[9:1];
    wire [17:0] curtain_curve_square=curtain_y_pair*curtain_y_pair;
    reg [7:0] curtain_gain_adjusted;
    // The border mask occupies the EXISTING adjustment register stage. Its
    // geometry is calculated in parallel with brightness/contrast, not in the
    // fade arithmetic path, and adds neither pixel latency nor frame storage.
    reg [10:0] border_left,border_right,border_top,border_bottom;
    reg [11:0] border_right_offset,border_bottom_offset,border_left_offset;
    reg [11:0] border_perimeter,border_head;
    reg [2:0] border_step,border_zoom,border_scene;
    reg [2:0] border_peak,border_energy;
    reg border_sample_seen;
    reg border_hit,border_hit_q;
    reg [4:0] border_t,border_t_q;
    reg [2:0] border_scene_q;
    reg [2:0] border_light_q;
    reg [11:0] border_position,border_distance;
    reg [10:0] border_triangle;
    reg [23:0] rgb_border;
    wire [7:0] border_abs=audio_sample[23]?
        (~audio_sample[23:16]+8'd1):audio_sample[23:16];
    wire [2:0] border_level=border_abs[7]?3'd7:border_abs[6:4];
    wire [2:0] border_frame_peak=audio_valid && border_level>border_peak?
        border_level:border_peak;
    wire border_frame_audio=border_sample_seen || audio_valid;
    wire [2:0] border_next_energy=border_frame_peak>=border_energy?
        border_frame_peak:(border_energy==0?3'd0:border_energy-3'd1);
    wire [4:0] border_advance={2'b00,border_step}+{1'b0,border_next_energy,1'b0};
    wire [4:0] curtain_alpha;
    wire [23:0] curtain_background;
    gallery_transition #(.PRECOMPUTED_GAIN(1)) u_gallery_transition(.rgb(24'd0),.x(x_adjusted),.y(y_adjusted),
      .fade_alpha(fade_alpha),.manual_active(manual_transition),
      .manual_phase(manual_phase),
      .valid(valid_adjusted),.curve_gain_in(curtain_gain_adjusted),.out_rgb(),
      .out_alpha(curtain_alpha),.out_background(curtain_background));
    // Match the waveform's four-clock geometry pipeline. Only two extra
    // pixel clocks (39 ns) are added; audio and cue clocks are unchanged.
    reg valid_fade,valid_hold;
    reg [10:0] x_fade,y_fade,x_hold,y_hold;
    reg [23:0] rgb_fade,rgb_hold;
    reg [4:0] alpha_fade;
    reg [23:0] background_fade;
    // Pre-mix the two subtitle colours with exactly the same curtain/fade.
    // This arithmetic runs beside the existing RGB hold stage, before any
    // character lookup. It lets the final subtitle layer reveal with the
    // picture without painting over opaque cloth or adding pixel cycles.
    generate if(SUBTITLE_PALETTE)begin: subtitle_transition
      wire [4:0] inverse_alpha=5'd16-alpha_fade;
      wire [11:0] cloth_r=background_fade[23:16]*inverse_alpha;
      wire [11:0] cloth_g=background_fade[15:8]*inverse_alpha;
      wire [11:0] cloth_b=background_fade[7:0]*inverse_alpha;
      wire [11:0] white_weight={alpha_fade,8'b0}-{7'b0,alpha_fade};
      wire [11:0] ink_r_weight={3'b0,alpha_fade,4'b0};
      wire [11:0] ink_g_weight={3'b0,alpha_fade,4'b0}+{4'b0,alpha_fade,3'b0};
      wire [11:0] ink_b_weight={2'b0,alpha_fade,5'b0};
      wire [11:0] paper_r=cloth_r+white_weight,paper_g=cloth_g+white_weight,paper_b=cloth_b+white_weight;
      wire [11:0] ink_r=cloth_r+ink_r_weight,ink_g=cloth_g+ink_g_weight,ink_b=cloth_b+ink_b_weight;
      reg [23:0] paper_hold,paper_d,paper_q,paper_out;
      reg [23:0] ink_hold,ink_d,ink_q,ink_out;
      always @(posedge clk or posedge rst)begin
        if(rst)begin
          paper_hold<=0;paper_d<=0;paper_q<=0;paper_out<=0;
          ink_hold<=0;ink_d<=0;ink_q<=0;ink_out<=0;
        end else begin
          paper_hold<={paper_r[11:4],paper_g[11:4],paper_b[11:4]};
          ink_hold<={ink_r[11:4],ink_g[11:4],ink_b[11:4]};
          paper_d<=paper_hold;paper_q<=paper_d;paper_out<=paper_q;
          ink_d<=ink_hold;ink_q<=ink_d;ink_out<=ink_q;
        end
      end
      assign subtitle_paper_rgb=paper_out;
      assign subtitle_ink_rgb=ink_out;
    end else begin: subtitle_transition_disabled
      assign subtitle_paper_rgb=24'hffffff;
      assign subtitle_ink_rgb=24'h101820;
    end endgenerate
    // Legacy port name spectrum_enable is retained for existing test/board
    // integration. SW1 now selects a real time-domain waveform, not a DFT.
    // audio_valid is a consumed-sample pulse, NOT the HDMI packet-valid tick.
    wire wave_line,wave_halo;
    wire [23:0] wave_rgb;
    wire wave_visible=spec_d && !cover_d && fade_alpha==16;
    // Keep menus/errors above the trace. Ordinary picture pixels defer the
    // existing single waveform to the final subtitle compositor instead.
    wire wave_front=valid_d && wave_visible && !menu_d && !rebuild_d && state_d!=14;
    audio_waveform u_waveform(.clk(clk),.rst(rst),.stream_reset(audio_stream_reset),
      .frame_tick(frame_tick),.sample_valid(audio_valid),.sample(audio_sample),
      .scene(scene),.valid(valid),.x(x),.y(y),
      .line_hit(wave_line),.halo_hit(wave_halo),.line_rgb(wave_rgb));

    reg ascii_active;
    reg [7:0] ch;
    integer cell_id,row,col;
    reg [2:0] menu_row,bar_id;
    reg [4:0] menu_col;
    reg [5:0] menu_local_y;
    reg [2:0] bar_level;
    reg [23:0] color,text_color;
    // Explicit-width local coordinates keep fixed-size menu decoders from
    // becoming 32-bit subtract/shift/comparison chains through integer temps.
    wire [10:0] mx_header=x_d-11'd384,my_header=y_d-11'd126;
    wire [10:0] mx_hint=x_d-11'd328,my_hint=y_d-11'd480;
    wire [10:0] mx_label=x_d-11'd296,mx_value=x_d-11'd568;
    wire [10:0] mx_arrow=x_d-11'd272,my_rows=y_d-11'd200;
    wire [10:0] mx_bar=x_d-11'd560,mx_dots=x_d-11'd480;

    // The original project converted the TF-card Anlogic BMP into this small
    // 96x64 palette ROM. Request with the preceding coordinate pipeline stage
    // so the synchronous ROM result is aligned with x_d/y_d.
    wire logo_req_area=x_hold>=920 && x_hold<1016 && y_hold>=16 && y_hold<80;
    wire [6:0] logo_dy=y_hold-16;
    wire [12:0] logo_addr=logo_req_area ?
      ((logo_dy<<6)+(logo_dy<<5)+(x_hold-920)) : 13'd0;
    wire [1:0] logo_palette;
    wire logo_area=x_d>=920 && x_d<1016 && y_d>=16 && y_d<80;
    osd_assets u_assets(.clk(clk),.logo_addr(logo_addr),.logo_palette(logo_palette));

    function [7:0] adjust_channel;
      input [7:0] value;input [2:0] bri,con;
      // Brightness peaks at 382 before clipping; contrast is -64..318.
      // Signed ten bits cover both, avoiding replicated twelve-bit adders.
      reg signed [9:0] t,d,q;
      begin
        t=$signed({1'b0,value});
        case(bri)
          0:t=t>>>1;1:t=t-(t>>>2);
          3:t=t+(t>>>2);4:t=t+(t>>>1);
          default:t=t;
        endcase
        if(t<0)t=0;else if(t>255)t=255;
        d=t-128;
        case(con)
          0:q=(d>>>1)+128;
          1:q=d-(d>>>2)+128;
          3:q=d+(d>>>2)+128;
          4:q=d+(d>>>1)+128;
          default:q=d+128;
        endcase
        if(q<0)adjust_channel=0;else if(q>255)adjust_channel=255;else adjust_channel=q[7:0];
      end
    endfunction
    // Square in adjusted, multiply by phase in fade. Blend in the existing
    // rgb_hold stage, keeping all six RGB/valid/coordinate stages unchanged.
    function [7:0] curtain_blend_channel;
      input [7:0] foreground,background;
      input [4:0] amount;
      reg signed [8:0] delta;
      reg signed [5:0] factor;
      reg signed [14:0] weighted,total;
      begin
        delta=$signed({1'b0,foreground})-$signed({1'b0,background});
        factor=$signed({1'b0,amount});
        weighted=delta*factor;
        total=$signed({3'b0,background,4'b0})+weighted;
        curtain_blend_channel=total[11:4];
      end
    endfunction
    function [23:0] alpha75;
      input [23:0] bg,fg;
      begin alpha75={((fg[23:16]>>1)+(fg[23:16]>>2)+(bg[23:16]>>2)),
                     ((fg[15:8]>>1)+(fg[15:8]>>2)+(bg[15:8]>>2)),
                     ((fg[7:0]>>1)+(fg[7:0]>>2)+(bg[7:0]>>2))};end
    endfunction

    // Four-pixel line, inset two pixels from the visible artwork. A circular
    // distance followed by min(d,P-d) has matching endpoints and no seam.
    // Only fixed shifts normalise its half-perimeter; no pixel multiplier.
    always @(posedge clk or posedge rst)begin
      if(rst)begin
        border_left<=2;border_right<=1021;border_top<=2;border_bottom<=597;
        border_right_offset<=1017;border_bottom_offset<=2635;border_left_offset<=3230;
        border_perimeter<=3228;border_step<=4;border_head<=0;
        border_zoom<=2;border_scene<=0;
        border_peak<=0;border_energy<=0;border_sample_seen<=0;
      end else begin
        case(zoom_level)
          0:begin
            border_left<=258;border_right<=765;border_top<=152;border_bottom<=447;
            border_right_offset<=355;border_bottom_offset<=1567;border_left_offset<=1756;
            border_perimeter<=1604;border_step<=2;
          end
          1:begin
            border_left<=130;border_right<=893;border_top<=77;border_bottom<=522;
            border_right_offset<=686;border_bottom_offset<=2101;border_left_offset<=2493;
            border_perimeter<=2416;border_step<=3;
          end
          default:begin
            border_left<=2;border_right<=1021;border_top<=2;border_bottom<=597;
            border_right_offset<=1017;border_bottom_offset<=2635;border_left_offset<=3230;
            border_perimeter<=3228;border_step<=4;
          end
        endcase
        border_zoom<=zoom_level;border_scene<=scene;
        if(audio_stream_reset || border_zoom!=zoom_level || border_scene!=scene)begin
          border_head<=0;border_peak<=0;border_energy<=0;border_sample_seen<=0;
        end else begin
          if(audio_valid)begin
            border_sample_seen<=1;
            if(border_level>border_peak)border_peak<=border_level;
          end
          if(frame_tick)begin
            border_peak<=0;border_sample_seen<=0;
            // A zero-valued PCM sample is still playback. Only the absence
            // of consumed samples pauses both phase and visible brightness.
            if(border_frame_audio)begin
              border_energy<=border_next_energy;
              if(border_head>=border_perimeter-border_advance)
                border_head<=border_head+border_advance-border_perimeter;
              else border_head<=border_head+border_advance;
            end
          end
        end
      end
    end
    always @* begin
      border_hit=0;border_t=0;border_position=0;border_distance=0;border_triangle=0;
      if(valid && scene>=1 && scene<=4 && !cover_d && state_d!=14 && !rebuild_d &&
         x>=border_left && x<=border_right && y>=border_top && y<=border_bottom)begin
        if(y<border_top+11'd4)begin
          border_hit=1;border_position={1'b0,x}-{1'b0,border_left};
        end else if(x>=border_right-11'd3)begin
          border_hit=1;border_position={1'b0,y}+border_right_offset;
        end else if(y>=border_bottom-11'd3)begin
          border_hit=1;border_position=border_bottom_offset-{1'b0,x};
        end else if(x<border_left+11'd4)begin
          border_hit=1;border_position=border_left_offset-{1'b0,y};
        end
        border_distance=border_head-border_position;
        if(border_head<border_position)border_distance=border_distance+border_perimeter;
        border_triangle=border_distance<=(border_perimeter>>1)?
          border_distance:(border_perimeter-border_distance);
        case(border_zoom)
          0:border_t=(border_triangle>>5)+(border_triangle>>7);
          1:border_t=(border_triangle>>6)+(border_triangle>>7)+(border_triangle>>8);
          default:border_t=(border_triangle>>6)+(border_triangle>>8);
        endcase
      end
    end
    // The frame energy adds 0..28 to colours whose maximum is 227.
    // Every segment uses constant shift/add slopes and shares its endpoints.
    function [23:0] border_palette;
      input [2:0] instrument;input [4:0] t;input [2:0] light;
      reg [7:0] r,g,b;reg [3:0] u;reg [7:0] lift;
      begin
        u=t[3:0];lift={3'b000,light,2'b00};
        case(instrument)
          1:begin r=8'd80+{1'b0,t,2'b00};g=8'd152+{3'b000,t};b=8'd148-{2'b00,t,1'b0};end
          2:begin r=8'd132+{2'b00,t,1'b0}+{3'b000,t};g=8'd56+{1'b0,t,2'b00};b=8'd48+{3'b000,t};end
          3:if(!t[4])begin
              r=8'd60+{3'b000,u,1'b0};g=8'd126+{3'b000,u,1'b0}+{4'b0000,u};b=8'd94+{2'b00,u,2'b00};
            end else begin
              r=8'd92+{2'b00,u,2'b00}+{3'b000,u,1'b0};
              g=8'd174+{3'b000,u,1'b0}+{4'b0000,u};b=8'd158+{2'b00,u,2'b00};
            end
          default:if(!t[4])begin
              r=8'd164+{3'b000,u,1'b0}+{4'b0000,u};g=8'd44+{2'b00,u,2'b00}+{4'b0000,u};b=8'd32+{4'b0000,u};
            end else begin
              r=8'd212+{4'b0000,u};g=8'd124+{2'b00,u,2'b00}+{4'b0000,u};
              b=8'd48+{2'b00,u,2'b00}+{4'b0000,u};
            end
        endcase
        border_palette={r+lift,g+lift,b+lift};
      end
    endfunction
    always @* begin
      rgb_border=border_hit_q?border_palette(border_scene_q,border_t_q,border_light_q):rgb_adjusted;
    end
    function [7:0] scale_char;
      input [1:0] mode;input [4:0] pos;
      begin
        scale_char=" ";
        case(mode)
          0:case(pos)0:scale_char="S";1:scale_char="C";2:scale_char="R";3:scale_char="I";4:scale_char="P";5:scale_char="T";endcase
          1:case(pos)0:scale_char="O";1:scale_char="R";2:scale_char="I";3:scale_char="G";4:scale_char="I";5:scale_char="N";6:scale_char="A";7:scale_char="L";endcase
          2:case(pos)0:scale_char="F";1:scale_char="I";2:scale_char="T";endcase
          default:case(pos)0:scale_char="F";1:scale_char="I";2:scale_char="L";3:scale_char="L";endcase
        endcase
      end
    endfunction
    function [7:0] level_char;
      input [2:0] level;input [4:0] pos;
      begin
        level_char=" ";
        case(level)
          0:case(pos)0:level_char="5";1:level_char="0";2:level_char="%";endcase
          1:case(pos)0:level_char="7";1:level_char="5";2:level_char="%";endcase
          2:case(pos)0:level_char="1";1:level_char="0";2:level_char="0";3:level_char="%";endcase
          3:case(pos)0:level_char="1";1:level_char="2";2:level_char="5";3:level_char="%";endcase
          default:case(pos)0:level_char="1";1:level_char="5";2:level_char="0";3:level_char="%";endcase
        endcase
      end
    endfunction
    function [7:0] menu_char;
      input [2:0] r;input [4:0] c;
      begin
        menu_char=" ";
        case(r)
          0:case(c)0:menu_char="Z";1:menu_char="O";2:menu_char="O";3:menu_char="M";endcase
          1:case(c)0:menu_char="B";1:menu_char="R";2:menu_char="I";3:menu_char="G";4:menu_char="H";5:menu_char="T";6:menu_char="N";7:menu_char="E";8:menu_char="S";9:menu_char="S";endcase
          2:case(c)0:menu_char="C";1:menu_char="O";2:menu_char="N";3:menu_char="T";4:menu_char="R";5:menu_char="A";6:menu_char="S";7:menu_char="T";endcase
          default:case(c)0:menu_char="E";1:menu_char="X";2:menu_char="I";3:menu_char="T";endcase
        endcase
      end
    endfunction
    function [7:0] hint_char;
      input [4:0] pos;
      begin
        hint_char=" ";
        case(pos)
          0:hint_char="K";1:hint_char="2";3:hint_char="-";
          7:hint_char="K";8:hint_char="3";
          10:hint_char="S";11:hint_char="E";12:hint_char="L";
          13:hint_char="E";14:hint_char="C";15:hint_char="T";
          19:hint_char="K";20:hint_char="4";22:hint_char="+";
        endcase
      end
    endfunction
    function [7:0] return_char;
      input [4:0] pos;
      begin
        return_char=" ";
        case(pos)0:return_char="R";1:return_char="E";2:return_char="T";
          3:return_char="U";4:return_char="R";5:return_char="N";endcase
      end
    endfunction

    always @(posedge clk or posedge rst)begin
      if(rst)begin
        menu0<=0;menu1<=0;menu_d<=0;item0<=0;item1<=0;item_d<=0;
        cover_d<=0;
        rebuild0<=0;rebuild1<=0;rebuild_d<=0;progress0<=0;progress1<=0;progress_d<=0;
        total0<=0;total1<=0;total_d<=0;
        bri0<=2;bri1<=2;bri_d<=2;con0<=2;con1<=2;con_d<=2;scale0<=0;scale1<=0;scale_d<=0;
        zoom_d<=2;
        spec0<=1;spec1<=1;spec_d<=1;
        state0<=0;state1<=0;state_d<=0;
        valid_d<=0;x_d<=0;y_d<=0;rgb_d<=0;
        valid_adjusted<=0;x_adjusted<=0;y_adjusted<=0;rgb_adjusted<=0;curtain_gain_adjusted<=0;
        border_hit_q<=0;border_t_q<=0;border_scene_q<=0;border_light_q<=0;
        valid_fade<=0;x_fade<=0;y_fade<=0;rgb_fade<=0;
        alpha_fade<=0;background_fade<=0;
        valid_hold<=0;x_hold<=0;y_hold<=0;rgb_hold<=0;
      end else begin
        valid_adjusted<=valid;x_adjusted<=x;y_adjusted<=y;
        curtain_gain_adjusted<=curtain_curve_square[16:9];
        border_hit_q<=border_hit;border_t_q<=border_t;
        border_scene_q<=scene;border_light_q<=border_energy;
        rgb_adjusted<={adjust_channel(rgb[23:16],bri_d,con_d),
          adjust_channel(rgb[15:8],bri_d,con_d),adjust_channel(rgb[7:0],bri_d,con_d)};
        valid_fade<=valid_adjusted;x_fade<=x_adjusted;y_fade<=y_adjusted;
        rgb_fade<=rgb_border;
        alpha_fade<=curtain_alpha;background_fade<=curtain_background;
        valid_hold<=valid_fade;x_hold<=x_fade;y_hold<=y_fade;
        if(!valid_fade)rgb_hold<=rgb_fade;
        else if(alpha_fade==0)rgb_hold<=background_fade;
        else if(alpha_fade==16)rgb_hold<=rgb_fade;
        else rgb_hold<={curtain_blend_channel(rgb_fade[23:16],background_fade[23:16],alpha_fade),
                       curtain_blend_channel(rgb_fade[15:8],background_fade[15:8],alpha_fade),
                       curtain_blend_channel(rgb_fade[7:0],background_fade[7:0],alpha_fade)};
        valid_d<=valid_hold;x_d<=x_hold;y_d<=y_hold;rgb_d<=rgb_hold;
        menu0<=menu_active;menu1<=menu0;item0<=menu_item;item1<=item0;
        rebuild0<=rebuild_busy;rebuild1<=rebuild0;
        progress0<=rebuild_progress;progress1<=progress0;total0<=rebuild_total;total1<=total0;
        bri0<=brightness_level;bri1<=bri0;con0<=contrast_level;con1<=con0;
        // ZOOM is already frame-locked in this clock domain by the top.
        // Do not latch it one more frame late relative to the image geometry.
        zoom_d<=zoom_level;
        scale0<=scale_override;scale1<=scale0;spec0<=spectrum_enable;spec1<=spec0;
        state0<=state_code;state1<=state0;
        if(frame_tick)begin
          cover_d<=ENABLE_COVER && cover_active;
          menu_d<=menu1;item_d<=item1;bri_d<=bri1;con_d<=con1;scale_d<=scale1;
          rebuild_d<=rebuild1;progress_d<=progress1;total_d<=total1;
          spec_d<=spec1;state_d<=state1;
        end
      end
    end

    always @* begin
      color=rgb_d;
      ascii_active=0;ch=" ";cell_id=0;row=0;col=0;
      menu_row=0;menu_col=0;menu_local_y=0;bar_id=0;bar_level=0;text_color=24'h101820;

      // Wave masks are aligned with x_d/y_d after four pixel stages.
      // Original shift-only half-mixed halo; PCM gain and trace geometry are unchanged.
      if(wave_visible && (!DEFER_WAVEFORM || !wave_front))begin
        if(wave_halo)color={((color[23:16]>>1)+(wave_rgb[23:16]>>1)),
          ((color[15:8]>>1)+(wave_rgb[15:8]>>1)),
          ((color[7:0]>>1)+(wave_rgb[7:0]>>1))};
        if(wave_line)color=wave_rgb;
      end

      // With no legal picture, suppress decorative layers and show only error text.
      if(state_d==14)begin
        color=24'hf4f6f8;text_color=24'hc62828;
        if(y_d>=270 && y_d<284 && x_d>=400 && x_d<624)begin
          ascii_active=1;cell_id=(x_d-400)>>4;row=(y_d-270)>>1;col=((x_d-400)>>1)&7;
          case(cell_id)
            0:ch="N";1:ch="O";3:ch="V";4:ch="A";5:ch="L";6:ch="I";7:ch="D";
            9:ch="I";10:ch="M";11:ch="A";12:ch="G";13:ch="E";default:ch=" ";
          endcase
        end else if(y_d>=310 && y_d<324 && x_d>=400 && x_d<624)begin
          ascii_active=1;cell_id=(x_d-400)>>4;row=(y_d-310)>>1;col=((x_d-400)>>1)&7;
          case(cell_id)
            0:ch="C";1:ch="H";2:ch="E";3:ch="C";4:ch="K";6:ch="T";7:ch="F";
            9:ch="C";10:ch="A";11:ch="R";12:ch="D";default:ch=" ";
          endcase
        end
      end else if(rebuild_d)begin
        // Mode changes re-render the cached frames from TF. Keep the user
        // informed while scanout is intentionally blanked.
        if(x_d>=336 && x_d<688 && y_d>=224 && y_d<376)
          color=alpha75(color,24'h263b52);
        text_color=24'hffffff;
        if(y_d>=254 && y_d<268 && x_d>=424 && x_d<600)begin
          ascii_active=1;cell_id=(x_d-424)>>4;row=(y_d-254)>>1;col=((x_d-424)>>1)&7;
          case(cell_id)0:ch="R";1:ch="E";2:ch="N";3:ch="D";4:ch="E";
            5:ch="R";6:ch="I";7:ch="N";8:ch="G";default:ch=" ";endcase
        end else if(y_d>=294 && y_d<308 && x_d>=424 && x_d<600)begin
          ascii_active=1;cell_id=(x_d-424)>>4;row=(y_d-294)>>1;col=((x_d-424)>>1)&7;
          ch=scale_char(scale_d,cell_id[4:0]);
        end else if(y_d>=334 && y_d<348 && x_d>=424 && x_d<616)begin
          ascii_active=1;cell_id=(x_d-424)>>4;row=(y_d-334)>>1;col=((x_d-424)>>1)&7;
          case(cell_id)
            0:ch="I";1:ch="M";2:ch="A";3:ch="G";4:ch="E";
            6:ch="0"+((progress_d<total_d)?progress_d+1'b1:total_d);
            8:ch="/";10:ch="0"+total_d;default:ch=" ";
          endcase
        end
      end else if(menu_d)begin
        // Opaque ink-blue panel: readable over every photo, with fixed contrast
        // rather than several translucent layers. Same four controls/keys.
        color={1'b0,color[23:17],1'b0,color[15:9],1'b0,color[7:1]};
        if(x_d>=248 && x_d<776 && y_d>=88 && y_d<512)begin
          color=24'h192b31;
          if(x_d==248 || x_d==775 || y_d==88 || y_d==511)color=24'had966a;
          else if(y_d<180)color=24'h17272d;
          if(y_d==180)color=24'had966a;
          if(y_d>=462 && y_d<463 && x_d>=272 && x_d<752)color=24'h45545a;
          if(y_d>=160 && y_d<164 && x_d>=480 && x_d<544 && mx_dots[3:0]<10)
            color=({1'b0,mx_dots[5:4]}==item_d)?24'hf1cf91:24'h45545a;
        end
        if(y_d>=126 && y_d<140 && x_d>=384 && x_d<640)begin
          text_color=24'hede5d4;ascii_active=1;cell_id=mx_header[7:4];
          row=my_header[3:1];col=mx_header[3:1];
          case(cell_id)0:ch="D";1:ch="I";2:ch="S";3:ch="P";4:ch="L";5:ch="A";6:ch="Y";
            8:ch="S";9:ch="E";10:ch="T";11:ch="T";12:ch="I";13:ch="N";14:ch="G";15:ch="S";default:ch=" ";endcase
        end else if(y_d>=480 && y_d<494 && x_d>=328 && x_d<696)begin
          text_color=24'hc2c9c6;ascii_active=1;cell_id=mx_hint[8:4];
          row=my_hint[3:1];col=mx_hint[3:1];ch=hint_char(cell_id[4:0]);
        end else if(y_d>=200 && y_d<456)begin
          menu_row={1'b0,my_rows[7:6]};
          menu_local_y=my_rows[5:0];
          if(menu_row<4)begin
            text_color=24'hede5d4;
            if(item_d==menu_row && x_d>=264 && x_d<760 && menu_local_y<56)begin
              color=24'h345257;
              if(x_d<268)color=24'hb54b3d;
            end
            if(x_d>=552 && x_d<744 && menu_local_y>=8 && menu_local_y<32)
              color=item_d==menu_row?24'h243d43:24'h20343b;
            if(menu_row<3 && menu_local_y>=40 && menu_local_y<44 &&
               x_d>=560 && x_d<720 && mx_bar[4:0]<24)begin
              bar_id=mx_bar[7:5];bar_level=menu_row==0?zoom_d:(menu_row==1?bri_d:con_d);
              color=bar_id<=bar_level?24'hbfa575:24'h45545a;
            end
            if(menu_local_y>=12 && menu_local_y<26)begin
              row=(menu_local_y-12)>>1;
              if(x_d>=272 && x_d<288)begin
                ascii_active=1;col=mx_arrow[3:1];ch=item_d==menu_row?">":" ";
              end else if(x_d>=296 && x_d<472)begin
                ascii_active=1;menu_col={1'b0,mx_label[7:4]};col=mx_label[3:1];
                ch=menu_char(menu_row[2:0],menu_col[4:0]);
              end else if(x_d>=568 && x_d<728)begin
                text_color=24'hede5d4;
                ascii_active=1;menu_col={1'b0,mx_value[7:4]};col=mx_value[3:1];
                case(menu_row)
                  0:ch=level_char(zoom_d,menu_col[4:0]);
                  1:ch=level_char(bri_d,menu_col[4:0]);
                  2:ch=level_char(con_d,menu_col[4:0]);
                  default:ch=return_char(menu_col[4:0]);
                endcase
              end
            end
          end
        end
      end else if(!cover_d && logo_area && logo_palette!=0)begin
        case(logo_palette)
          1:color=alpha75(color,24'he62b2f);
          2:color=alpha75(color,24'h1767b1);
          default:color=alpha75(color,24'h303840);
        endcase
      end
    end
    // Character selection and font lookup are independent pipeline stages.
    // Keep x -> subtract -> character mux -> glyph ROM -> pixel mux out of
    // a single video clock; removing a label does not change pixel latency.
    reg text_active_q,valid_q,sof_q,last_q;
    reg [2:0] col_q;
    reg [23:0] color_q,text_color_q;
    reg wave_line_q,wave_halo_q;
    reg [23:0] wave_rgb_q;
    wire [4:0] ascii_pixels;
    ascii_font_rom u_ascii(.clk(clk),.code(ch[6:0]),.row(row[2:0]),.pixels(ascii_pixels));
    always @(posedge clk or posedge rst)begin
      if(rst)begin
        out_valid<=0;out_sof<=0;out_last<=0;out_rgb<=0;
        text_active_q<=0;valid_q<=0;sof_q<=0;last_q<=0;
        col_q<=0;color_q<=0;text_color_q<=0;
        wave_line_q<=0;wave_halo_q<=0;wave_rgb_q<=0;
        waveform_line<=0;waveform_halo<=0;waveform_rgb<=0;
      end
      else begin
        text_active_q<=ascii_active;col_q<=col[2:0];
        color_q<=color;text_color_q<=text_color;
        wave_line_q<=DEFER_WAVEFORM && wave_front && wave_line;
        wave_halo_q<=DEFER_WAVEFORM && wave_front && wave_halo;
        wave_rgb_q<=wave_rgb;
        waveform_line<=wave_line_q;waveform_halo<=wave_halo_q;waveform_rgb<=wave_rgb_q;
        valid_q<=valid_d;sof_q<=valid_d && x_d==0 && y_d==0;
        last_q<=valid_d && x_d==1023;
        out_valid<=valid_q;out_sof<=sof_q;out_last<=last_q;
        out_rgb<=text_active_q && col_q<5 && ascii_pixels[4-col_q]?text_color_q:color_q;
      end
    end
endmodule
