`timescale 1ns/1ps
// Independent SUB2 raster oracle: ordinary row-major /18 and %18 math.
// Do not duplicate the production four-output-row word-address decomposition.
module tb_subtitle_native24;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame_tick=0,wr_en=0,font_wr_en=0,font_ready=0;
 reg [8:0] wr_addr=0;reg [7:0] wr_data=0;
 reg [9:0] font_wr_addr=0;reg [17:0] font_wr_data=0;
 reg [1:0] image_index=0;
 reg valid=0,sof=0,last=0;reg [23:0] rgb=0;
 reg [12:0] scroll_value=13'd1024;
 integer xx=0,yy=0,scene_index=0;
 wire ov,os,ol;wire [23:0] orgb;
 subtitle_overlay #(.ENABLE_FONT24(1)) dut(
  .wr_clk(clk),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_data),
  .font_wr_en(font_wr_en),.font_wr_addr(font_wr_addr),.font_wr_data(font_wr_data),
  .font_ready(font_ready),.font_quiet_request(1'b0),
  .clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(1'b1),.show_picture(1'b1),
  .intro_pause(1'b0),.intro_restart(1'b0),.image_index(image_index),
  .len0(8'd40),.len1(8'd41),.len2(8'd40),.len3(8'd41),
  .valid(valid),.sof(sof),.last(last),.rgb(rgb),
  .subtitle_paper_rgb(24'hffffff),.subtitle_ink_rgb(24'h101820),
  .out_valid(ov),.out_sof(os),.out_last(ol),.out_rgb(orgb));

 reg [7:0] codes[0:511];
 reg [17:0] font_words[0:1023];
 reg [23:0] punctuation_rows[0:47];
 integer lengths[0:3];
 reg caption_active=0,checking=0,glyph_probe=0;
 function [23:0] reference_rgb;
  input [23:0] under;input integer px,py,sv,sc;
  input is_sof,is_valid,visible;
  integer tx,character_index,code_value,source_x,source_y,offset,word_address;
  reg ink_hit;reg [7:0] r,g,b;
  begin
   if(is_sof)begin px=0;py=0;end
   reference_rgb=under;
   if(is_valid && visible && px>=6 && px<1018 && py>=552 && py<594)begin
    r=192+under[23:16]/4;g=192+under[15:8]/4;b=192+under[7:0]/4;
    reference_rgb={r,g,b};
    tx=px+sv;
    if(py>=560 && py<592 && tx>=1024 && tx<1024+lengths[sc]*32)begin
     character_index=(tx-1024)/32;
     code_value=codes[sc*128+character_index];
     source_x=(((tx-1024)%32)*3)/4;
     source_y=((py-560)*3)/4;
     ink_hit=0;
     if(code_value==8'hc0 || code_value==8'hc1)
      ink_hit=punctuation_rows[(code_value-8'hc0)*24+source_y][23-source_x];
     else if(code_value>=8'he0)begin
      offset=source_y*24+source_x;
      word_address=(code_value-8'he0)*32+offset/18;
      ink_hit=font_words[word_address][17-offset%18];
     end else $fatal(1,"Native introduction has unexpected code %h at scene%0d cell%0d",code_value,sc+1,character_index);
     if(ink_hit)reference_rgb=24'h101820;
    end
   end
  end
 endfunction

 reg [23:0] rq[0:2];
 reg vq[0:2],sq[0:2],lq[0:2],gq[0:2];
 integer xq[0:2],yq[0:2],svq[0:2],scq[0:2];
 integer stage,glyph_pixels=0,ink_pixels=0,paper_pixels=0,boundary_pixels=0;
 integer metadata_cycles=0,marker_pixels=0,bubble_cycles=0,punctuation_pixels=0;
 integer reference_code;
 always @(posedge clk)begin
  if(rst)begin
   for(stage=0;stage<3;stage=stage+1)begin
    rq[stage]=0;vq[stage]=0;sq[stage]=0;lq[stage]=0;gq[stage]=0;
    xq[stage]=0;yq[stage]=0;svq[stage]=0;scq[stage]=0;
   end
  end else begin
   for(stage=2;stage>0;stage=stage-1)begin
    rq[stage]=rq[stage-1];vq[stage]=vq[stage-1];sq[stage]=sq[stage-1];lq[stage]=lq[stage-1];gq[stage]=gq[stage-1];
    xq[stage]=xq[stage-1];yq[stage]=yq[stage-1];svq[stage]=svq[stage-1];scq[stage]=scq[stage-1];
   end
   rq[0]=reference_rgb(rgb,xx,yy,scroll_value,scene_index,sof,valid,caption_active);
   vq[0]=valid;sq[0]=sof;lq[0]=last;gq[0]=glyph_probe;
   xq[0]=xx;yq[0]=yy;svq[0]=scroll_value;scq[0]=scene_index;
   #1;
   if(checking)begin
    metadata_cycles=metadata_cycles+1;
    if(ov!==vq[2] || os!==sq[2] || ol!==lq[2])
     $fatal(1,"Native24 three-cycle valid/SOF/EOL mismatch got%b%b%b expected%b%b%b",ov,os,ol,vq[2],sq[2],lq[2]);
    if(!vq[2])bubble_cycles=bubble_cycles+1;
    else begin
     if(orgb!==rq[2])$fatal(1,"Native24 RGB scene%0d xy%0d,%0d scroll%0d got%h expected%h",scq[2]+1,xq[2],yq[2],svq[2],orgb,rq[2]);
     if(sq[2] || lq[2])marker_pixels=marker_pixels+1;
     if(gq[2])begin
      glyph_pixels=glyph_pixels+1;
      if(rq[2]==24'h101820)ink_pixels=ink_pixels+1;
      else paper_pixels=paper_pixels+1;
      reference_code=codes[scq[2]*128+(xq[2]+svq[2]-1024)/32];
      if(reference_code==8'hc0 || reference_code==8'hc1)punctuation_pixels=punctuation_pixels+1;
     end else boundary_pixels=boundary_pixels+1;
    end
   end
  end
 end

 task tick;begin @(negedge clk);end endtask
 task frame;begin repeat(5)tick;frame_tick=1;tick;frame_tick=0;repeat(6)tick;end endtask
 task drive;
  input integer px,py,sv;
  input is_valid,is_sof,is_last,is_glyph;
  begin
   tick;xx=px;yy=py;scroll_value=sv;dut.x=px;dut.y=py;
   valid=is_valid;sof=is_sof;last=is_last;glyph_probe=is_glyph;
   rgb=24'h305071 ^ ((px*127+py*19+sv*3)&24'hffffff);
  end
 endtask
 task drain;begin repeat(6)drive(0,0,1024,0,0,0,0);end endtask
 integer scene,glyph,row,col,i,glyphs=0;
 integer xs[0:5],ys[0:7];
 initial begin
  lengths[0]=40;lengths[1]=41;lengths[2]=40;lengths[3]=41;
  xs[0]=0;xs[1]=5;xs[2]=6;xs[3]=1017;xs[4]=1018;xs[5]=1023;
  ys[0]=551;ys[1]=552;ys[2]=559;ys[3]=560;ys[4]=591;ys[5]=592;ys[6]=593;ys[7]=594;
  $readmemh("sim/gallery_subtitle_codes.hex",codes);
  $readmemh("sim/gallery_punctuation_24.hex",punctuation_rows);
  force dut.scroll=scroll_value;
  repeat(5)tick;rst=0;
  for(i=0;i<512;i=i+1)begin tick;wr_en=1;wr_addr=i;wr_data=codes[i];end
  tick;wr_en=0;
  for(scene=0;scene<4;scene=scene+1)begin
   checking=0;caption_active=0;font_ready=0;image_index=scene;scene_index=scene;
   frame;frame;
   if(!dut.font_cache_idle)$fatal(1,"Native cache did not become idle before font writes");
   case(scene)
    0:$readmemh("sim/gallery_font_1.hex",font_words);
    1:$readmemh("sim/gallery_font_2.hex",font_words);
    2:$readmemh("sim/gallery_font_3.hex",font_words);
    3:$readmemh("sim/gallery_font_4.hex",font_words);
   endcase
   for(i=0;i<1024;i=i+1)begin tick;font_wr_en=1;font_wr_addr=i;font_wr_data=font_words[i];end
   tick;font_wr_en=0;font_ready=1;
   frame;frame;
   if(!dut.ready_d || dut.index_d!==image_index || dut.length_d!==lengths[scene])
    $fatal(1,"Native scene/readiness/length not published atomically scene%0d",scene+1);
   caption_active=1;checking=1;
   for(glyph=0;glyph<lengths[scene];glyph=glyph+1)begin
    for(row=0;row<32;row=row+1)begin
     for(col=0;col<32;col=col+1)begin
      drive(64+col,560+row,1024+glyph*32-64,1,0,0,1);
      if((row*32+col+glyph)%47==0)drive(1900,2000,1024+glyph*32-64,0,0,0,0);
     end
    end
    glyphs=glyphs+1;
   end
   drain;
   for(row=0;row<8;row=row+1)for(col=0;col<6;col=col+1)
    drive(xs[col],ys[row],1024,1,0,xs[col]==1023,0);
   drive(111,222,1024,1,1,0,0);
   drive(1023,599,1024,1,0,1,0);
   drive(4,591,1024,0,1,1,0);
   drain;
   checking=0;caption_active=0;
  end
  if(glyphs!=162 || glyph_pixels!=165888 || boundary_pixels!=200 || ink_pixels<10000 || paper_pixels<10000 || punctuation_pixels<10000 || bubble_cycles<3000 || marker_pixels<32)
   $fatal(1,"Native24 coverage glyphs%0d pixels%0d boundary%0d ink%0d paper%0d punct%0d bubbles%0d markers%0d",glyphs,glyph_pixels,boundary_pixels,ink_pixels,paper_pixels,punctuation_pixels,bubble_cycles,marker_pixels);
  $display("PASS native24 subtitle: %0d scene-local characters/%0d glyph pixels (%0d ink/%0d paper/%0d punctuation), %0d viewport/marker probes, %0d bubbles, %0d exact3-cycle metadata checks; independent row-major floor3over4,/18,mod18 oracle for all four real SUB2 pages",glyphs,glyph_pixels,ink_pixels,paper_pixels,punctuation_pixels,boundary_pixels,bubble_cycles,metadata_cycles);
  $finish;
 end
 initial begin #20000000;$fatal(1,"native24 subtitle timeout");end
endmodule
