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
//  File: pgen16.v;   Four bit, 16 state pattern generator
//
//  The pgen16 is a small pattern generator.  The generator goes through
//  16 steps where each step is exactly 256 counts long.  Within a step
//  the outputs are set to that step's value when the count equals that
//  step's trigger count.
//      Note that the total period is always 4096 counts long.
//
//  Registers:
//      Registers 0 to 31 are formed into 16 pairs.  The lower register,
//      0,2,4, ... are the 8 bits of the trigger counter.  The higher
//      numbered registers, 1,3,5,... are the values to latch for the
//      outputs when the trigger count is reached in that step.
//      
//      Reg 32: Clk source in the lower 4 bits
//
//  The clock source is selected by the lower 4 bits of register 32:
//      0:  Off
//      1:  20 MHz
//      2:  10 MHz
//      3:  5 MHz
//      4:  1 MHz
//      5:  500 KHz
//      6:  100 KHz
//      7:  50 KHz
//      8:  10 KHz
//      9   5 KHz
//     10   1 KHz
//     11:  500 Hz
//     12:  100 Hz
//     13:  50 Hz
//     14:  10 Hz
//     15:  5 Hz
//
/////////////////////////////////////////////////////////////////////////
module pgen16(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,
       m100clk,m10clk,m1clk,u100clk,u10clk,u1clk,n100clk,pattern);
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
    input  m100clk;          // 100 Millisecond clock pulse
    input  m10clk;           // 10 Millisecond clock pulse
    input  m1clk;            // Millisecond clock pulse
    input  u100clk;          // 100 microsecond clock pulse
    input  u10clk;           // 10 microsecond clock pulse
    input  u1clk;            // 1 microsecond clock pulse
    input  n100clk;          // 100 nanosecond clock pulse
    output [3:0] pattern;    // out signals


    // Addressing and bus interface lines 
    wire   myaddr;           // ==1 if a correct read/write on our address
    wire   [7:0] doutl;      // RAM output lines
    wire   [4:0] douth;      // RAM output lines
    wire   [3:0] raddr;      // RAM address lines
    wire   timewenl;         // Timer RAM write enable low
    wire   timewenh;         // Timer RAM write enable high
    ram16x8out4 lowtime(doutl,raddr,datin,clk,timewenl);
    ram16x4out4 hitimbits(douth,raddr,datin,clk,timewenh);


    // Pattern generation timer and state
    reg    [7:0] main;       // Main timer comparison clock
    wire   lclk;             // Prescale clock
    reg    lreg;             // Prescale clock divided by two
    reg    [3:0] freq;       // Input frequency selector
    reg    [3:0] state;      // Sequencer that counts 0 to 7
    reg    [3:0] patlatch;   // Latched values of the outputs


    // Generate the clock source for the main counter
    assign lclk = (freq[3:1] == 0) ? 0 :
                  (freq[3:1] == 1) ? n100clk :
                  (freq[3:1] == 2) ? u1clk :
                  (freq[3:1] == 3) ? u10clk :
                  (freq[3:1] == 4) ? u100clk :
                  (freq[3:1] == 5) ? m1clk :
                  (freq[3:1] == 6) ? m10clk :
                  (freq[3:1] == 7) ? m100clk : 0;


    initial
    begin
        state = 0;
        freq = 0;        // no clock running to start
    end


    always @(posedge clk)
    begin
        // Get the half rate clock
        if (lclk)
            lreg <= ~lreg;


        // latch clock selector into flip-flops
        if (strobe && ~rdwr && myaddr && (addr[5] == 1))
        begin
            freq <= datin[3:0];
        end

        if (~(strobe & myaddr & ~rdwr))  // Only when the host is not writing our regs
        begin
            if ((freq == 1) ||
                 ((freq[0] == 0) && (lclk == 1)) ||
                 ((freq[0] == 1) && (lreg == 1) && (lclk == 1)))
            begin
                main <= main + 1;
                if (main == 8'hff)
                begin
                    state <= state + 1;
                end
                if (main == doutl)
                begin
                    patlatch <= douth;  // latch outputs on clock match
                end
            end
        end
    end


    // Assign the outputs.
    assign pattern[0] = patlatch[0];
    assign pattern[1] = patlatch[1];
    assign pattern[2] = patlatch[2];
    assign pattern[3] = patlatch[3];

    assign mywrite = (strobe && myaddr && ~rdwr); // latch data on a write
    assign timewenl  = (mywrite && (addr[5] == 0) && (addr[0] == 0));
    assign timewenh  = (mywrite && (addr[5] == 0) && (addr[0] == 1));
    assign raddr = (strobe & myaddr) ? addr[4:1] : state ;

    assign myaddr = (addr[15:8] == our_addr) && (addr[7:6] == 0);
    assign datout = (~myaddr) ? datin :
                    (strobe && (addr[5] == 1)) ? {4'h0,freq} :
                    (strobe && (addr[0] == 0)) ? doutl : 
                    (strobe && (addr[0] == 1)) ? {4'h0,douth} : 
                    0 ; 

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule


module ram16x8out4(dout,addr,din,wclk,wen);
   output [7:0] dout;
   input  [3:0] addr;
   input  [7:0] din;
   input  wclk;
   input  wen;

   // RAM8X8S: 16 x 8 posedge write distributed (LUT) RAM
   //           Virtex-II/II-Pro
   // Xilinx HDL Language Template, version 10.1

   RAM16X8S #(
      .INIT_00(16'h0000),  // INIT for bit 0 of RAM
      .INIT_01(16'h0000),  // INIT for bit 1 of RAM
      .INIT_02(16'h0000),  // INIT for bit 2 of RAM
      .INIT_03(16'h0000),  // INIT for bit 3 of RAM
      .INIT_04(16'h0000),  // INIT for bit 4 of RAM
      .INIT_05(16'h0000),  // INIT for bit 5 of RAM
      .INIT_06(16'h0000),  // INIT for bit 6 of RAM
      .INIT_07(16'h0000)   // INIT for bit 7 of RAM
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

   // End of RAM8X8S_inst instantiation

endmodule


module ram16x4out4(dout,addr,din,wclk,wen);
   output [3:0] dout;
   input  [3:0] addr;
   input  [3:0] din;
   input  wclk;
   input  wen;

   // RAM16X4S: 16 x 4 posedge write distributed (LUT) RAM
   //           Virtex-II/II-Pro, Spartan-3/3E/3A
   // Xilinx HDL Language Template, version 10.1

   RAM16X4S #(
      .INIT_00(16'h0000), // INIT for bit 0 of RAM
      .INIT_01(16'h0000), // INIT for bit 1 of RAM
      .INIT_02(16'h0000), // INIT for bit 2 of RAM
      .INIT_03(16'h0000)  // INIT for bit 3 of RAM
   ) RAM16X4S_inst (
      .O0(dout[0]),     // RAM data[0] output
      .O1(dout[1]),     // RAM data[1] output
      .O2(dout[2]),     // RAM data[2] output
      .O3(dout[3]),     // RAM data[3] output
      .A0(addr[0]),     // RAM address[0] input
      .A1(addr[1]),     // RAM address[1] input
      .A2(addr[2]),     // RAM address[2] input
      .A3(addr[3]),     // RAM address[3] input
      .D0(din[0]),      // RAM data[0] input
      .D1(din[1]),      // RAM data[1] input
      .D2(din[2]),      // RAM data[2] input
      .D3(din[3]),      // RAM data[3] input
      .WCLK(wclk),      // Write clock input
      .WE(wen)          // Write enable input
   );

  // End of RAM16X4S_inst instantiation

endmodule


