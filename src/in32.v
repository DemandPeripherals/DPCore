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
//  File: in32.v;   Thirty-two channel digital input
//
//  Registers: 8 bit, read-write
//      Reg 0:  Bit 0 is the value at pin 1 and is read-only.
//              Bit 1 is set to enable interrupt on change and is read-write
//      Reg 1:  As above for pin 2
//      Reg 2:  As above for pin 3
//      Reg 3:  As above for pin 4
//      Reg 4:  As above for pin 5
//      Reg 5:  As above for pin 6
//      Reg 6:  As above for pin 7
//      Reg 7:  As above for pin 8
//      Reg 8:  As above for pin 9
//      Reg 9:  As above for pin 10
//      Reg 10: As above for pin 11
//      Reg 11: As above for pin 12
//      Reg 12: As above for pin 13
//      Reg 13: As above for pin 14
//      Reg 14: As above for pin 15
//      Reg 15: As above for pin 16
//      Reg 16: As above for pin 17
//      Reg 17: As above for pin 18
//      Reg 18: As above for pin 19
//      Reg 19: As above for pin 20
//      Reg 20: As above for pin 21
//      Reg 21: As above for pin 22
//      Reg 22: As above for pin 23
//      Reg 23: As above for pin 24
//      Reg 24: As above for pin 25
//      Reg 25: As above for pin 26
//      Reg 26: As above for pin 27
//      Reg 27: As above for pin 28
//      Reg 28: As above for pin 29
//      Reg 29: As above for pin 30
//      Reg 30: As above for pin 31
//      Reg 31: As above for pin 32
//
//
//  HOW THIS WORKS
//      The in32 card has four 74HC165 parallel-to-serial shift
//  registers.  A 7474 dual D flip-flop is used to synchronize
//  the parallel load and the bit shifts.  The Verilog below
//  uses the 'bst' counter to count the 32 bits and the 'gst'
//  counter for the state machine controlling the 7474 (and
//  hence the loading and shifting).
//
//  The state machine for loading and shifting is fairly simple
//  but will be easier to understand if viewed next to the
//  schematic for the in32.
//      
//  The cabling from the Baseboard to the in32 has ringing on
//  all of the lines at any transition.  To overcome this we
//  use a 7474.  Ringing on the reset or clk line of a 7474 has
//  no effect on the output if the D input is held constant
//  during the ringing.  This is the basis for the state machine.
//  
// GST  Pin 6/4/2    State
// #0       0/0/0     Low clock (pin 6) to the SH/LD~ flipflop
// #1       1/0/0     SH/LD~ goes low (pin6 clocked in a zero), latching the 32 input pins
// #2       0/0/1     Set D input to 1 and lo clock to SH/LD~ flipflop
// #3       1/0/1     SH/LD~ goes hi (pin6 clocked in a one) grab the data
// #4       1/1/1     CLK goes hi (pin 4 clocked in a one) shifting data one bit, check for data change
// #5       0/0/1     CLK goes lo (pin 2 clears FF) write data to RAM
//                    (repeat 3, 4 & 5 for each bit)
//
//  If we detect a change on a watched pin we set a flag to
//  Indicate that a change is pending.  We wait until we've
//  transferred all 32 bits before looking at changepending
//  and setting another flag to request an autosend of the
//  data.  We stop reading the pins while waiting for an
//  autosend up to the host.
//
/////////////////////////////////////////////////////////////////////////
module in32(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,
       u10clk, pin2, pin4, pin6, pin8);

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
    input  u10clk;           // 10 microsecond clock pulse
    output pin2;             // Pin2 to the in32 card.  Clock control.
    output pin4;             // Pin4 to the in32 card.  Clock control.
    output pin6;             // Pin6 to the in32 card.  Clock control.
    input  pin8;             // Serial data from the in32

    // State variables
    reg    [4:0] bst;        // Bit number for current card access
    reg    [3:0] gst;        // global state for xfer from card
    reg    dataready;        // set=1 to wait for an autosend to host
    reg    changepending;    // set=1 while finishing all 32 bits to then set dataready
    reg    sample;           // used to bring pin8 into our clock domain

    // Addressing and bus interface lines 
    wire   myaddr;           // ==1 if a correct read/write on our address
    wire   [1:0] rout;       // RAM output lines
    wire   [4:0] raddr;      // RAM address lines
    wire   [1:0] rin;        // RAM input lines
    wire   wen;              // RAM write enable
    ram32x2in32 ram(rout,raddr,rin,clk,wen); // Register array in RAM


    initial
    begin
        gst = 0;
        bst = 0;
        dataready = 0;
        changepending = 0;
    end

    always @(posedge clk)
    begin
        // reading reg 31 clears the dataready flag
        if (strobe && rdwr && myaddr && (addr[4:0] == 31))
        begin
            dataready <= 0;
        end

        // else if host is not rd/wr our regs and we're not waiting for autosend
        else if (~(strobe & myaddr & ~rdwr) && (u10clk == 1) && ~dataready)
        begin
            // was there a change on an input?
            // grab the input on 3, compare to old value on 4, write to RAM on 5
            if (gst == 3)
                sample <= pin8;
            if (rout[1] && (sample != rout[0]) && (gst == 4))
                changepending <= 1;
            if (gst < 5)
                gst <= gst + 1;
            else
            begin
                bst <= bst + 1;  // next bit
                if (bst != 31)   // Done with all bits?
                    gst <= 3;
                else
                begin
                    gst <= 0;
                    if (changepending)
                    begin
                        dataready <= 1;
                        changepending <= 0;
                    end
                end
            end
        end
    end


    // Assign the outputs.
    assign pin2 = ~((gst == 0) || (gst == 1));
    assign pin4 = (gst == 4);
    assign pin6 = ~((gst == 0) || (gst == 2) || (gst == 5));

    // assign RAM signals
    assign wen   = (strobe & myaddr & ~rdwr) ||  // latch data on a write
                   (~dataready && (gst == 5));
    assign raddr = (strobe & myaddr) ? addr[4:0] : bst ;
    assign rin[1] = (strobe & myaddr & ~rdwr) ? datin[1] : rout[1];
    assign rin[0] = sample;

    assign myaddr = (addr[11:8] == our_addr) && (addr[7:5] == 0);
    assign datout = (~myaddr) ? datin :
                     (~strobe && myaddr && (dataready)) ? 8'h20 :  // Send 32 bytes if ready
                      (strobe) ? {6'h00,rout} : 
                       0 ; 

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule



module ram32x2in32(dout,addr,din,wclk,wen);
   output [1:0] dout;
   input  [4:0] addr;
   input  [1:0] din;
   input  wclk;
   input  wen;

   // RAM32X2S: 32 x 2 posedge write distributed (LUT) RAM
   //           Virtex-II/II-Pro, Spartan-3/3E/3A
   // Xilinx HDL Language Template, version 10.1

   RAM32X2S #(
      .INIT_00(32'h00000000), // INIT for bit 0 of RAM
      .INIT_01(32'h00000000)  // INIT for bit 1 of RAM
   ) RAM32X2S_inst (
      .O0(dout[0]),     // RAM data[0] output
      .O1(dout[1]),     // RAM data[1] output
      .A0(addr[0]),     // RAM address[0] input
      .A1(addr[1]),     // RAM address[1] input
      .A2(addr[2]),     // RAM address[2] input
      .A3(addr[3]),     // RAM address[3] input
      .A4(addr[4]),     // RAM address[4] input
      .D0(din[0]),      // RAM data[0] input
      .D1(din[1]),      // RAM data[1] input
      .WCLK(wclk),      // Write clock input
      .WE(wen)          // Write enable input
   );

  // End of RAM32X2S_inst instantiation

endmodule



