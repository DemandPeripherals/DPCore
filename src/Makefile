# *********************************************************
# Copyright (c) 2020 Demand Peripherals, Inc.
# 
# This file is licensed separately for private and commercial
# use.  See LICENSE.txt which should have accompanied this file
# for details.  If LICENSE.txt is not available please contact
# support@demandperipherals.com to receive a copy.
# 
# In general, you may use, modify, redistribute this code, and
# use any associated patent(s) as long as
# 1) the above copyright is included in all redistributions,
# 2) this notice is included in all source redistributions, and
# 3) this code or resulting binary is not sold as part of a
#    commercial product.  See LICENSE.txt for definitions.
# 
# DPI PROVIDES THE SOFTWARE "AS IS," WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING
# WITHOUT LIMITATION ANY WARRANTIES OR CONDITIONS OF TITLE,
# NON-INFRINGEMENT, MERCHANTABILITY, OR FITNESS FOR A PARTICULAR
# PURPOSE.  YOU ARE SOLELY RESPONSIBLE FOR DETERMINING THE
# APPROPRIATENESS OF USING OR REDISTRIBUTING THE SOFTWARE (WHERE
# ALLOWED), AND ASSUME ANY RISKS ASSOCIATED WITH YOUR EXERCISE OF
# PERMISSIONS UNDER THIS AGREEMENT.
# 
# *********************************************************

# Makefile to compile and download a simple Verilog program


DEVICE=xc3s100e-4-vq100
default: DPCore.bin

DPCore.ngc: includes.v main.v bus_ctrl.v slip.v busif.v ft245.v bb4io.v
	echo "run -ifn includes.v -ifmt Verilog -ofn DPCore -p \
	$(DEVICE) -opt_mode Speed -opt_level 2" | xst

buildmain: buildmain.c
	gcc -o buildmain buildmain.c

includes.v: main.v

main.v: buildmain protomain perilist
	cp protomain main.v
	./buildmain perilist >> main.v
	echo "\`include \"sysdefs.h\"" >includes.v
	echo "\`include \"main.v\"" >> includes.v
	echo "\`include \"bus_ctrl.v\"" >> includes.v
	echo "\`include \"ft245.v\"" >> includes.v
	echo "\`include \"slip.v\"" >> includes.v
	echo "\`include \"busif.v\"" >> includes.v
	cat includes.tmp | sort | uniq >>includes.v


DPCore.ngd: DPCore.ngc baseboard4.ucf
	ngdbuild -p $(DEVICE) -uc baseboard4.ucf -aul DPCore.ngc

DPCore.ncd: DPCore.ngd
	map -detail -pr b DPCore.ngd

DPCore.pcf: DPCore.ngd
	map -detail -pr b DPCore.ngd

parout.ncd: DPCore.ncd
	par -pl high -rl high -w DPCore.ncd parout.ncd DPCore.pcf

DPCore.bit: parout.ncd
	bitgen -w  -g CRC:Enable -g StartUpClk:CClk -g Compress \
	parout.ncd DPCore.bit DPCore.pcf

DPCore.bin: DPCore.bit
	promgen -w -p bin -o temp.bin -u 0 DPCore.bit
	cat perilist temp.bin > DPCore.bin

install: DPCore.bin
	stty -opost  < /dev/ttyUSB0
	cat DPCore.bin > /dev/ttyUSB0

clean:
	rm -rf buildmain DPCore.bgn DPCore.bin DPCore.bit DPCore.bld \
		DPCore.drc DPCore.map DPcore_map.xrpt DPCore.mrp DPCore.ncd \
		DPCore.ngc DPCore.ngd DPCore_ngdbuild.xrpt DPCore.ngm \
		DPCore_par.xrpt DPCore.pcf DPCore.prm DPCore_summary.xml \
		DPCore_usage.xml DPcore_par.xrpt includes.v main.v temp.prm \
		temp.bin netlist.lst parout.ncd parout.pad parout_pad.csv \
		parout_pad.txt parout.par parout.ptwx parout.unroutes \
		parout.xpi xlnx_auto_0.ise xlnx_auto_0_xdb/ xst/ includes.tmp\
		smartpreview.twr enumerator.lst DPCore_xst.xrpt temp.cfi \
		_xmsgs/ webtalk.log  DPCore_bitgen.xwbt usage_statistics_webtalk.html


