// Single-image transition compositor. No frame-buffer/read-enable control and
// no pipeline register: insert at the existing registered fade stage.
module gallery_transition_v1(
    input [23:0] rgb,
    input [10:0] x,
    input [10:0] y,
    input [4:0] fade_alpha,
    input manual_active,
    input [5:0] manual_phase,
    input valid,
    output reg [23:0] out_rgb
);
    localparam [23:0] CURTAIN=24'h101c30;
    wire [4:0] alpha=(fade_alpha>=5'd16)?5'd16:fade_alpha;
    // Pixels 511 and 512 share the centre. The single cached image remains
    // untouched: this stage only selects an opaque light-gold procedural veil
    // or the already-fetched pixel. No textures, RAM or extra pixel cycles.
    wire [10:0] distance=(x>=11'd512)?x-11'd512:11'd511-x;
    // The triangular phase envelope is min(p,63-p), implemented as wiring.
    // Bottom gain <6 ensures that p*9 + gain*min(p,63-p) is strictly
    // increasing on both halves of the motion; curvature vanishes at ends.
    wire [4:0] curve_phase=manual_phase[5]?~manual_phase[4:0]:manual_phase[4:0];
    wire [8:0] y_pair=y[9:1];
    wire [17:0] curve_square=y_pair*y_pair;
    wire [7:0] curve_gain=curve_square[16:9];
    wire [12:0] curve_product=curve_gain*curve_phase;
    wire [7:0] bend=curve_product[12:5];
    // Overscan by the feather width before phase63, avoiding a last-frame
    // jump at the outside edges while retaining fully opaque phase zero.
    wire [10:0] half_width={2'b00,manual_phase,3'b000}+
                          {5'b00000,manual_phase}+{3'b000,bend};
    wire [10:0] edge_depth=half_width-distance;
    wire covered=(distance>=half_width);
    wire [10:0] curtain_depth=distance-half_width;
    // Two broad, low-contrast folds per half: triangle slopes are wiring and
    // 8-bit wrap, not a texture lookup or a variable-width arithmetic unit.
    wire [7:0] fold_position=distance[7:0]+{2'b00,y[8:3]}+{manual_phase,2'b00};
    wire [3:0] fold_light=fold_position[7]?~fold_position[6:3]:fold_position[6:3];
    wire [3:0] edge_shadow=covered && curtain_depth<11'd16 ?
                         (4'd15-curtain_depth[3:0])>>1:4'd0;
    wire [7:0] cloth_red=8'd200+{4'b0000,fold_light}-{4'b0000,edge_shadow};
    wire [7:0] cloth_green=8'd175+{4'b0000,fold_light}-{4'b0000,edge_shadow};
    wire [7:0] cloth_blue=8'd126+{4'b0000,fold_light}-{4'b0000,edge_shadow};
    wire [7:0] glint_y_a=8'd20+{2'b00,manual_phase};
    wire [7:0] glint_y_b=8'd127-{2'b00,manual_phase};
    wire micro_glint=(y[9:2]==glint_y_a || y[9:2]==glint_y_b);
    wire [7:0] flow_y=y[7:0]+{manual_phase,2'b00};
    wire edge_flow=flow_y[7:5]==3'd0;
    reg [23:0] curtain_rgb,background;
    reg [4:0] pixel_alpha;

    function [7:0] blend_channel;
      input [7:0] foreground,background;
      input [4:0] amount;
      reg signed [8:0] delta;
      reg signed [5:0] factor;
      reg signed [14:0] weighted,total;
      begin
        delta=$signed({1'b0,foreground})-$signed({1'b0,background});
        // Keep the multiplier signed and narrow so spare DSP blocks replace
        // the five-way LUT adder tree without changing this pipeline stage.
        factor=$signed({1'b0,amount});
        weighted=delta*factor;
        total=$signed({3'b0,background,4'b0})+weighted;
        blend_channel=total[11:4];
      end
    endfunction

    always @* begin
      pixel_alpha=alpha;
      background=CURTAIN;
      curtain_rgb={cloth_red,cloth_green,cloth_blue};
      if(manual_phase!=0 && manual_phase!=6'd63 && covered)begin
        // Muted gold is restricted to a 2-pixel edge and four tiny glints.
        // All these pixels are fully opaque; they never expose a bank switch.
        if(curtain_depth<11'd2)
          curtain_rgb=edge_flow?24'he4cf98:24'hb8a06c;
        if(curtain_depth<11'd5 && micro_glint)curtain_rgb=24'hf3e7c5;
      end
      if(manual_active)begin
        background=curtain_rgb;
        if(manual_phase==6'd63)pixel_alpha=5'd16;
        else if(manual_phase==0 || covered)pixel_alpha=0;
        else if(edge_depth>=11'd32)pixel_alpha=5'd16;
        else pixel_alpha={1'b0,edge_depth[5:1]};
      end
      // Invalid pixels are not displayed, and remain unmodified here.
      if(!valid)out_rgb=rgb;
      else if(manual_active && manual_phase==0)out_rgb=curtain_rgb;
      else if(manual_active && manual_phase==6'd63)out_rgb=rgb;
      else out_rgb={blend_channel(rgb[23:16],background[23:16],pixel_alpha),
                    blend_channel(rgb[15:8],background[15:8],pixel_alpha),
                    blend_channel(rgb[7:0],background[7:0],pixel_alpha)};
    end
endmodule
