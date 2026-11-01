# Read-only report assertions. No SDC or clock changes are made here.
proc wave_layer_read {path} {
 set fd [open $path r]
 set text [read $fd]
 close $fd
 return $text
}
proc wave_layer_check_clocks {text} {
 array set clocks {}
 foreach line [split $text "\n"] {
  if {[regexp {^\s*clk[0-9]+:\s+([0-9.]+)\s+[0-9]+\s+(\S+)\s*$} $line unused frequency name]} {
   if {[info exists clocks($name)]} {error "Duplicate clock $name"}
   set clocks($name) $frequency
  }
 }
 set expected {
  {clk 50.000}
  {sys_pll_m0/pll_inst.clkc[0] 40.000}
  {sys_pll_m0/pll_inst.clkc[1] 40.000}
  {sys_pll_m0/pll_inst.clkc[2] 40.000}
  {video_pll_m0/pll_inst.clkc[0] 51.201}
  {video_pll_m0/pll_inst.clkc[1] 256.016}
 }
 if {[array size clocks]!=6} {error "Expected exactly 6 clocks, found [array size clocks]"}
 foreach specification $expected {
  set name [lindex $specification 0]
  set frequency [lindex $specification 1]
  if {![info exists clocks($name)] || abs($clocks($name)-$frequency)>0.002} {
   error "Missing/changed original clock $name (expected $frequency MHz)"
  }
 }
 puts "WAVE_LAYER_CLOCKS_PASS original_six_frequencies"
}
proc wave_layer_check_final {status_file summary_file} {
 set status [wave_layer_read $status_file]
 set summary [wave_layer_read $summary_file]
 foreach token {SWNS STNS HWNS HTNS} {
  set pattern [format {%s:\s*([-+]?[0-9]+(?:\.[0-9]+)?)ns} $token]
  if {![regexp $pattern $status unused raw]} {error "Missing $token in final status"}
  if {[string match -* $raw] || $raw<0} {error "Negative $token $raw ns"}
  if {($token eq "STNS" || $token eq "HTNS") && $raw!=0} {error "Nonzero $token"}
  if {![regexp $pattern $summary unused summary_raw] ||
      [string match -* $summary_raw] || $summary_raw!=$raw} {
   error "Summary/status mismatch for $token"
  }
  set result($token) $raw
 }
 if {![regexp {STA coverage\s*:\s*([0-9.]+)%} $summary unused coverage] || $coverage<99.99} {
  error "Missing/insufficient routed STA coverage"
 }
 foreach pattern {{Confidence\s*:\s*Routed} {Check Corner\s*:\s*Both} {Slow\s*\|\s*yes\s+yes} {Fast\s*\|\s*yes\s+yes}} {
  if {![regexp $pattern $summary]} {error "Missing final routed two-corner check: $pattern"}
 }
 wave_layer_check_clocks $summary
 puts "WAVE_LAYER_FINAL_STA_PASS setup=$result(SWNS) hold=$result(HWNS) stns=$result(STNS) htns=$result(HTNS) coverage=$coverage"
 return [list $result(SWNS) $result(HWNS)]
}

