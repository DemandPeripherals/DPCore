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
//  File: pwmin4.v;   Four channel generic PWM input
//
//  Registers: (16 bit)
//      Reg 0:  Interval 0 duration in clk counts              (16 bits)
//      Reg 2:  Input values at the start of the interval (4 bits)
//      Reg 4:  Interval 1 duration in clk counts              (16 bits)
//      Reg 6:  Input values at the start of the interval (4 bits)
//      Reg 8:  Interval 2 duration in clk counts              (16 bits)
//      Reg 10: Input values at the start of the interval (4 bits)
//      Reg 12: Interval 3 duration in clk counts              (16 bits)
//      Reg 14: Input values at the start of the interval (4 bits)
//      Reg 16: Interval 4 duration in clk counts              (16 bits)
//      Reg 18: Input values at the start of the interval (4 bits)
//      Reg 20: Interval 5 duration in clk counts              (16 bits)
//      Reg 22: Input values at the start of the interval (4 bits)
//      Reg 24: Interval 6 duration in clk counts              (16 bits)
//      Reg 26: Input values at the start of the interval (4 bits)
//      Reg 28: Interval 7 duration in clk counts              (16 bits)
//      Reg 30: Input values at the start of the interval (4 bits)
//      Reg 32: Interval 8 duration in clk counts              (16 bits)
//      Reg 34: Input values at the start of the interval (4 bits)
//      Reg 36: Interval 9 duration in clk counts              (16 bits)
//      Reg 38: Input values at the start of the interval (4 bits)
//      Reg 40: Interval 10 duration in clk counts             (16 bits)
//      Reg 42: Input values at the start of the interval (4 bits)
//      Reg 44: Interval 11 duration in clk counts             (16 bits)
//      Reg 46: Input values at the start of the interval (4 bits)
//      Reg 48: Clk source in the lower 4 bits, then the number of intervals
//              in use, and the start output values in the next 4 bits
//
//  The clock source is selected by the lower 4 bits of register 48:
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
//  HOW THIS WORKS
//      The registers store which inputs changed at the start of an interval
//  and the duration in clock counts of the interval.  At the end of a cycle
//  the values are sent up to the host and a new cycle is started.  A new
//  cycles starts on the first input transition after sending up to the host.
//  This state machine has three states: waiting for first transition, taking
//  measurements, and waiting to sent to host.
//      The transition out of "taking measurements" can occur on either of
//  two events: all inputs have made at least three transitions (so we get
//  both high and low durations), or if there has been no transitions at all
//  while the interval counter counted from 0 to 65535.  We don't want a
//  busy input to fill up the interval registers so we use a counter to
//  count the transitions for each input.  An input is ignored after it has
//  made three transitions.
//
/////////////////////////////////////////////////////////////////////////
module pwmin4(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,
       m100clk,m10clk,m1clk,u100clk,u10clk,u1clk,n100clk,pwm);
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
    input  [3:0] pwm;        // PWM in signals


    // PWM generation lines
    reg    [15:0] main;      // Main PWM comparison clock
    wire   lclk;             // Prescale clock
    reg    lreg;             // Prescale clock divided by two
    reg    [3:0] freq;       // Input frequency selector
    reg    [3:0] old;        // Input values being brought into our clock domain
    reg    [3:0] new;        // Input values being brought into our clock domain
    reg    [3:0] edgcount;   // Count of transitions in the current cycle
    reg    [1:0] state;      // Waiting for first edge, counting edges, waiting for host send
    reg    [1:0] ec0;        // Transition counter
    reg    [1:0] ec1;        // Transition counter
    reg    [1:0] ec2;        // Transition counter
    reg    [1:0] ec3;        // Transition counter

    // Addressing and bus interface lines 
    wire   myaddr;           // ==1 if a correct read/write on our address
    wire   [7:0] doutl;      // RAM output lines
    wire   [7:0] douth;      // RAM output lines
    wire   [3:0] ramedge;    // Edge transition output info
    wire   [3:0] raddr;      // RAM address lines
    wire   ramwen;           // RAM write enable
    ram16x8 timeregramL(doutl,raddr,main[7:0],clk,ramwen); // Register array in RAM
    ram16x8 timeregramH(douth,raddr,main[15:8],clk,ramwen);
    ram16x4 edgeregram(ramedge,raddr,old,clk,ramwen);


    // Generate the clock source for the main counter
    assign lclk = (freq[3:1] == 0) ? 0 :
                  (freq[3:1] == 1) ? n100clk :
                  (freq[3:1] == 2) ? u1clk :
                  (freq[3:1] == 3) ? u10clk :
                  (freq[3:1] == 4) ? u100clk :
                  (freq[3:1] == 5) ? m1clk :
                  (freq[3:1] == 6) ? m10clk : m100clk; 

    initial
    begin
        state = 0;       // Waiting for first transition
        freq = 0 ;       // no clock running to start
        ec0 = 0;
        ec1 = 0;
        ec2 = 0;
        ec3 = 0;
    end


    always @(posedge clk)
    begin
        // Get the half rate clock
        if (lclk)
            lreg <= ~lreg;

        // latch clock selector into flip-flops
        if (strobe && ~rdwr && myaddr && (addr[5:0] == 48))
        begin
            freq    <= datin[3:0];
        end

        // Reset all state information when the host reads the transition count
        if (strobe && myaddr && rdwr && (addr[5:0] == 48))
        begin
            main <= 0;
            state <= 0;
            edgcount <= 0;
            ec0 <= 0;
            ec1 <= 0;
            ec2 <= 0;
            ec3 <= 0;
        end

        // Else do input processing on a clock edge
        else if ((freq == 1) ||
                 ((freq[0] == 0) && (lclk == 1)) ||
                 ((freq[0] == 1) && (lreg == 1) && (lclk == 1)))
        begin
            // bring the inputs into our clock domain
            new <= pwm;
            old <= new;

            // Do state machine processing
            if (state == 0)  // waiting for first transition
            begin
                if ((old ^ new) != 0)
                begin
                    if ((old[0] != new[0]) && (ec0 != 3))
                        ec0 <= ec0 + 1;
                    if ((old[1] != new[1]) && (ec1 != 3))
                        ec1 <= ec1 + 1;
                    if ((old[2] != new[2]) && (ec2 != 3))
                        ec2 <= ec2 + 1;
                    if ((old[3] != new[3]) && (ec3 != 3))
                        ec3 <= ec3 + 1;
                    state <= 1;         // start collecting transition data
                    edgcount <= edgcount + 1;
                end
            end
            else if (state == 1)  // collecting transitions on the inputs
            begin
                main <= main + 1;
                if (main == 16'hffff)
                    state <= 2;

                else if ((old ^ new) != 0)
                begin
                    if ((old[0] != new[0]) && (ec0 != 3))
                        ec0 <= ec0 + 1;
                    if ((old[1] != new[1]) && (ec1 != 3))
                        ec1 <= ec1 + 1;
                    if ((old[2] != new[2]) && (ec2 != 3))
                        ec2 <= ec2 + 1;
                    if ((old[3] != new[3]) && (ec3 != 3))
                        ec3 <= ec3 + 1;
                    // increment to next transition if there are any valid transitions
                    if (((old[0] != new[0]) && (ec0 != 3)) ||
                        ((old[1] != new[1]) && (ec1 != 3)) ||
                        ((old[2] != new[2]) && (ec2 != 3)) ||
                        ((old[3] != new[3]) && (ec3 != 3)))
                    begin
                        edgcount <= edgcount + 1;
                        main <= 0;
                        if (11 == ec0 + ec1 + ec2 + ec3)  // doing 12th measurement?
                            state <= 2;      // Done. Send results to host.
                    end
                end
            end
            // if (state == 2)  // Do nothing.  We are just waiting for a host read
        end
    end


    // Assign the outputs.
    assign mywrite = (strobe && myaddr && ~rdwr); // latch data on a write
    assign ramwen  = ((state != 2) && (((old[0] != new[0]) && (ec0 != 3)) ||
                                       ((old[1] != new[1]) && (ec1 != 3)) ||
                                       ((old[2] != new[2]) && (ec2 != 3)) ||
                                       ((old[3] != new[3]) && (ec3 != 3))));
    assign raddr = (strobe & myaddr) ? addr[5:2] : edgcount ;
    assign myaddr = (addr[15:8] == our_addr) && (addr[6] == 0);
    assign datout = (~myaddr) ? datin :
                    (~strobe && myaddr && (state == 2)) ? 16'h4719 :
                    (strobe && (addr[5:0] == 48)) ? {8'h0,edgcount,freq} :
                    (strobe && (addr[1] == 0)) ? {douth,doutl} : 
                    (strobe && (addr[1] == 1)) ? {12'h000,ramedge} : 
                    0 ; 

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule


module ram16x8(dout,addr,din,wclk,wen);
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
      .INIT_03(16'h0000), // INIT for bit 3 of RAM
      .INIT_04(16'h0000), // INIT for bit 4 of RAM
      .INIT_05(16'h0000), // INIT for bit 5 of RAM
      .INIT_06(16'h0000), // INIT for bit 6 of RAM
      .INIT_07(16'h0000)  // INIT for bit 7 of RAM
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


module ram16x4(dout,addr,din,wclk,wen);
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


