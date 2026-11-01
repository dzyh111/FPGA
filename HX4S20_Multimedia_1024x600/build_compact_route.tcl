# Route the UI/subtitle/border refinement; keep prior release evidence unchanged.
if {[catch {
 source tools/wave_layer_signoff.tcl
 set refine_seed 13
 if {[info exists ::env(COMPACT_PNR_SEED)]} {set refine_seed $::env(COMPACT_PNR_SEED)}
 if {![string is integer -strict $refine_seed] || $refine_seed<1 || $refine_seed>99} {error "Invalid route seed"}
 set refine_prefix compact_seed${refine_seed}
 import_device eagle_s20.db -package EG4S20BG256
 import_db compact_gate.db
 # Reload immediately, before any timer can start on the imported DB.
 clear_sdc -user
 read_sdc user_source/constraints_source/timing.sdc
 legalize_phy_inst
 set_param flow enable_seed on
 set_param place seed $refine_seed
 set_param place effort high
 set_param place fix_hold on
 set_param route effort routability
 set_param route hold_fix_iteration 30
 # Same vendor CongestionHigh + compatible TimingHigh as the prior release.
 set_param place opt_timing high
 set_param place logic_level_opt on
 set_param place aggressive_opt 20
 set_param place aggr_neighbor_dist 5
 set_param place enhanced_beeline_opt 2
 set_param place timing_driven_mode on
 set_param place shifter_opt on
 set_param place crit_path_opt on
 set_param place post_place_opt high
 set_param place split_data_from_clock on
 set_param place ofv 70
 set_param place opt_max_density 50
 set_param place target_density 0.6
 set_param place target_density_pp 0.7
 set_param place enhanced_gp on
 set_param place non_crit_opt on
 set_param place enable_congestion_recovery on
 set_param route post_route_opt high
 place
 export_db ${refine_prefix}_place.db
 # Official routability effort and deferred hold fix, no timing relaxation.
 set_param route fix_hold off
 if {[catch {route} refine_route_error]} {
  set_param route fix_hold on
  update_timing -mode final
  report_timing_status -file ${refine_prefix}_failed_status.txt
  report_timing_path -to [get_regs -hier *] -ep_num 30 -file ${refine_prefix}_failed_paths.txt
  export_db ${refine_prefix}_failed_route.db
  error "route failed: $refine_route_error"
 }
 export_db ${refine_prefix}_raw_routed.db
 update_timing -mode final
 report_timing_status -file ${refine_prefix}_raw_routed_status.txt
 report_timing_summary -file ${refine_prefix}_raw_routed_timing.txt
 puts "COMPACT_DEFERRED_BASE_ROUTE_COMPLETED seed=$refine_seed raw_db=${refine_prefix}_raw_routed.db"
 if {[catch {fix_hold} refine_deferred_hold_error]} {
  set_param route fix_hold on
  update_timing -mode final
  report_timing_status -file ${refine_prefix}_deferred_hold_failed_status.txt
  report_timing_path -to [get_regs -hier *] -ep_num 30 -file ${refine_prefix}_deferred_hold_failed_paths.txt
  export_db ${refine_prefix}_deferred_hold_failed_route.db
  error "deferred hold fix failed: $refine_deferred_hold_error"
 }
 set_param route fix_hold on
 puts "COMPACT_DEFERRED_HOLD_REPAIR_COMPLETED seed=$refine_seed"
 update_timing -mode final
 report_timing_status -file ${refine_prefix}_initial_status.txt
 set refine_fd [open ${refine_prefix}_initial_status.txt r]
 set refine_status [read $refine_fd]
 close $refine_fd
 if {[regexp {HWNS:\s*([-+0-9.]+)ns} $refine_status unused refine_hold] && $refine_hold<0} {
  puts "COMPACT_POST_ROUTE_HOLD_REPAIR initial_hold=$refine_hold"
  fix_hold -clock_opt
  update_timing -mode final
 }
 report_area -io_info -file ${refine_prefix}_phy.area
 report_route_status -drc
 drc_check -route
 report_timing_status -file ${refine_prefix}_timing_status.txt
 report_timing_summary -file ${refine_prefix}_timing.txt
 report_timing_path -to [get_regs -hier *] -ep_num 50 -file ${refine_prefix}_timing_paths.txt
 export_db ${refine_prefix}_pr.db
 set signed_slack [wave_layer_check_final ${refine_prefix}_timing_status.txt ${refine_prefix}_timing.txt]
 set refine_setup [lindex $signed_slack 0]
 set refine_hold [lindex $signed_slack 1]
 write_verilog sim/${refine_prefix}_physical.v -implement
 bitgen -bit HX4S20_Multimedia_1024x600_compact.bit
 puts "COMPACT_ROUTE_COMPLETED seed=$refine_seed setup=$refine_setup hold=$refine_hold"
} refine_error]} {catch {set_param route fix_hold on};puts stderr "COMPACT_ROUTE_FAILED $refine_error";exit 1}
exit


