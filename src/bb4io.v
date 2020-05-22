// *********************************************************
// Copyright (c) 2020 Demand Peripherals, Inc.
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

//////////////////////////////////////////////////////////////////////////
//
//  File: bb4io.v;   Peripheral access to the Baseboard4 LEDs and buttons.
//
//  Reg 0: Buttons.  Read-only, 8 bit.  Auto-send on change. Sends both
//         the LED value and the button values.
//  Reg 1: LEDs.  Read/write, 8 bit
//
/////////////////////////////////////////////////////////////////////////
module bb4io(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,leds, bntn1, bntn2, bntn3);
    input  clk;              // system clock
    input  rdwr;             // direction of this transfer. Read=1; Write=0
    input  strobe;           // true on full valid command
    input  [3:0] our_addr;   // high byte of our assigned address
    input  [11:0] addr;      // address of target peripheral
    input  busy_in;          // ==1 if a previous peripheral is busy
    output busy_out;         // ==our busy state if our address, pass through otherwise
    input  addr_match_in;    // ==1 if a previous peripheral claims the address
    output addr_match_out;   // ==1 if we claim the above address, pass through otherwise
    input  [7:0] datin;      // Data INto the peripheral;
    output [7:0] datout;     // Data OUTput from the peripheral, = datin if not us.
    output [7:0] leds;       // The LEDs on the Baseboard4
    input  bntn1;            //  Button #1
    input  bntn2;            //  Button #2
    input  bntn3;            //  Button #3
 
    wire   myaddr;           // ==1 if a correct read/write on our address
    reg    [2:0] btn0;       // bring buttons into our clock domain
    reg    [2:0] btn1;       // bring buttons into our clock domain
    reg    [7:0] ledlatch;   // Latched value of the LEDs
    reg    data_ready;       // ==1 if we have new data to send up to the host


    initial
    begin
        btn0 = 3'b000;
        btn1 = 3'b000;
        ledlatch = 8'hff;  // Matches the power-on state of the LEDs
        data_ready = 0;
    end

    // Bring the Buttons into our clock domain.
    always @(posedge clk)
    begin
        btn0[0] <= bntn1;
        btn0[1] <= bntn2;
        btn0[2] <= bntn3;
        btn1 <= btn0;

        if (strobe & myaddr & ~rdwr & (addr[0] == 1))  // latch data on a write
        begin
            ledlatch <= datin[7:0];
        end
        // clear data_ready register on a read
        if (strobe & myaddr & rdwr & (addr[0] == 0))
        begin
            data_ready <= 0;
        end
        else if (btn1 != btn0)   // edge detection for sending data up to the host
        begin
            data_ready <= 1;
        end
    end
 
    assign myaddr = (addr[11:8] == our_addr) && (addr[7:1] == 0);

    // data out is the button if a read on us, our data ready send command 
    // if a poll from the bus interface, and data_in in all other cases.
    assign datout = (~myaddr) ? datin : 
                    (~strobe & data_ready) ? 8'h01 :
                    (strobe && (addr[0] == 1)) ? ledlatch : 
                    (strobe && (addr[0] == 0)) ? btn1 :
                    datin ;

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;
    assign leds = ledlatch;


endmodule

