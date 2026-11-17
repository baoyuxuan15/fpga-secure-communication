# Keep indexed names in Tcl: QSF's line parser treats braces as literal text.
# KEY1..4 are active low. D6=L7 stays the existing armed indicator.
set_location_assignment PIN_M2 -to {key_n[0]}
set_location_assignment PIN_M1 -to {key_n[1]}
set_location_assignment PIN_E15 -to {key_n[2]}
set_location_assignment PIN_E16 -to {key_n[3]}
set_location_assignment PIN_M6 -to alarm_led_n
set_location_assignment PIN_P3 -to muted_led_n
set_location_assignment PIN_N3 -to test_led_n
set_location_assignment PIN_J11 -to beep
set_location_assignment PIN_B1 -to shcp
set_location_assignment PIN_K9 -to stcp
set_location_assignment PIN_R1 -to ds
set_location_assignment PIN_L11 -to oe
foreach port {key_n[0] key_n[1] key_n[2] key_n[3] alarm_led_n muted_led_n test_led_n beep shcp stcp ds oe} {
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to $port
}
