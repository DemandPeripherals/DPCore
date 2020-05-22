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
//  File: enumerator.v;   ROM list of the peripherals in a build.
//  Description:  Each peripheral is assigned an ID number and a
//      version number.  These are listed in this ROM as a way for
//      the Linux daemon to know how to deal with the peripherals
//      in this unique build.
//
/////////////////////////////////////////////////////////////////////////
module enumerator(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout);
    input  clk;              // system clock
    input  rdwr;             // direction of this transfer. Read=1; Write=0
    input  strobe;           // true on full valid command
    input  [3:0] our_addr;   // high byte of our assigned address
    input  [11:0] addr;      // address of target peripheral
    input  busy_in;          // ==1 if a previous peripheral is busy
    output busy_out;         // ==our busy state if our address, pass through otherwise
    input  addr_match_in;    // ==1 if a previous peripheral claims the address
    output addr_match_out;   // ==1 if we claim the above address, pass through otherwise
    input  [7:0] datin ;     // Data INto the peripheral;
    output [7:0] datout ;    // Data OUTput from the peripheral, = datin if not us.
 
    wire   myread;           // ==1 if a correct read on our address
    wire   mywrite;          // ==1 if a correct write to our address
    wire   [10:0] raddr; 
    wire   [7:0] dout;
    reg    imbusy;           // I'm busy.  Needed for extra RAM access clock cycle
    reg    [10:0] addrptr;   // increments to each ROM address in turn


    ram2kx8 enumrom(clk, raddr, dout);


    initial
    begin
        imbusy = 1;   // we want to stretch the read/write strobe by one clock
        addrptr = 0;
    end


    always @(posedge clk)
    begin
        // Say we're not busy on _next_ read clock.  Default is we're busy.
        if (rdwr & strobe & (addr[11:8] == our_addr ))
        begin
            imbusy <= 0;
            if (imbusy == 0)
            begin
                addrptr <= addrptr + 1;
            end
        end

        // Reset address pointer on any write
        else if (~rdwr & strobe & (addr[11:8] == our_addr ))
        begin
            addrptr <= 0;
            imbusy <= 0;
        end

        // Default is that we're busy
        else
            imbusy <= 1;
    end

        // Logic for the output pins
        assign raddr = addrptr;
        assign myread = rdwr & strobe & (addr[11:8] == our_addr );
        assign mywrite = ~rdwr & strobe & (addr[11:8] == our_addr );
        assign datout  = (myread) ? dout[7:0] : datin;
        assign busy_out = (strobe & (addr[11:8] == our_addr )) ? imbusy : busy_in;
        assign addr_match_out = myread | mywrite | addr_match_in;


endmodule
    
    
//
// A wrapper around an instance of a Xilinx RAM block.
module ram2kx8(clk, addr, dout);
    input clk;
    input [10 : 0] addr;
    output [7 : 0] dout;
 
    wire DOP;
    RAMB16_S9 #(
        .INIT(9'h000),  // Value of output RAM registers at startup
        .SRVAL(9'h000), // Output value upon SSR assertion
        .WRITE_MODE("WRITE_FIRST"), // WRITE_FIRST, READ_FIRST or NO_CHANGE
        `include "enumerator.lst"
       ) RAMB16_S9_inst (
          .DO(dout),      // 8-bit Data Output
          .DOP(DOP),      // 1-bit parity Output
          .ADDR(addr),    // 11-bit Address Input
          .CLK(clk),      // Clock
          .DI(8'h00),     // 8-bit Data Input
          .DIP(1'b0),     // 1-bit parity Input
          .EN(1'b1),      // RAM Enable Input
          .SSR(1'b0),     // Synchronous Set/Reset Input
          .WE(1'b0)       // Write Enable Input
       );
 
endmodule

