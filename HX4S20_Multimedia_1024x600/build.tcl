# Current compact source flow. Default is synthesis only.
# Run from the formal project root. No command runs merely by opening the project.
# Set BUILD_STAGE=route in a fresh TD process only after a successful new synthesis.
set current_stage synth
if {[info exists ::env(BUILD_STAGE)]} {set current_stage $::env(BUILD_STAGE)}
if {$current_stage ni {synth route}} {puts stderr "BUILD_FAILED: BUILD_STAGE must be synth or route";exit 1}
puts "CURRENT_BUILD compact stage=$current_stage"
if {[catch {source build_compact_${current_stage}.tcl} current_error]} {
 puts stderr "BUILD_FAILED $current_error"
 exit 1
}
