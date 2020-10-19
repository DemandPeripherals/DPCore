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
//  File: roten.v;   A rotary encoder input with an LED output
//
//      This peripheral is intended to be part of a user interface.  The
//  rotary encoder counts and push button event are sent to the host on
//  any change.   Rotary encoder events are accumulated in case more
//  than one occurs during a sample interval.
//
//  up to the host on any change.
//
//  Registers (8 bit):
//  0:   MSB is the button state.  Low 7 bits are quadrature count
//  1:   LED state is the LSB.
//
/////////////////////////////////////////////////////////////////////////
module roten(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout, btn, q1, q2, led);
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
    input  btn;              // center push button on the encoder switch
    input  q1;               // input 1 on the encoder
    input  q2;               // input 2 on the encoder
    output led;              // the LED state

    // Addressing and bus interface lines 
    wire   myaddr;           // ==1 if a correct read/write on our address
 
    // Counter state and signals
    reg    [6:0] count;      // signed 7 bit count of quadrature transitions
    wire   q_inc;            // ==1 to increment quadrature counter
    wire   q_dec;            // ==1 to decrement quadrature counter
    reg    data_avail;       // Flag to say data is ready to send
    reg    ledst;            // ==1 to turn on the LED
    reg    q1_1,q1_2;
    reg    q2_1,q2_2;
    reg    btnst;
    reg    at_init;          // at init take inputs as past state --
                             // this prevents bogus counts at start-up

    initial
    begin
        ledst = 0;
        data_avail = 0;
        at_init = 1;
    end

    always @(posedge clk)
    begin
        if (strobe & myaddr & ~rdwr)  // latch data on a write
        begin
            if (addr[0] == 1)
                ledst <= datin[0];
        end
        else if (strobe & myaddr & rdwr & (addr[0] == 0)) // else if a read from the host
        begin
            // Clear data_available if we are sending the count up to the host
            data_avail <= 0;
            count <= 0;
        end
        else
        begin     // no host activity and so do normal processing
            if (at_init)  // at init assume current state is last state
            begin
                q1_1 <= q1;
                q1_2 <= q1;
                q2_1 <= q2;
                q2_2 <= q2;
                btnst <= btn;
                at_init <= 0;
            end
            else
            begin
                // Bring inputs into our clock domain.
                q1_1 <= q1;
                q1_2 <= q1_1;
                q2_1 <= q2;
                q2_2 <= q2_1;

                // increment or decrement the count if needed
                if (q_inc)
                begin
                    count <= count + 7'h01;
                    data_avail <= 1;
                end
                else if (q_dec)
                begin
                    count <= count - 7'h01;
                    data_avail <= 1;
                end

                // send a button change event if needed
                // we try to debounce a little by only sending once per poll
                else if ((data_avail == 0) && (btnst != btn))
                begin
                    btnst <= btn;
                    data_avail <= 1;
                end
            end
        end
    end


    // Detect the edges to count
    assign q_inc = ((q1_2 != q1_1) && (q1_2 ^ q2_2)) ||
                    ((q2_2 != q2_1) && (~(q1_2 ^ q2_2)));
    assign q_dec = ((q1_2 != q1_1) && (~(q1_2 ^ q2_2))) ||
                    ((q2_2 != q2_1) && (q1_2 ^ q2_2));


    // assign bus and I/O lines
    assign led = ledst;

    assign myaddr = (addr[11:8] == our_addr) && (addr[7:1] == 0);
    assign datout = (~myaddr) ? datin : 
                    (~strobe && data_avail) ? 8'h01 :  // Just one byte to send up
                    (strobe && (addr[0] == 0)) ? {~btnst,count} : // button is active low
                    (strobe && (addr[0] == 1)) ? {7'h00,ledst} :
                    8'h00 ;

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule

