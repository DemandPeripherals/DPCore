# *********************************************************
# Copyright (c) 2021 Demand Peripherals, Inc.
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

# Makefile to run Verilog tests for some of the peripherals


default: all

all: gpio4_tb.xt2 ws2812_tb.xt2 tif_tb.xt2

gpio4_tb.xt2: gpio4_tb.v ../gpio4.v
	iverilog -o gpio4_tb.vvp  gpio4_tb.v ../gpio4.v
	vvp gpio4_tb.vvp -lxt2

ws2812_tb.xt2: ws2812_tb.v ../ws2812.v
	iverilog -o ws2812_tb.vvp  ws2812_tb.v ../ws2812.v
	vvp ws2812_tb.vvp -lxt2

tif_tb.xt2: tif_tb.v ../tif.v
	iverilog -o tif_tb.vvp  tif_tb.v ../tif.v
	vvp tif_tb.vvp -lxt2

clean:
	rm -rf *.vvp *.xt2


