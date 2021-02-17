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
// gpio4_tb.v : Testbench for the GPIO4 peripheral
//
//  Registers are
//    Addr=0    Data In/Out
//    Addr=1    Data direction register.  1==output,  default=0 (input)
//    Addr=2    Update on change register.  If set, input change send auto update
//
//  GPIO4 is a quad general purpose input/output peripheral.  The
//  four FPGA pins can be configured as any cobbination of inputs
//  and outputs.  Input pins can be configured to sent the host an
//  update when the pin changes value.  
//    Since the FPGA pins are bidirectional we use a bidirectional
//  buffer to test the pins.  The value of the driven pins is in 
//  pinval and which pins are driven is set by pinmask.  The wire
//  pins is the bidirectional buffer assigned to the peripheral's
//  FPGA pins
//
//  The test procedure is as follows:
//  - Set bus lines and FPGA pins to default state
//  - Write 0001 to the data register
//  - Write 0011 to the directions register
//  - Verify the pins are zz01 (testing output)
//  - Set pinval to 1000
//  - Set pinmux to 1100
//  - Verify the pins are 1001 (testing input)
//  - Set pinval to 1100
//  - Verify that datout is 8'h01 on a poll (test update-on-change)
//  - Read the data register (clears update pending)
//  - Verify that peripheral does not respond to a poll
//
 
`timescale 1ns/1ns

module gpio4_tb;
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
    wire   [3:0] sbio;       // Simple Bidirectional I/O 
    reg    [3:0] pinval;     // Actual values at the _input_ pins
    reg    [3:0] pinmask;    // Which pins our test drives on the peripheral pins
    wire   [3:0] pins;       // test multiplexer tied to peripheral pins


    // Add the device under test
    gpio4 gpio4_dut(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
          addr_match_in,addr_match_out,datin,datout,sbio);

    // generate the clock(s)
    initial  clk = 0;
    always   #25 clk = ~clk;

    // wire the pin mux
    assign sbio = pins;
    assign pins[0] = (pinmask[0]) ? pinval[0] : 1'bz ;
    assign pins[1] = (pinmask[1]) ? pinval[1] : 1'bz ;
    assign pins[2] = (pinmask[2]) ? pinval[2] : 1'bz ;
    assign pins[3] = (pinmask[3]) ? pinval[3] : 1'bz ;


    // Test the device
    initial
    begin
        $dumpfile ("gpio4_tb.xt2");
        $dumpvars (0, gpio4_tb);

        //  - Set bus lines and FPGA pins to default state
        rdwr = 1; strobe = 0; our_addr = 4'h2; addr = 12'h000;
        busy_in = 0; addr_match_in = 0; datin = 8'h00;
        pinval = 0; pinmask = 0;

        #500  // some time later ...
        //  - Write 0001 to the data register
        rdwr = 0; strobe = 1; our_addr = 4'h2; addr = 12'h200;
        busy_in = 0; addr_match_in = 0; datin = 8'h01;
        #50
        rdwr = 1; strobe = 0; our_addr = 4'h2; addr = 12'h000;
        busy_in = 0; addr_match_in = 0; datin = 8'h00;

        #500  // some time later ...
        //  - Write 0011 to the directions register
        // set direction register to output on the low two pins
        rdwr = 0; strobe = 1; our_addr = 4'h2; addr = 12'h201;
        busy_in = 0; addr_match_in = 0; datin = 8'h03;
        #50
        rdwr = 1; strobe = 0; our_addr = 4'h0; addr = 12'h000;
        busy_in = 0; addr_match_in = 0; datin = 8'h00;

        #500  // some time later ...
        //  - Verify the pins are zz01 (testing output)
        if (sbio === 4'bzz01)
            $display("PASS: gpio4 output test");
        else
            $display("FAIL: gpio4 output test");


        //  - Set pinval to 1000 (testing input)
        //  - Set pinmux to 1100
        pinval = 4'b1000; pinmask = 4'b1100;

        #500  // some time later ...
        //  - Verify the pins are 1001
        if (sbio === 4'b1001)
            $display("PASS: gpio4 input test");
        else
            $display("FAIL: gpio4 input test");


        // Test update on change
        // Enable update-on-change for the upper two bitsi, 1100
        //  - Set pinval to 1100 (test update-on-change)
        rdwr = 0; strobe = 1; our_addr = 4'h2; addr = 12'h202;
        busy_in = 0; addr_match_in = 0; datin = 8'h0c;
        #50
        rdwr = 1; strobe = 0; our_addr = 4'h0; addr = 12'h000;
        busy_in = 0; addr_match_in = 0; datin = 8'h00;
        // change the input pins from 10xx to 11xx
        pinval = 4'b1100;

        #500  // some time later ...
        //  - Verify that datout is 8'h01 on a poll
        rdwr = 0; strobe = 0; our_addr = 4'h2; addr = 12'h200;
        busy_in = 0; addr_match_in = 0; datin = 8'h00;
        #50
        if (datout === 8'b01)
            $display("PASS: gpio4 update pending set test");
        else
            $display("FAIL: gpio4 update pending set test");

        //  - Read the data register (clears update pending)
        rdwr = 1; strobe = 1; our_addr = 4'h2; addr = 12'h200;
        busy_in = 0; addr_match_in = 0; datin = 8'h00;
        #50
        if (datout === 8'h0d)
            $display("PASS: gpio4 read test");
        else
            $display("FAIL: gpio4 read test");

        //  - Verify that peripheral does not respond to a poll
        #500   // some time later ...
        rdwr = 0; strobe = 0; our_addr = 4'h2; addr = 12'h200;
        busy_in = 0; addr_match_in = 0; datin = 8'h00;
        #50
        if (datout === 8'h00)
            $display("PASS: gpio4 update pending cleared test");
        else
            $display("FAIL: gpio4 update pending cleared test");


        #500  // some time later ...
        $finish;
    end
endmodule

