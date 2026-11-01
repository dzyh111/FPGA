// Frozen 32-bit-counter reference from the prior signed-off red-curtain RTL.
module button_press_32bit_ref #(
    parameter integer CLK_HZ=40_000_000,
    parameter integer DEBOUNCE_MS=20
)(input clk,input rst,input key_n,output reg pulse);
    localparam integer LIMIT=(CLK_HZ/1000)*DEBOUNCE_MS;
    reg [1:0] sync;
    reg stable;
    reg [31:0] count;
    always @(posedge clk or posedge rst)begin
      if(rst)begin sync<=3;stable<=1;count<=0;pulse<=0;end
      else begin
        sync<={sync[0],key_n};pulse<=0;
        if(sync[1]==stable)count<=0;
        else if(count>=LIMIT-1)begin
          if(stable && !sync[1])pulse<=1;
          stable<=sync[1];count<=0;
        end else count<=count+1'b1;
      end
    end
endmodule

// KEY2 decreases/advances, KEY3 selects menu items, KEY4 increases/toggles.
module ui_control_32bit_ref #(
    parameter integer CLK_HZ=40_000_000,
    parameter integer IDLE_SECONDS=8
)(
    input clk,input rst,input key_prev,input key_menu,input key_next,
    output reg menu_active,output reg [2:0] menu_item,
    output reg [2:0] brightness_level,output reg [2:0] contrast_level,
    output wire [1:0] scale_override,output reg [2:0] zoom_level
);
    // Loader modes are no longer user controls. ZOOM changes only scanout.
    assign scale_override=2'd0;
    localparam integer IDLE_CYCLES=CLK_HZ*IDLE_SECONDS;
    wire p_pulse,m_pulse,n_pulse;
    reg [31:0] idle_cnt;
    button_press_32bit_ref #(.CLK_HZ(CLK_HZ)) u_prev(clk,rst,key_prev,p_pulse);
    button_press_32bit_ref #(.CLK_HZ(CLK_HZ)) u_menu(clk,rst,key_menu,m_pulse);
    button_press_32bit_ref #(.CLK_HZ(CLK_HZ)) u_next(clk,rst,key_next,n_pulse);
    always @(posedge clk or posedge rst)begin
      if(rst)begin
        menu_active<=0;menu_item<=0;brightness_level<=3'd2;contrast_level<=3'd2;
        zoom_level<=2;
        idle_cnt<=0;
      end else begin
        if(menu_active)begin
          if(p_pulse||m_pulse||n_pulse)idle_cnt<=0;
          else if(idle_cnt>=IDLE_CYCLES-1)begin menu_active<=0;idle_cnt<=0;end
          else idle_cnt<=idle_cnt+1'b1;
          if(m_pulse)begin
            if(menu_item==3)menu_item<=0;else menu_item<=menu_item+1'b1;
          end
          if(menu_item==0)begin
            if(p_pulse && zoom_level!=0)zoom_level<=zoom_level-1'b1;
            if(n_pulse && zoom_level!=4)zoom_level<=zoom_level+1'b1;
          end else if(menu_item==1)begin
            if(p_pulse && brightness_level!=0)brightness_level<=brightness_level-1'b1;
            if(n_pulse && brightness_level!=4)brightness_level<=brightness_level+1'b1;
          end else if(menu_item==2)begin
            if(p_pulse && contrast_level!=0)contrast_level<=contrast_level-1'b1;
            if(n_pulse && contrast_level!=4)contrast_level<=contrast_level+1'b1;
          end else if(menu_item==3 && (p_pulse||n_pulse))begin menu_active<=0;idle_cnt<=0;end
        end else begin
          idle_cnt<=0;
          if(m_pulse)begin menu_active<=1;menu_item<=0;end
        end
      end
    end
endmodule
