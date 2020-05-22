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
//  File: in4.v;   Simple 4 bit input
//
//  Registers are
//    Addr=0    Data In
//    Addr=1    Update on change register.  If set, input change sends auto update
//
//
/////////////////////////////////////////////////////////////////////////
module in4(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,in);
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
    input  [3:0] in;         // Simple 4 bit input
 
    wire   myaddr;           // ==1 if a correct read/write on our address
    reg    [3:0] mask;       // Auto-update mask. 
    reg    marked;           // ==1 if we need to send an auto-update to the host
    reg    [3:0] meta;       // Used to bring the inputs into our clock domain
    reg    [3:0] meta1;      // Used to bring the inputs into our clock domain and for edge detection

    initial
    begin
        mask = 0;
        marked = 0;
    end

    always @(posedge clk)
    begin
        if (strobe & myaddr & ~rdwr)  // latch data on a write
        begin
            if (addr[0] == 1)
                mask <= datin[3:0];
        end

        if (((meta ^ meta1) & mask) != 0)   // do edge detection
            marked <= 1;
        else if (strobe & myaddr & rdwr)  // clear marked register on any read
            marked <= 0;

        // Get the inputs; swap bit positions
        meta[0] <= in[3]; meta[1] <= in[2]; meta[2] <= in[1]; meta[3] <= in[0]; 
        meta1  <= meta;

    end

    // Assign the outputs.
    assign myaddr = (addr[11:8] == our_addr) && (addr[7:1] == 0);
    assign datout = (~myaddr) ? datin : 
                    (~strobe & marked) ? 8'h01 :  // Send data to host if ready
                     (strobe && (addr[0] == 0)) ? {4'h0,meta1} :
                     (strobe && (addr[0] == 1)) ? {4'h0,mask} :
                     0;

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule

