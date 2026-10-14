# Yosys-Tcl synthesis script for the TM1638 demo (iCE40UP5K / iCESugar V1.5)
# Run from the project root:   yosys -c tcl/top_tm1638_demo.tcl     (or: make syn_tcl)
yosys -import

# 1. Tcl variables
set top_level "top_tm1638_demo"
set src_files [list "tm1638.v" "top_tm1638_demo.v"]

# 2. Read RTL files
foreach file $src_files {
    puts "Parsing source file: $file"
    read_verilog tcl/$file
}

# 3. Synthesize for iCE40 (SB_IO is an iCE40 primitive, known to synth_ice40)
synth_ice40 -top $top_level -noabc9

# 4. Statistics and outputs
stat
write_verilog -noattr "build/${top_level}_netlist.v"
write_json "build/${top_level}_netlist.json"
