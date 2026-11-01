create_clock -name clk -period 20 [get_ports {clk}]
derive_clocks
# These hierarchy input nets feed only seven asynchronous SET synchronizers.
# Through-net matching survives physical packing, unlike logical .sr names.
# The synchronous release-chain data paths remain timed. See sim audit.
set_false_path -through [get_nets -hier -nowarn {*u_audio_fifo/rst *reset_audio_video/arst}]
# New audio metadata is stable while the stream is held in reset. Only the
# first mailbox/synchronizer stage is asynchronous; keep second stages timed.
# Anchor logical output-net names: leading/trailing wildcards also match TD's
# generated audio_sample_total aliases, incorrectly constraining its SD-side CE.
set_max_delay 8 -datapath_only -to [get_regs -hier -nowarn {sample_total_s0[*] scene_s0[*] scene_map_s0[*] sd_card_bmp_m0/audio_loop_sync[0]}]
# Board asynchronous controls are synchronised explicitly in RTL.
set_false_path -from [get_ports {rst_n key1 key2 key3 switches[*]}]
# Constrain only the first synchroniser stage; the second stage stays timed.
# Datapath-only bounds also limit skew of Gray-pointer bits and mailbox payloads.
set_max_delay 8 -datapath_only -to [get_regs -hier -nowarn {*sync_r1* *primary_addr_gray_sync*}]
set_max_delay 8 -datapath_only -to [get_regs -hier -nowarn {*u_scan/commit_sync[0]* *u_scan/ack_sync[0]* *u_scan/blank_sync[0]*}]
# The image index is held across the entire frame-boundary handoff. Give its
# first synchronizer stage a separate, still conservative 9 ns route bound;
# the 8 ns event-toggle bound accidentally constrained an aliased 40 MHz path.
# Exact two first-stage synchronizers only. A contains-wildcard also matches
# the upstream SD-domain disp_buf_idx aliases (4 targets instead of 2).
set_max_delay 9 -datapath_only -to [get_regs -hier -nowarn {u_scan/index_s0[*]}]
# Fifth external-frame select accompanies the same stable commit mailbox.
set_max_delay 8 -datapath_only -to [get_regs -hier -nowarn {u_scan/cover_s0 cover_read_m0 cover_write_m0}]
# Percentage zoom uses a registered Gray-code control crossing into video.
# Its frame-latched binary payload then settles through the existing 8-pixel
# read-request delay before the SDRAM-side mailbox captures it. Only first
# stages get a datapath bound; second stages and all image paths stay timed.
set_max_delay 8 -datapath_only -to [get_regs -hier -nowarn {zoom_sync0[*] frame_read_write_m0/frame_fifo_read_m0/zoom_d0[*]}]
set_max_delay 8 -datapath_only -to [get_regs -hier -nowarn {*commit_ack_sync[0]* *write_ack_sync[0]* *wrfin_tgl_sync[0]*}]
set_max_delay 8 -datapath_only -to [get_regs -hier -nowarn {*blank_ack_sync[0]* *state_seg_sync0*}]
# Exactly six reader/writer first-stage mailbox bits. Contains-wildcards
# also select source-side bank selectors and read_req through packed aliases.
set_max_delay 8 -datapath_only -to [get_regs -hier -nowarn {frame_read_write_m0/frame_fifo_read_m0/read_req_d0 frame_read_write_m0/frame_fifo_read_m0/read_addr_index_d0[*] frame_read_write_m0/frame_fifo_write_m0/write_req_d0 frame_read_write_m0/frame_fifo_write_m0/write_addr_index_d0[*]}]
# Slide payload is held for the full frame. video_scan waits eight pixel clocks
# before requesting a read; only the first of the two synchroniser stages is bounded here.
# Exact first-stage output nets only. These legacy payload chains are unused
# by the current single-bank reader and optimize away; a contains-wildcard
# instead matches the video-side read_next_index alias and its synchronous CE.
set_max_delay 8 -datapath_only -to [get_regs -hier -nowarn {frame_read_write_m0/frame_fifo_read_m0/next_index_d0[*] frame_read_write_m0/frame_fifo_read_m0/slide_d0[*]}]
set_max_delay 8 -datapath_only -to [get_regs -hier -nowarn {*u_osd/sw0* *u_osd/menu0* *u_osd/item0* *u_osd/bri0* *u_osd/con0* *u_osd/scale0* *u_osd/spec0* *u_osd/sub0* *u_osd/state0* *u_osd/img0* *u_osd/auto0*}]
# Rebuild status is display-only and changes at human-scale intervals.  It is
# sampled by explicit two-stage synchronizers; exclude only their first stage
# from related-PLL phase timing while leaving the second stage fully timed.
set_false_path -to [get_regs -hier -nowarn {*u_osd/rebuild0* *u_osd/progress0* *u_osd/total0*}]
# Anchor the first-stage subtitle mailbox outputs. Contains-wildcards also
# match upstream SD length-CE and frame-reader index aliases after packing.
# Keep the same 8 ns first-stage bound; second stages and SD logic stay timed.
set_max_delay 8 -datapath_only -to [get_regs -hier -nowarn {u_subtitles/index0[*] u_subtitles/lengths0[*] u_subtitles/en0 u_subtitles/pic0}]
# Gallery mailboxes are held across the complete commit/intro acknowledgement.
# Only first stages cross clocks; all second stages and video paths stay timed.
set_max_delay 8 -datapath_only -to [get_regs -hier -nowarn {font_scene0[*] font_index0[*] font_valid0 pack0 menu_video0 restart_video0 u_scan/manual_s0 sd_card_bmp_m0/intro_done_sync[0] sd_card_bmp_m0/intro_restart_sync[0] sd_card_bmp_m0/intro_index0[*]}]
set_max_delay 8 -datapath_only -to [get_regs -hier -nowarn {sd_card_bmp_m0/bmp_read_m0/font_idle_sync[0] sd_card_bmp_m0/bmp_read_m0/font_quiet_sync[0] u_subtitles/quiet0}]

# The vendor dual-clock FIFOs intentionally assert and release their internal
# clear asynchronously.  Recovery/removal between unrelated FIFO clocks does
# not describe a functional data path; FIFO pointer synchronizers protect the
# first transfer after clear.  Restrict the exception to asynchronous reset
# pins so ordinary inter-clock data paths remain checked.
set_false_path -through [get_nets -hier -nowarn {*frame_fifo_read_m0/fifo_aclr *frame_fifo_write_m0/fifo_aclr}]
