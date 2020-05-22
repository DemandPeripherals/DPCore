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
//  File: quad2.v;   A dual quadrature decoder
//
//      This quadrature decoder accumulates pulses and sends an update
//  to the host that includes both a signed count and a period in usec.
//
//  The pulses are accumulated in RAM based registers.  So as to not
//  miss any pulses during a host read/clear, the design uses two sets
//  sets of registers and toggles between them on each transmission up
//  to the host.  Counts accumulate in one block while data in the other
//  is waiting to be sent to the host.
//
//     A 16 bit microsecond counter runs in parallel to the counting. 
//  The counter is zeroed at the start of each sampling interval.  Each
//  time a counter is incremented, a snapshot is taken of the usec counter.
//  The most recent snapshot is also sent up at each poll.  This usec
//  count gives the host the ability to compute the number of usec it
//  took to accumulate the number of counts.  A count and the number of
//  usec gives a very accurate frequency even at low counts per poll.
//    Counts and period snapshots are kept in slice RAM to conserve
//  space.  Both are 16 bits so the maximum period is 65ms.
//    Note that the input clock is at SYSCLK and we divide this by
//  four so that each input gets access to the slice RAM address
//  and data lines for two of every four clocks.  The first of
//  the two clocks updates the count and the second updates the
//  period.
//
//
//  Registers
//  0,1:   Input a signed count (high,low)
//  2,3:   usec snapshot of last edge capture by counter
//  4,5:   Input a signed count (high,low)
//  6,7:   usec snapshot of last edge capture by counter
//  8  :   Poll interval in units of 10ms.  0-5, where 0=10ms and 5=60ms, 7=off
//
/////////////////////////////////////////////////////////////////////////
module quad2(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,addr_match_in,
              addr_match_out,datin,datout, m10clk, u1clk, a1, a2, b1, b2);
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
    input  m10clk;           // Latch data at 10, 20, or 50 ms
    input  u1clk;            // 1 microsecond clock pulse
    input  a1;               // input 1 on channel a
    input  a2;               // input 2 on channel a
    input  b1;               // input 1 on channel b
    input  b2;               // input 2 on channel b

    // Addressing and bus interface lines 
    wire   myaddr;           // ==1 if a correct read/write on our address
 
    // Count RAM interface lines
    wire   [15:0] rout;      // RAM output lines
    wire   [3:0] raddr;      // RAM address lines
    wire   [15:0] rin;       // RAM input lines
    wire   wen;              // RAM write enable
    ramq216x8count ramH(rout[15:8],raddr,rin[15:8],clk,wen); // Register array in RAM
    ramq216x8count ramL(rout[7:0],raddr,rin[7:0],clk,wen); // Register array in RAM

    // Counter state and signals
    wire   a_inc;            // ==1 to increment A
    wire   a_dec;            // ==1 to decrement A
    wire   b_inc;            // ==1 to increment B
    wire   b_dec;            // ==1 to decrement B
    wire   [15:0] addmux;    // sits in front of an adder and == 1 or ffff
    reg    data_avail;       // Flag to say data is ready to send
    reg    [2:0] pollclk;    // number-1 of poll interval in units of 10ms.  0=10ms
    reg    [2:0] pollcount;  // divides pollclk to get 10, 20, ... 60ms
    reg    [15:0] period;    // 16 bit microsecond counter
    reg    block;            // Which block of registers we are updating
    reg    [1:0] inx;        // Which input we are examining now [1] and count/period [0]
    reg    a1_1,a1_2;
    reg    a2_1,a2_2;
    reg    b1_1,b1_2;
    reg    b2_1,b2_2;

    initial
    begin
        block = 0;
        data_avail = 0;
        period = 0;
        pollclk = 7;         // 0,1,2,3.. for 10ms,20ms,30ms ..60ms,off poll time
        pollcount = 0;
    end

    always @(posedge clk)
    begin
        // Update pollcount, do poll processing
        if (m10clk)
        begin
            if (pollcount == pollclk)
            begin
                pollcount <= 0;
                data_avail <= 1;                // set flag to send data to host
                block <= ~block;                // switch RAM block every poll
                period <= 0;                    // restart period counter
            end
            else
                pollcount <= pollcount +1;
        end
        else if (u1clk)
            period <= period + 1;


        // Handle write requests from the host
        if (strobe & myaddr & ~rdwr & addr[3])  // latch data on a write
        begin
            pollclk <= datin[2:0];
        end


        if (strobe & myaddr & rdwr) // if a read from the host
        begin
            // Clear data_available if we are sending the count up to the host
            data_avail <= 0;
        end
        else
        begin
            // host has priority access to RAM so delay our processing while
            // host is reading RAM.  This won't affect the output since we are
            // delaying processing by one sysclk and the maximum input frequency
            // is one twentieth of sysclk.
            inx <= inx + 1;
            if (inx == 3)  // sample inputs on next sysclk edge
            begin
                // Bring inputs into our clock domain.
                a1_1 <= a1;
                a1_2 <= a1_1;
                a2_1 <= a2;
                a2_2 <= a2_1;
                b1_1 <= b1;
                b1_2 <= b1_1;
                b2_1 <= b2;
                b2_2 <= b2_1;
            end
        end
    end


    // Detect the edges to count
    assign a_inc = ((a1_2 != a1_1) && (a1_2 ^ a2_2)) ||
                    ((a2_2 != a2_1) && (~(a1_2 ^ a2_2)));
    assign a_dec = ((a1_2 != a1_1) && (~(a1_2 ^ a2_2))) ||
                    ((a2_2 != a2_1) && (a1_2 ^ a2_2));
    assign b_inc = ((b1_2 != b1_1) && (b1_2 ^ b2_2)) ||
                    ((b2_2 != b2_1) && (~(b1_2 ^ b2_2)));
    assign b_dec = ((b1_2 != b1_1) && (~(b1_2 ^ b2_2))) ||
                    ((b2_2 != b2_1) && (b1_2 ^ b2_2));


    // addmux is +1 or -1 depending inx, a_inc, and b_inc
    assign addmux = 
                 (((inx == 0) && (a_inc == 1)) || ((inx == 2) && (b_inc == 1))) ? 1 :
                 16'hffff ;

    // RAM address is block and inx, or !block and register address if a host read
    assign raddr = (strobe & myaddr & rdwr & (addr[3] == 0)) ? {1'b0, ~block, addr[2:1]} : 
                                                               {1'b0, block, inx} ;

    // Clear RAM register on/after a read
    assign rin = (strobe & myaddr & rdwr & (addr[7:3] == 0) & (addr[0] == 1)) ? 0 :
                 ((inx == 0) && (a_inc == 1)) ? (rout + addmux) :
                 ((inx == 0) && (a_dec == 1)) ? (rout + addmux) :
                 ((inx == 1) && (a_inc == 1)) ? period :
                 ((inx == 1) && (a_dec == 1)) ? period :
                 ((inx == 2) && (b_inc == 1)) ? (rout + addmux) :
                 ((inx == 2) && (b_dec == 1)) ? (rout + addmux) :
                 ((inx == 3) && (b_inc == 1)) ? period :
                 ((inx == 3) && (b_dec == 1)) ? period :
                 rout ;
    assign wen   = 1 ;

    assign myaddr = (addr[11:8] == our_addr) && (addr[7:4] == 0);
    assign datout = (~myaddr) ? datin : 
                    // send 8 bytes per sample.  Pollclk==7 turns off auto-updates
                    (~strobe && data_avail && (pollclk != 7)) ? 8'h08 :
                    (strobe & (addr[0] == 0)) ? rout[15:8] :
                    (strobe & (addr[0] == 1)) ? rout[7:0] :
                    (strobe & (addr[3] == 1)) ? {5'h0,pollclk} :
                    0 ;

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule


// Distributed RAM to store counters and shadow value.
module ramq216x8count(dout,addr,din,wclk,wen);
   output [7:0] dout;
   input  [3:0] addr;
   input  [7:0] din;
   input  wclk;
   input  wen;

   // RAM16X8S: 16 x 8 posedge write distributed (LUT) RAM
   //           Virtex-II/II-Pro
   // Xilinx HDL Language Template, version 10.1

   RAM16X8S #(
      .INIT_00(16'h0000), // INIT for bit 0 of RAM
      .INIT_01(16'hffff), // INIT for bit 1 of RAM
      .INIT_02(16'h0000), // INIT for bit 2 of RAM
      .INIT_03(16'hffff), // INIT for bit 3 of RAM
      .INIT_04(16'h0000), // INIT for bit 4 of RAM
      .INIT_05(16'hffff), // INIT for bit 5 of RAM
      .INIT_06(16'h0000), // INIT for bit 6 of RAM
      .INIT_07(16'hffff) // INIT for bit 7 of RAM
   ) RAM16X8S_inst (
      .O(dout),           // 8-bit RAM data output
      .A0(addr[0]),       // RAM address[0] input
      .A1(addr[1]),       // RAM address[1] input
      .A2(addr[2]),       // RAM address[2] input
      .A3(addr[3]),       // RAM address[3] input
      .D(din),            // 8-bit RAM data input
      .WCLK(wclk),        // Write clock input
      .WE(wen)            // Write enable input
   );

   // End of RAM16X8S_inst instantiation

endmodule

