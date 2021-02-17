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
// tif_tb.v : Testbench for the the Text Interface peripheral.
//
//  Registers: 8 bit, read-write
//      Reg 0:  Bits 0-4: keypad status.  0x00 if no key pressed
//              Bits 5-6: not used
//              Bit  7:   rotary encoder button status
//      Reg 1:  Bits 0-3: signed number of rotary pulses.
//              Bits 6-7: not used
//      Reg 2:  Bits 0-4: tone duration in units of 10ms
//              Bits 5-6: note frequency (1454Hz, 726, 484, 363)
//              Bit  7:   set for a slightly louder sound
//      Reg 3:  Bits 0-2: LED control
//              Bits 4:   Contrast control (has minimal effect)
//      Reg 4:  Bits 0-5: Character FIFO for the text display
//
//  The test procedure is as follows:
//  - Test fifo full
//    -- For loop writing 15 bytes to reg 4, the character FIFO
//       -- Verify that we recognize our address and the buffer is full
//    -- delay long enough for the characters to drain from the buffer
//    -- For loop writing 16 bytes to reg 4, the character FIFO
//       -- Verify that we do not recognize our address on the last write
//
 
`timescale 1ns/1ns

module tif_tb;
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
    reg    u1clk;            // one microsecond clock pulse   
    reg    m10clk;           // ten millisecond clock pulse   
    wire   pin2;             // Pin2 to the tif card.  Clock control and data.
    wire   pin4;             // Pin4 to the tif card.  Clock control.
    wire   pin6;             // Pin6 to the tif card.  Clock control.
    wire   pin8;             // Serial data from the tif
    integer i;               // test loop counter

    // Add the device under test
    tif tif_dut(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,addr_match_in,
              addr_match_out,datin,datout,u1clk,m10clk,pin2,pin4,pin6,pin8);


    // generate the clock(s)
    initial  clk = 0;
    always   #25 clk = ~clk;
    initial  u1clk = 0;
    always   begin #(19 * 50); u1clk = 1; #50; u1clk = 0; end
    initial  m10clk = 0;
    always   begin #(19 * 50); u1clk = 1; #50; u1clk = 0; end


    // Test the device
    initial
    begin
        $dumpfile ("tif_tb.xt2");
        $dumpvars (0, tif_tb);

        //  - Set bus lines and FPGA pins to default state
        rdwr = 1; strobe = 0; our_addr = 4'h2; addr = 12'h000;
        busy_in = 0; addr_match_in = 0; datin = 8'h00;


        #500  // some time later ...
        // Test busy out 
        for (i = 0; i < 30; i = i+1)
        begin
            //  - Write to the character FIFO register
            // Characters are 9 bits, 8 data bits and an SR bit
            // The peripherals expects two consecutive writes of
            // the first low four bits, then the SR bit and the
            // high four bits.  The MSB of the second bit is set
            // to 1 to indicate it is the second half of the char
            rdwr = 0; strobe = 1; our_addr = 4'h2; addr = 12'h204;
            busy_in = 0; addr_match_in = 0; datin = {4'h0,i[3:0]};
            #50
            // address_match_out is 1 up to i=14
            if ((i == 14) && (addr_match_out == 1))
                $display("PASS: TIF FIFO depth check");
            if ((i == 14) && (addr_match_out == 0))
                $display("FAIL: TIF FIFO depth check");
            if ((i == 15) && (addr_match_out == 0))
                $display("PASS: TIF FIFO buffer full check");
            if ((i == 15) && (addr_match_out == 1))
                $display("FAIL: TIF FIFO buffer full check");
            rdwr = 0; strobe = 1; our_addr = 4'h2; addr = 12'h204;
            busy_in = 0; addr_match_in = 0; datin = {4'h8,i[3:0]};
            #50;
        end
        #200

        $finish;
    end
endmodule


// this module is a simulation equivalent of the
// Xilinx SRL16 LUT based shift register
module SRL16 (
    output  Q,             // SRL data output
    input   A0,            // Select[0] input
    input   A1,            // Select[1] input
    input   A2,            // Select[2] input
    input   A3,            // Select[3] input
    input   CLK,           // Clock input
    input   D);

    parameter INIT = 16'h0000;

    reg    [15:0] data;     // shift register data

    initial
    begin
        data = INIT;
    end

    always @(posedge CLK)
    begin
        {data[15:0]} <= {data[14:0], D};
    end

    assign Q = data[{A3,A2,A1,A0}];

endmodule

