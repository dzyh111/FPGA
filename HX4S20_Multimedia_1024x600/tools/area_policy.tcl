# Shared area policy for the current command-line synthesis entry.
# Call AFTER any project/Run commit_param and immediately BEFORE optimize_gate.
proc configure_compact_mapping {} {
 set_param gate add_map_lut_struct high
 set_param gate map_mode area_prior
 set_param gate multi_thread_mapping partition
 puts "COMPACT_AREA_POLICY_APPLIED high area_prior partition"
 report_param -stage gate -all
}
