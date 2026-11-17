# Asynchronous keys enter only the first stage of the two-flop synchronizers.
set_false_path -from [get_ports {key_n[*]}] -to [get_registers {*key_meta}]
