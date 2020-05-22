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
//  File: count4.v;   A quad event/frequency counter
//
//  Four simple up counters that count the positive, negative, or both
//  edges on the inputs.  Counts are accumulated in one block of registers
//  and the poll clock causes us to switch which block we update.
//  All four counts are sent up to the host on the poll.  
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
//  eight so that each input gets access to the slice RAM address
//  and data lines for two of every eight clocks.  The first of
//  the two clocks updates the count and the second updates the
//  period.
//
//  Registers:
//   0, 1: Input a unsigned count (high,low)
//   2, 3: Input a unsigned usec marker
//   4, 5: Input b unsigned count
//   6, 7: Input b unsigned usec marker
//   8, 9: Input c unsigned count (high,low)
//  10,11: Input c unsigned usec marker
//  12,13: Input d unsigned count
//  14,15: Input d unsigned usec marker
//  16   : Poll interval in units of 10ms.  0-5, where 0=10ms and 5=60ms
//  17   : Edge select for all 4 counters: (rw)
//         Bits 01 are for a, 2-3 for b, 4-5 for c, and 6-7 for d.
//         Bit 1 0
//             0 0  : count no edges (ie counter is off)
//             0 1  : count positive edges.
//             1 0  : count negative edges
//             1 1  : count both edges
//
//
/////////////////////////////////////////////////////////////////////////
module count4(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,addr_match_in,
              addr_match_out,datin,datout, m10clk, u1clk, a, b, c, d);
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
    input  a;                // input A
    input  b;                // input B
    input  c;                // input C
    input  d;                // input D

    // Addressing and bus interface lines 
    wire   myaddr;           // ==1 if a correct read/write on our address
 
    // Count RAM interface lines
    wire   [3:0] raddr;      // Counter/Period RAM address lines
    wire   wen;              // Counter/Period RAM write enable
    wire   [15:0] crout;     // Counter RAM output lines
    wire   [15:0] crin;      // Counter RAM input lines
    ram16x8count cramH(crout[15:8],raddr,crin[15:8],clk,wen); // Register array in RAM
    ram16x8count cramL(crout[7:0],raddr,crin[7:0],clk,wen); // Register array in RAM

    // Counter state and signals
    reg    [2:0] pollclk;    // number-1 of poll interval in units of 10ms.  0=10ms
    reg    [2:0] pollcount;  // divides pollclk to get 10, 20, ... 60ms
    reg    [7:0] mode;       // mode of operation for the counters
    reg    [3:0] inold;      // Bring inputs into our clock domain
    reg    [3:0] innew;      // Bring inputs into our clock domain
    wire   [3:0] cedge;      // ==1 for a counter edge
    reg    data_avail;       // Flag to say data is ready to send. Set when pollclk=pollcount
    reg    block;            // Which block of registers we are updating
    reg    [2:0] inx;        // Which input we are examining now [2:1], count/period [0]
    reg    [15:0] period;    // 16 bit microsecond counter

    initial
    begin
        mode = 8'h00;                // All off to start
        block = 0;
        data_avail = 0;
        period = 0;
        pollclk = 0;         // 0,1,2,3.. for 10ms,20ms,30ms ..60ms,off poll time
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
                data_avail <= 1;            // set flag to send data to host
                block <= ~block;                // switch RAM block every poll
                period <= 0;                    // restart period counter
            end
            else
                pollcount <= pollcount +1;
        end
        else if (u1clk)
            period <= period + 1;


        // Handle write requests from the host
        if (strobe & myaddr & ~rdwr & addr[4])  // latch data on a write
        begin
            if (addr[0] == 0)                   // configuration parameter
                pollclk <= datin[2:0];
            else
                mode <= datin[7:0];
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
            if (inx == 7)  // sample inputs 
            begin
                // Set current to old to get ready for next cycle
                inold[0] <= innew[0];
                inold[1] <= innew[1];
                inold[2] <= innew[2];
                inold[3] <= innew[3];
                innew[0] <= a;
                innew[1] <= b;
                innew[2] <= c;
                innew[3] <= d;
            end
        end
    end


    // Detect the edges to count
    assign cedge[0] = (((inold[0] == 0) && (innew[0] == 1) && mode[0]) ||  // positive edge triggered
                       ((inold[0] == 1) && (innew[0] == 0) && mode[1]));   // negative edge triggered
    assign cedge[1] = (((inold[1] == 0) && (innew[1] == 1) && mode[2]) ||  // positive edge triggered
                       ((inold[1] == 1) && (innew[1] == 0) && mode[3]));   // negative edge triggered
    assign cedge[2] = (((inold[2] == 0) && (innew[2] == 1) && mode[4]) ||  // positive edge triggered
                       ((inold[2] == 1) && (innew[2] == 0) && mode[5]));   // negative edge triggered
    assign cedge[3] = (((inold[3] == 0) && (innew[3] == 1) && mode[6]) ||  // positive edge triggered
                       ((inold[3] == 1) && (innew[3] == 0) && mode[7]));   // negative edge triggered


    // assign RAM signals
    assign wen   = 1 ;
    assign raddr = (strobe & myaddr & rdwr & (addr[7:4] == 0)) ? {~block, addr[3:1]} : 
                                              {block, inx} ;
    // Clear count RAM register on/after a read
    assign crin = (strobe & myaddr & rdwr & (addr[7:4] == 0) & (addr[1:0] == 2'b01)) ? 0 :
                 ((inx == 0) && (cedge[0] == 1)) ? (crout + 1) :
                 ((inx == 1) && (cedge[0] == 1)) ? period :
                 ((inx == 2) && (cedge[1] == 1)) ? (crout + 1) :
                 ((inx == 3) && (cedge[1] == 1)) ? period :
                 ((inx == 4) && (cedge[2] == 1)) ? (crout + 1) :
                 ((inx == 5) && (cedge[2] == 1)) ? period :
                 ((inx == 6) && (cedge[3] == 1)) ? (crout + 1) :
                 ((inx == 7) && (cedge[3] == 1)) ? period :
                 crout ;

    assign myaddr = (addr[11:8] == our_addr) & (addr[7:5] == 0);
    assign datout = (~myaddr) ? datin : 
                    (~strobe & data_avail) ? 8'h10 :  // send up 16 bytes when data is available
                    (strobe & (addr[4]) & (addr[0] == 0)) ? {5'h0,pollclk} :
                    (strobe & (addr[4]) & (addr[0])) ? mode :
                    (strobe & (addr[0] == 0)) ? crout[15:8] :
                    (strobe & (addr[0] == 1)) ? crout[7:0] :
                    0 ;

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule


// Distributed RAM to store counters and shadow value.
module ram16x8count(dout,addr,din,wclk,wen);
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
      .INIT_01(16'h0000), // INIT for bit 1 of RAM
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


