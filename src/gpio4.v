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
//  File: gpio.v;   Simple 4 bit bidirectional IO
//
//  Registers are
//    Addr=0    Data In/Out
//    Addr=1    Data direction register.  1==output,  default=0 (input)
//    Addr=2    Update on change register.  If set, input change send auto update
//
// NOTES:
//
/////////////////////////////////////////////////////////////////////////
module gpio4(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,sbio);
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
    inout  [3:0] sbio;       // Simple Bidirectional I/O 
 
    wire   myaddr;           // ==1 if a correct read/write on our address
    reg    [3:0] val;        // Output values
    reg    [3:0] dir;        // The data direction register
    reg    [3:0] mask;       // Auto-update mask. 
    reg    marked;           // ==1 if we need to send an auto-update to the host
    reg    [3:0] meta;       // Used to bring the inputs into our clock domain
    reg    [3:0] meta1;      // Used to bring the inputs into our clock domain and for edge detection

    initial
    begin
        val = 0;
        dir = 0;
        mask = 0;
        marked = 0;
    end

    always @(posedge clk)
    begin
        if (strobe & myaddr & ~rdwr)  // latch data on a write
        begin
            if (addr[1:0] == 0)
                val <= datin[3:0];
            if (addr[1:0] == 1)
                dir <= datin[3:0];
            if (addr[1:0] == 2)
                mask <= datin[3:0];
        end

        if (((meta ^ meta1) & mask & ~dir) != 0)   // do edge detection
            marked <= 1;
        else if (strobe & myaddr & rdwr)  // clear marked register on any read
            marked <= 0;

        // Get the inputs
        meta   <= sbio; 
        meta1  <= meta;

    end

    // Assign the outputs.
    assign sbio[3] = (dir[3]) ? val[3] : 1'bz;
    assign sbio[2] = (dir[2]) ? val[2] : 1'bz;
    assign sbio[1] = (dir[1]) ? val[1] : 1'bz;
    assign sbio[0] = (dir[0]) ? val[0] : 1'bz;

    assign myaddr = (addr[11:8] == our_addr) && (addr[7:2] == 0);
    assign datout = (~myaddr) ? datin : 
                    (~strobe & marked) ? 8'h01 :   // send up one byte if data available
                     (strobe && (addr[1:0] == 0)) ? {4'h0,meta1} :
                     (strobe && (addr[1:0] == 1)) ? {4'h0,dir} :
                     (strobe && (addr[1:0] == 2)) ? {4'h0,mask} :
                     8'h00;

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule

