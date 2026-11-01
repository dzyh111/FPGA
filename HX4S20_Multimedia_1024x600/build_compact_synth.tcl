# UI/subtitle/border refinement. Original device, clocks and SDC.
# Run from the project root with td_commands_prompt.exe.
if {[catch {
 source tools/wave_layer_signoff.tcl
 import_device eagle_s20.db -package EG4S20BG256
 set fd [open sources.f r]
 set files [split [read $fd] "\n"]
 close $fd
 foreach f $files {
  set f [string trim $f]
  if {$f ne ""} {analyze -file $f -include_dir {rtl user_source/hdl_source/include .}}
 }
 elaborate -top top
 read_adc user_source/constraints_source/pin.adc
 read_sdc user_source/constraints_source/timing.sdc
 optimize_rtl
 report_area -file compact_rtl.area
 source tools/area_policy.tcl
 configure_compact_mapping
 optimize_gate
 report_area -file compact_gate.area
 # Synthesized gate databases use basic mode, never routed final mode.
 update_timing -mode basic
 report_timing_status -file compact_gate_timing_status.txt
 report_timing_summary -file compact_gate_timing.txt
 wave_layer_check_clocks [wave_layer_read compact_gate_timing.txt]
 export_db compact_gate.db
 write_verilog sim/compact_gate_audit.v -implement
 puts "COMPACT_SYNTHESIS_COMPLETED_NO_BIT"
} compact_error]} {puts stderr "COMPACT_SYNTHESIS_FAILED $compact_error";exit 1}
exit

