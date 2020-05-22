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
//  File: ping4.v;   Interface to four Parallax PNG))) ultrasonic sensors
//
//  Registers are read-only and 16 bit
//    Addr=0,1    Echo time
//    Addr=2      Interface number
//    Addr=3      Enabled register
//
//
//   State      0   1    2   | 3      4                   5    0
//   IN/OUT   _____|--|____________|------|------------|________
//   Poll     .....|...................................______|____
//
//   The FPGA drives the PNG))) high for 5 us (state 1) and then holds
//   the line low for 500 us (state 2).  It then switches and starts
//   listening for a rising edge (state 3) coming back from the PNG.
//   When it finds the rising edge it counts the microseconds until 
//   the falling edge (state 4).  With a complete sample, we wait for
//   a poll and then send the sample up the host (state 5)
//
//   The above is repeated for each of the four input lines.  Each
//   good reason we start the cycle on a poll from the busif.  Times
//   for state 2 and 3 should be less than 750 us.  If we're still in
//   state 3 after 1024 us we assume that no sensor is connected and
//   go immediately to state 5 with a reading of zero.
//
/////////////////////////////////////////////////////////////////////////
module ping4(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,u1clk,m10clk,png);
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
    input  u1clk;            // Pulse every one microsecond
    input  m10clk;           // Pulse every 10 milliseconds
    inout  [3:0] png;        // Parallax PNG))) inputs
 
    wire   myaddr;           // ==1 if a correct read/write on our address
    reg    [1:0] sensor;     // Which sensor is being measured
    reg    [2:0] state;      // Where in the measurement we are
    reg    [14:0] timer;     // Used for all counting of microseconds
    reg    [1:0] deadtimer;  // Creates a short pause between reading to let echos die down
    reg    meta;             // Brings inputs into our clock domain
    reg    meta1;            // Brings inputs into our clock domain and for edge detection
    reg    [3:0] enabled;    // ==1 if sensor is enabled

    initial
    begin
        state = 0;
        sensor = 0;
        enabled = 0;
        deadtimer = 3;
    end

    always @(posedge clk)
    begin
        // Get the input
        meta  <= (sensor == 0) ? png[0] :
                 (sensor == 1) ? png[1] :
                 (sensor == 2) ? png[2] : png[3];
        meta1 <= meta;


        // Set the enabled bits
        if (strobe & myaddr & ~rdwr)  // latch data on a write
        begin
            if (addr[1:0] == 3)
                enabled <= datin[3:0];
        end


        if (state == 0)  // Waiting to start a measurement, output=0
        begin
            if (((sensor == 0) && (enabled[0] == 0)) ||
                ((sensor == 1) && (enabled[1] == 0)) ||
                ((sensor == 2) && (enabled[2] == 0)) ||
                ((sensor == 3) && (enabled[3] == 0)))
                sensor <= sensor + 1;
            else if (deadtimer == 0)  // start on 30 ms boundary
            begin
                state <= 1;
                timer <= -6;
            end
            else if (m10clk)
                deadtimer <= deadtimer - 1;
        end
        if (state == 1)  // Sending the start pulse to the PNG))), output=1
        begin
            if (u1clk)
            begin
                if (timer == 0)
                begin
                    state <= 2;
                    timer <= -512;
                end
                else
                    timer <= timer + 1;
            end
        end
        if (state == 2)  // Dead time waiting to switch line direction, output=0
        begin
            if (u1clk)
            begin
                if (timer == 0)
                begin
                    state <= 3;
                    timer <= -512;
                end
                else
                    timer <= timer + 1;
            end
        end
        if (state == 3)  // Waiting for a low-to-high transition or a timeout, output=Z
        begin
            if ((meta == 1) && (meta1 == 0)) // Got the low-to-high transition
            begin
                state <= 4;
                timer <= 0;
            end
            else if (u1clk)
            begin
                if (timer == 0)  // timeout == no sensor; send a zero response
                begin
                    state <= 5;
                    timer <= 0;
                end
                else
                    timer <= timer + 1;
            end
        end
        if (state == 4)  // Waiting for the input to go low again
        begin
            if (u1clk)
                timer <= timer + 1;
            if (meta1 == 0)
                state <= 5;
        end
        if (state == 5)  // Got a measurement. Wait for a poll.
        begin
            if (strobe && myaddr)  // Poll.  Go start another reading
            begin
                state <= 0;
                sensor <= sensor + 1;
                deadtimer <= 3;
            end
        end

    end

    // Assign the outputs.
    assign png[0] = ((enabled[0] == 0) || (sensor != 0)) ? 0 :
                    (state == 1) ?   1    :
                    ((state == 0) || (state == 2)) ? 0 : 1'bz ;
    assign png[1] = ((enabled[1] == 0) || (sensor != 1)) ? 0 :
                    (state == 1) ?   1    :
                    ((state == 0) || (state == 2)) ? 0 : 1'bz ;
    assign png[2] = ((enabled[2] == 0) || (sensor != 2)) ? 0 :
                    (state == 1) ?   1    :
                    ((state == 0) || (state == 2)) ? 0 : 1'bz ;
    assign png[3] = ((enabled[3] == 0) || (sensor != 3)) ? 0 :
                    (state == 1) ?   1    :
                    ((state == 0) || (state == 2)) ? 0 : 1'bz ;

    assign myaddr = (addr[11:8] == our_addr) && (addr[7:2] == 0);
    assign datout = (~myaddr) ? datin : 
                    (~strobe & (state == 5)) ? 8'h03 : // send 3 bytes when a sample is ready
                    (strobe && (addr[1:0] == 0)) ? {2'h0,timer[14:8]} :
                    (strobe && (addr[1:0] == 1)) ? timer[7:0] :
                    (strobe && (addr[1:0] == 2)) ? {6'h00,sensor} :
                    (strobe && (addr[1:0] == 3)) ? {4'h0,enabled} :
                    0;

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule

