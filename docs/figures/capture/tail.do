# common capture helpers (sourced before the project .do)
# The Wave window is placed at x = 1960 (a second monitor here); change the +X+Y in wm geometry if needed.
set PrefWave(font) {{Arial} 11}
set PrefDefaults(font) {{Arial} 10}
proc cap_layout {start end {w 2200} {h 900} {namew 230} {valw 120}} {
    configure wave -signalnamewidth 1 -namecolwidth $namew -valuecolwidth $valw -timelineunits ns
    set win [view -undock wave]
    set top [winfo toplevel $win]
    wm geometry $top ${w}x${h}+1960+60
    update
    wave zoom range $start $end
    update
}
proc cap_ready {} {
    update; after 1500; update
    set f [open cap_ready w]; close $f
}
