// *********************************************************
// Copyright (c) 2021 Demand Peripherals, Inc.
//
// This file is licensed separately for private and commercial
// use.  See LICENSE.txt which should have accompanied this file
// for details.  If LICENSE.txt is not available please contact
// support@demandperipherals.com to receive a copy.
//
// In general, you may use, modify, redistribute this code, and
// use any associated patent(s) as long as
// 1) the above copyright is included in all redistributions,
// 2) this notice is included in all source redistributions, and
// 3) this code or resulting binary is not sold as part of a
//    commercial product.  See LICENSE.txt for definitions.
//
// DPI PROVIDES THE SOFTWARE "AS IS," WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING
// WITHOUT LIMITATION ANY WARRANTIES OR CONDITIONS OF TITLE,
// NON-INFRINGEMENT, MERCHANTABILITY, OR FITNESS FOR A PARTICULAR
// PURPOSE.  YOU ARE SOLELY RESPONSIBLE FOR DETERMINING THE
// APPROPRIATENESS OF USING OR REDISTRIBUTING THE SOFTWARE (WHERE
// ALLOWED), AND ASSUME ANY RISKS ASSOCIATED WITH YOUR EXERCISE OF
// PERMISSIONS UNDER THIS AGREEMENT.
//
// This software may be covered by US patent #10,324,889. Rights
// to use these patents is included in the license agreements.
// See LICENSE.txt for more information.
// *********************************************************

/////////////////////////////////////////////////////////////////////////
// ws2812_tb.v : Testbench for the WS2812 peripheral
//
//  Registers are
//    Addr=0    WS2812 data for output 0
//    Addr=1    WS2812 data for output 1
//    Addr=2    WS2812 data for output 2
//    Addr=3    WS2812 data for output 3
//    Addr=4    Config: LSB=invertoutput
//
//  WS2812 is a quad driver for the World Semi WS2812 RGB LED.
//  Each FPGA pin can drive one chain of LEDs.  Driving a single
//  byte takes about nine microseconds.  This is fast enough 
//  that the peripheral can assert BUSY_OUT to request additional
//  bus cycles while it sends the byte.
//  Specifically, a zero bit is high for 350 ns and low for 800
//  and a one bit is high for 700 ns and low for 600.  The first
//  bit is high for an extra clock cycle while the timers are
//  set up.
//
//  The test procedure is as follows:
//  - Test busy_out
//    -- For loop writing 30 bytes to pin1
//       -- Verify that busy_out is asserted on each write
//    -- Verify that the total time was about 30*9 microseconds
//  - Test timing of output pin
//    -- Write one byte (8'hf0) and watch output timing
//
 
`timescale 1ns/1ns

module ws2812_tb;
    // direction is relative to the DUT
    reg    clk;              // system clock
    reg    rdwr;             // direction of this transfer. Read=1; Write=0
    reg    strobe;           // true on full valid command
    reg    [3:0] our_addr;   // high byte of our assigned address
    reg    [11:0] addr;      // address of target peripheral
    reg    busy_in;          // ==1 if a previous peripheral is busy
    wire   busy_out;         // ==our busy state if our address, pass through otherwise
    reg    addr_match_in;    // ==1 if a previous peripheral claims the address
    wire   addr_match_out;   // ==1 if we claim the above address, pass through otherwise
    reg    [7:0] datin ;     // Data INto the peripheral;
    wire   [7:0] datout ;    // Data OUTput from the peripheral, = datin if not us.
    wire   led1;             // The WS2812 din lines
    wire   led2;             //
    wire   led3;             //
    wire   led4;             //
    integer i;               // test loop counter
    integer now;             // start of period measurement
    integer TH0;             // Time high for a zero bit
    integer TL0;             // Time low for a zero bit
    integer TH1;             // Time high for a one bit
    integer TL1;             // Time low for a one bit

    // Add the device under test
    ws2812 ws2812_dut(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,addr_match_in,
              addr_match_out,datin,datout,led1,led2,led3,led4);


    // generate the clock(s)
    initial  clk = 0;
    always   #25 clk = ~clk;


    // Test the device
    initial
    begin
        $dumpfile ("ws2812_tb.xt2");
        $dumpvars (0, ws2812_tb);

        //  - Set bus lines and FPGA pins to default state
        rdwr = 1; strobe = 0; our_addr = 4'h2; addr = 12'h000;
        busy_in = 0; addr_match_in = 0; datin = 8'h00;


        #500  // some time later ...
        // Test busy out 
        for (i = 0; i < 30; i = i+1)
        begin
            //  - Write 0001 to the data register
            rdwr = 0; strobe = 1; our_addr = 4'h2; addr = 12'h200;
            busy_in = 0; addr_match_in = 0; datin = 8'h55;
            #50
            while (busy_out)
            begin
                #50;
            end
        end
        // The time is 1 clock cycle per byte for set up, 23 clock
        // cycles (7+16) for a low bit, and 28 clock cycles for a
        // high bit.  Our test has 30 bytes,  120 one bits, and 120
        // low bits.  The total time should be :
        //    500   - when we started
        // 138000   - low bits (120 * 23 * 50)
        // 156000   - high bits (120 * 26 * 50)
        //   1450   - write cycle ((30 -1) * 50)
        // 295950   - total test time 
        if ($time == 295950)
            $display("PASS: ws2812 busy_out timing");
        else
            $display("FAIL: ws2812 busy_out timing");
        //  - Set bus lines and FPGA pins to default state
        rdwr = 1; strobe = 0; our_addr = 4'h2; addr = 12'h000;
        busy_in = 0; addr_match_in = 0; datin = 8'h00;


        #500  // some time later ...
        //  write 55 to LED1
        rdwr = 0; strobe = 1; our_addr = 4'h2; addr = 12'h200;
        busy_in = 0; addr_match_in = 0; datin = 8'h55;
        #50
        // Start the timer for one bit high time
        now = $time;
        while (led1)        // in high time of a zero bit
            #50;
        TH0 = $time - now;
        now = $time;
        while (~led1)       // in low time of a zero bit
            #50;
        TL0 = $time - now;
        now = $time;
        while (led1)        // in high time of a one bit
            #50;
        TH1 = $time - now;
        now = $time;
        while (~led1)       // in low time of a one bit
            #50;
        TL1 = $time - now;
        if ((TH0 == 350) && (TL0 == 800) && 
            (TH1 == 700) && (TL1 == 600))
            $display("PASS: ws2812 bit timings");
        else
            $display("FAIL: ws2812 bit timings");

        $finish;
    end
endmodule

