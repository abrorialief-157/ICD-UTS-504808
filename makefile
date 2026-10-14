DIR_BUILD = build
DIR_CONS = constraints
DIR_SRC = tcl
DIR_SIM = sim
DIR_TB = tb
DIR_TCL = tcl

TOP_LEVEL = top_tm1638_demo

# yosys flags. If your yosys crashes with "write_xaiger2 ... aiger.cc" use:
#   make all SYNTH_FLAGS="-noabc9 -noabc"
SYNTH_FLAGS = -noabc9
VERILOGS = $(DIR_SRC)/tm1638.v $(DIR_SRC)/$(TOP_LEVEL).v

# ------ SIMULATION ------
compile:
	if not exist $(DIR_BUILD) mkdir $(DIR_BUILD)
	iverilog \
    -o $(DIR_BUILD)/$(TOP_LEVEL)_sim \
    $(VERILOGS) \
    $(DIR_TB)/$(TOP_LEVEL)_tb.v

vvp:
	vvp $(DIR_BUILD)/$(TOP_LEVEL)_sim

gtk:
	gtkwave $(DIR_BUILD)/$(TOP_LEVEL)_tb.vcd

sim: compile vvp gtk

# ------ SYNTHESIS / PLACE & ROUTE / BITSTREAM ------
# -noabc9 : avoids an internal crash of the Windows yosys build (abc9 / aiger)
syn:
	if not exist $(DIR_BUILD) mkdir $(DIR_BUILD)
	yosys -p "synth_ice40 -top $(TOP_LEVEL) $(SYNTH_FLAGS) -json $(DIR_BUILD)/$(TOP_LEVEL)_netlist.json" $(VERILOGS)

# alternative: same synthesis driven by a Yosys-Tcl script
syn_tcl:
	if not exist $(DIR_BUILD) mkdir $(DIR_BUILD)
	yosys -c $(DIR_TCL)/$(TOP_LEVEL).tcl

pnr:
	nextpnr-ice40 \
		--up5k \
		--package sg48 \
		--json $(DIR_BUILD)/$(TOP_LEVEL)_netlist.json \
		--pcf $(DIR_CONS)/$(TOP_LEVEL).pcf \
		--asc $(DIR_BUILD)/$(TOP_LEVEL).asc

bit:
	icepack $(DIR_BUILD)/$(TOP_LEVEL).asc $(DIR_BUILD)/$(TOP_LEVEL).bin

all: syn pnr bit

# ------ PROGRAMMING (iCESugar uses icesprog / iCELink) ------
flash:
	icesprog $(DIR_BUILD)/$(TOP_LEVEL).bin

# ------ CLEAN ------
clean:
	if exist $(DIR_BUILD) rmdir $(DIR_BUILD) /S /Q

.PHONY: all syn syn_tcl pnr bit flash compile vvp gtk sim clean
