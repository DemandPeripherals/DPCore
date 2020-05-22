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
//  File: io8.v;   Eight independent channels of input and output
//
//  Registers: 8 bit, read-write
//      Reg 0:  Bit 0 is the value at pin 1 and is read-only.
//              Bit 1 is set to enable interrupt on change and is read-write
//              Bit 2 is the data out value and is read-write
//      Reg 1:  As above for pin 2
//      Reg 2:  As above for pin 3
//      Reg 3:  As above for pin 4
//      Reg 4:  As above for pin 5
//      Reg 5:  As above for pin 6
//      Reg 6:  As above for pin 7
//      Reg 7:  As above for pin 8
//
//
//  HOW THIS WORKS
//      The io8 card has one 74LVC595 serial-to-parallel chip
//  and a 245/165 buffer and parallel-to-serial shift register.
//  A 7474 dual D flip-flop is used to synchronize the parallel
//  load and bit shifts.  The Verilog below uses 'bst' to count
//  the 8 bits and 'gst' as the state machine controller for the
//  7474 (and hence the loading and shifting).
//      
//  The cabling from the Baseboard to the io8 has ringing on
//  all of the lines at any transition.  To overcome this we
//  use a 7474.  Ringing on the reset or clk line of a 7474 has
//  no effect on the output if the D input is held constant
//  during the ringing.  The data line (pin2) must not change
//  on either rising or falling edge pin4 and the rising edge
//  of pin6.   This is the goal of the gst state machine.
//  
// GST  Pin 6/4/2       State
// OLD:
// * #0       0/0/0     Start state
// * #1       0/0/1     Set up data value for the RCK/LD- strobes
// * #2       1/0/1     Rising edge sets RCK high and LD- low
// * #3       0/0/1     Lower clock line that controls RCK/LD flip-flop
// * #4       0/0/0     Data is latched.  Now start shifting the bits
// * #5       1/0/0     Rising egde of pin6 sets RCK low and LD- high
// *                    (repeat 6-10 for each bit)
// * #6       1/0/d     Setup the data out value for this bit
// *                    (do edge detection for input value during #6)
// * #7       1/0/d     Save input value into RAM
// * #8       1/1/d     Shift clock goes high, shifting in 'd'.
// * #9       1/0/0     Lower clock line to flip-flop controlling shift clocks
// * #10      0/0/0     QB (SCK, CLK) goes low
// *                    (repeat 6-10 for each bit)
//
// NEW:
// #0       0/0/0     Start state -- set up data value low for the RCK/LD- strobes
// #1       1/0/0     Rising egde of pin6 sets RCK/LD- low
// #2       1/0/1     Set up data value hi for the RCK/LD- strobes
// #3       0/0/1     Lower pin6 to setup for rising edge to be clocked
// #4       1/0/1     Rising egde of pin6 sets RCK/LD- hi, Data out is latched.  Now start shifting the bits
// #5       1/0/0     Lower pin2 -- this may be a redundant state
//                    (repeat 6-10 for each bit)
// #6       1/0/d     Setup the data out value for this bit
//                    (do edge detection for input value during #6)
// #7       1/0/d     Save input value into RAM
// #8       1/1/d     Shift clock goes high, shifting in 'd'.
// #9       1/0/0     Lower clock line to flip-flop controlling shift clocks
// #10      0/0/0     QB (SCK, CLK) goes low
//                    (repeat 6-10 for each bit)
//  If we detect a change on a watched pin we set a flag to
//  Indicate that a change is pending.  We wait until we've
//  transferred all 8 bits before looking at changepending
//  and setting another flag to request an autosend of the
//  data.  We stop reading the pins while waiting for an
//  autosend up to the host.
//
/////////////////////////////////////////////////////////////////////////
module io8(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
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
    output pin2;             // Pin2 to the io8 card.  Clock control and data.
    output pin4;             // Pin4 to the io8 card.  Clock control.
    output pin6;             // Pin6 to the io8 card.  Clock control.
    input  pin8;             // Serial data from the io8

    // State variables
    reg    [2:0] bst;        // Bit number for current card access
    reg    [3:0] gst;        // global state for xfer from card
    reg    dataready;        // set=1 to wait for an autosend to host
    reg    changepending;    // set=1 while finishing all 16 bits to then set dataready
    reg    sample;           // used to bring pin8 into our clock domain

    // Addressing and bus interface lines 
    wire   myaddr;           // ==1 if a correct read/write on our address
    wire   [2:0] rout;       // RAM output lines
    wire   [2:0] ramedge;    // Edge transition output info
    wire   [3:0] raddr;      // RAM address lines
    wire   [2:0] rin;        // RAM input lines
    wire   wen;              // RAM write enable
    io8_16x1(rout[2],raddr,rin[2],clk,wen);
    io8_16x1(rout[1],raddr,rin[1],clk,wen);
    io8_16x1(rout[0],raddr,rin[0],clk,wen);


    initial
    begin
        gst = 0;
        bst = 0;
        dataready = 0;
        changepending = 0;
    end

    always @(posedge clk)
    begin

        // reading reg 7 clears the dataready flag
        if (strobe && rdwr && myaddr && (addr[2:0] == 7))
        begin
            dataready <= 0;
        end

        // else if host is not rd/wr our regs and we're not waiting for autosend
        else if ((u10clk == 1) && ~dataready)
        begin
            // was there a change at an input?
            // grab the input on 4, compare to old value on 5, write to RAM on 6
            if (gst == 4)
                sample <= pin8;
            if ((gst == 5) && rout[1] && (sample != rout[0]))
                changepending <= 1;

            if (gst < 8)
                gst <= gst + 1;
            else
            begin
                bst <= bst + 1;  // next bit
                gst <= (bst == 7) ? 0 : 4;
                if (bst == 7)   // Done with all bits?
                begin
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
    assign pin2 = (gst == 2) || (gst == 3) ||                    // LD == 0
                   (((gst == 4) || (gst == 5)) && rout[2]) ||    // data out value
                   (gst == 6) || (gst == 7) || (gst == 8);       // LD == 1
    assign pin4 = (gst == 5);
    assign pin6 = (gst == 1) || (gst == 3) || (gst == 4) || (gst == 5) ||
                  (gst == 6) || (gst == 8);

           // assign RAM signals
    assign wen   = (strobe & myaddr & ~rdwr) ||  // latch data on a write
                   (~dataready && (gst == 6));
    assign raddr = (strobe & myaddr) ? {1'h0,addr[2:0]} : {1'h0,bst[2:0]} ;
    assign rin[2] = (strobe & myaddr & ~rdwr) ? datin[2] : rout[2];
    assign rin[1] = (strobe & myaddr & ~rdwr) ? datin[1] : rout[1];
    assign rin[0] = sample;

    assign myaddr = (addr[11:8] == our_addr) && (addr[7:3] == 0);
    assign datout = (~myaddr) ? datin :
                     (~strobe && myaddr && (dataready)) ? 8'h08 :  // send up 8 bytes when ready
                      (strobe) ? {5'h00,rout} : 
                       0 ; 

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule


module io8_16x1(dout,addr,din,wclk,clken);
    output dout;
    input  [3:0] addr;
    input  din;
    input  wclk;
    input  clken;

    // RAM16X1S_1: 16 x 1 positive edge write, asynchronous read single-port distributed RAM
    //             Spartan-3E
    // Xilinx HDL Libraries Guide, version 12.1

    RAM16X1S #(
    ) RAM16X1S_inst (
       .O(dout),        // 1-bit data output
       .A0(addr[0]),    // Address[0] input bit
       .A1(addr[1]),    // Address[1] input bit
       .A2(addr[2]),    // Address[2] input bit
       .A3(addr[3]),    // Address[3] input bit
       .D(din),         // 1-bit data input
       .WCLK(wclk),     // Write clock input
       .WE(clken)       // Write enable input
    );
endmodule



