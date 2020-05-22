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
//  File: rfob.v;   Keyfob (315 MHz) receiver
//
//  Registers: (8 bit)
//      Reg 00: Data bit 0
//      ::: ::
//      Reg 31: Data bit 31
//      Reg 32: Number of valid bits in packet
//      Reg 33: Number of 10us samples in a bit time.  Determines BPS.
//
//      The keyfob receiver card has a 315 MHz receiver and a circuit
//  to convert the levels at the receiver to 3.3 volts.
//  Pin 1 is the Rx data line from the receiver.
//  Pin 3 is RSSI from the receiver (but is unused)
//  Pin 5 is an LED that indicates the start of a packet
//  Pin 7 is an LED that toggles on completion of a valid packet
//
//  
//  HOW THIS WORKS
//      Keyfob transmitters encode the bits in a frame using PWM.  The
//  actual pulse widths depend on the data rate.  Higher data rates have
//  shorter pulses than those of lower data rates.  A 1700 bps transmitter
//  has a bit width of 600 us with a zero bit width of 150 us and one
//  width of 450 us.  A 560 bsp transmitter has bit widths for zero and one
//  as 400 us and 1.2 ms, with a bit width of 1.8 ms.  Register 33 tells
//  us how many samples to sum before deciding if the sample represent a
//  one or a zero.
//      A "frame" is a complete sequence of data pulses with a leading
//  sync interval.  The sync interval is always at least 10 milliseconds
//  long.  The first edge after the sync interval is the start of bit #0.
//  There can be a variable number of bits in a packet depending on the
//  type of keyfob transmitter used.  The end of a packet is defined as
//  the first interval without an edge, positive or negative, for one
//  bit time.  We check for a valid packet by comparing the number of
//  bits received to the number we expect.
//      We send the data up to the host at the end of a packet.  We send
//  just the bits we have received.
//
/////////////////////////////////////////////////////////////////////////
module rfob(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,
       u10clk, m1clk, rfdin, rssi, pwml, pwmh);
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
    input  m1clk;            // 1 millisecond clock pulse
    input  rfdin;            // RF data bit
    input  rssi;             // RSSI (but is analog and so of little use)
    output pwml;             // Lower PWM line for LED
    output pwmh;             // Higher PWM line for LED

    // RF pulse width registers and RSSI lines
    reg    [7:0] smplcnt;    // A bit has this many 10 us samples
    reg    [7:0] scount;     // sample counter.  Goes zero to smplcnt
    reg    [7:0] smplsum;    // number of samples with RF data in a 1
    reg    dflt;             // data line but in our clock domain
    reg    [4:0] pktbits;    // expected number of bits.  Set by host.
    reg    [4:0] bitcnt;     // number of bits in pkt so far
    reg    [3:0] main;       // main timer for pulse widths and pre/postamble
    reg    [2:0] state;      // ==0 if waiting for pkt start
                             // ==1 if in pkt, waiting for first bit
                             // ==2 if in bit and summing the num of high input samples
                             // ==3 if in low time waiting for next but or in postamble
                             // ==4 if pkt complete, wait to send to host
    reg    databit;          // latched value of sampled bit
    reg    pktflag;          // toggled on each valid packet

    // Addressing, bus interface, and spare I/O lines and registers
    wire   myaddr;           // ==1 if a correct read/write on our address

    // Registers for Rx data
    wire   rxout;            // Rx RAM output line
    wire   [4:0] rxaddr;     // Rx RAM address lines
    wire   rxin;             // Rx RAM input lines
    wire   rxwen;            // Rx RAM write enable
    rfram32x1 rfrx(rxout,rxaddr,rxin,clk,wen);


    initial
    begin
        bitcnt = 0;
        smplcnt = 8'd165;    // 560 Hz has a bit time of 180 samples.  Stop early.
        state = 0;           // waiting for pkt start
        pktbits = 5'd24;     // most xmitters have 24 bits of data
        main = 0;
        pktflag = 0;
    end

    always @(posedge clk)
    begin
        // Handle reads and writes from the host
        if (strobe && myaddr && (addr[4] == 1) && rdwr)
            state <= 0;                // Clear data ready on a read
        else if (strobe && myaddr && (addr[5] == 1) && ~rdwr)  // write to config?
        begin
            if (addr[0] == 0)
                pktbits <= datin[4:0];    // Number of bits in a packet
            else
                smplcnt <= datin[7:0];    // Number of 10us samples in a bit
        end

        // Look for preamble on edges of m1clk
        else if ((state == 0) & m1clk)
        begin
            main <= main + 1;
            if (main == 11)
            begin
                state <= 1;
                main <= 0;
            end
        end
        else if (u10clk)
        begin
            // Sample the input
            dflt <= rfdin;

            // run the state machine
            if (state == 0)    // reset preamble counter on non-zero input
            begin
                // A valid preamble is low for greater than about 10 ms
                if (dflt == 1)
                begin
                    main <= 0;
                end
            end
            else if (state == 1)
            begin
                // in preamble, waiting for first bit.  Wait forever.
                if (dflt == 1)
                begin
                    state <= 2;
                    main <= 0;
                    scount <= smplcnt;
                    smplsum <= 0;
                    bitcnt <= 0;
                end
            end
            else if (state == 2)
            begin
                // in bit.  Sum the number of times the input is high
                smplsum <= smplsum + dflt;

                // decrement the sample counter and see if we're at bit end
                scount <= scount - 1;
                if (scount == 0)
                begin
                    // Done sampling the bit.
                    // The bit is a one if more than half of the samples were a 1.
                    // The ram input will reflect the bit value.
                    // We now start waiting for the next bit (or postamble timeout)
                    state <= 3;   // go to zero-bit low time
                    databit <= (smplsum > (smplcnt[7:1])) ? 1 : 0 ;
                end
            end
            else if (state == 3)
            begin
                // We are done sampling the bit and should be in the 'low' part
                // of the bit.  Wait for the next high input to start the next
                // bit but run a timer (using scount) to see if we are at the
                // end of the packet.
                if (dflt == 1)
                begin
                    // Saw a high edge, Go to in-bit
                    bitcnt <= bitcnt + 1;
                    scount <= smplcnt;
                    smplsum <= 0;
                    state <= 2;
                end
                else
                begin
                    // we are still waiting for the high edge of the next bit.
                    scount <= scount - 1;
                    if (scount == 0)    // 255 counts to reach zero.  No more bits
                    begin
                        if (bitcnt == pktbits)
                        begin
                            state <= 4;
                            pktflag <= ~pktflag;
                        end
                        else            // a bogus packet if not expected length
                        begin
                            state <= 0; // go wait for next preamble
                            main <= 0;
                        end
                    end
                end
            end
            else if (state == 4)
            begin
                    // wait here for a host read then go to wait-for-preamble state
            end
        end
    end

    // Route the RAM and output lines
    assign rxaddr = (strobe & myaddr) ? addr[4:0] : bitcnt ;
    assign wen  = (state == 3) && ((dflt == 1) || (scount == 0));
    // an input bit is 'one' if more than half the samples are one.
    assign rxin = databit;

    // Assign the outputs.
    assign myaddr = (addr[11:8] == our_addr) && (addr[7:6] == 0);
    assign datout = (~myaddr) ? datin :
                    (~strobe && (state == 4)) ? 8'h18 :  // 24 bytes to send
                    (strobe) ? {7'h0,rxout} : 
                    0 ; 

    assign raddr = (strobe & myaddr) ? addr[4:1] : 4'h0000 ;

    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

    assign pwml = (state != 0) ? 1 : 0;
    assign pwmh = pktflag;

endmodule

module rfram32x1(dout,addr,din,wclk,wen);
   output dout;
   input  [4:0] addr;
   input  din;
   input  wclk;
   input  wen;

    // RAM32X1S: 32 x 1 posedge write distributed (LUT) RAM
    //           All FPGA
    // Xilinx HDL Libraries Guide, version 10.1.2

    RAM32X1S #(
        .INIT(32'h0000)  // Initial contents of RAM
    ) RAM32X1S_inst (
    .O(dout),      // RAM output
    .A0(addr[0]),  // RAM address[0] input
    .A1(addr[1]),  // RAM address[1] input
    .A2(addr[2]),  // RAM address[2] input
    .A3(addr[3]),  // RAM address[3] input
    .A4(addr[4]),  // RAM address[4] input
    .D(din),       // RAM data input
    .WCLK(wclk),   // Write clock input
    .WE(wen)       // Write enable input
    );

    // End of RAM32X1S_inst instantiation
endmodule


