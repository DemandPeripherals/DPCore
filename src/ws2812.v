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
//  File: ws2812.v;  Quad control of ws2812 LEDs 
//
//  Accept up to 256 bytes from the host and shift each bit out
//  using the timing defined for the World Semi ws2812 RGB(W) LED.
//  A zero bit is high for 350 ns and low for 800.  A one bit is
//  high for 700 ns and low for 600.
//
//  The hardware has a 7474 and a two input data selector.  Pin
//  0 is the D input and pin 1 is the clock line.  This lets the
//  circuit tolerate ringing.  The high two pins go to the mux
//  A and B inputs.  The Q output goes to the chip select of the
//  mux.  This makes the four mux outputs the four ws2812 drive
//  lines.
//
//  Because of the large amount of data and the fairly high
//  output frequency the circuit uses the busy line to apply
//  back pressure to the bus interface.  A 265 byte packet
//  takes about 2.5 ms.  This can limit the USB bandwidth.
//
//  Use the 'no-increment' write command so send multiple bytes
//  of data to the same register.
//
//  Registers are
//    Addr=0    WS2812 data for output 0
//    Addr=1    WS2812 data for output 1
//    Addr=2    WS2812 data for output 2
//    Addr=3    WS2812 data for output 3
//
// NOTES:
//
/////////////////////////////////////////////////////////////////////////
module ws2812(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,addr_match_in,
              addr_match_out,datin,datout,dline,clkline,muxa,muxb);
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
    output dline;            // D input to the 7474
    output clkline;          // Clock line to the 7474
    output muxa;             // 2-to-4 mux input A
    output muxb;             // 2-to-4 mux input B
 
    wire   myaddr;           // ==1 if a correct read/write on our address
    reg    [7:0] wsdata;     // ws2813 byte to send
    reg    firstwrite;       // set if this is the first clock of a ws2812 write
    reg    [2:0] bitcnt;     // counter for which bit we are sending
    reg    [3:0] pulsecnt;   // the number of sysclk to hold the output high or low
    reg    outstate;         // whether we are in the high or low part of an output pulse
    wire   [3:0] targetwidth;  // one of 7,15,12,or 14 depending bit to send and outstate


    assign targetwidth = (~wsdata[0] & outstate) ? 7 : // 350 ns for high part of a zero bit
                         (~wsdata[0] & ~outstate) ? 15 : // 750 ns for low part of a zero bit
                         (wsdata[0] & outstate) ? 12 : // 600 ns for high part of a one bit
                         14;                           // 700 ns for low part of a one bit

    initial
    begin
        firstwrite = 1;
    end

    always @(posedge clk)
    begin
        if (~myaddr)       // if not us ...
        begin
            firstwrite <= 1;          // reset firstwrite
            bitcnt <= 0;
            outstate <= 1;
            pulsecnt <= 0;
        end
        else if (strobe & ~rdwr & firstwrite)  // latch on first sysclk of write
        begin
            wsdata <= datin[7:0];
            firstwrite <= 0;          // set flag to run state machine
        end
        else if (strobe & ~rdwr & ~firstwrite)  // write but not first sysclk
        begin
            // At this point we are holding the busy line high while we shift out
            // the bits in wsdata.  The shift counter is bitcnt, the pulse width
            // counter is pulsecnt, and whether we are in the high or low part of
            // output pulse is set by outstate.


            // The wire targetwidth has the desired high/low count for pulsecnt.
            if (pulsecnt == targetwidth)
            begin
                outstate <= ~outstate;
                pulsecnt <= 0;
                if (~outstate)
                begin
                    // Shift out the next bit and reset the pulse width counter
                    // if we are at the end of the pulse low part of the output.  
                    wsdata <= (wsdata >> 1);
                    bitcnt <= bitcnt + 1;
                    if (bitcnt == 7)
                    begin
                        firstwrite <= 1;
                    end
                end
            end
            else
            begin
                // continue waiting for end of pulsecnt
                pulsecnt <= pulsecnt + 1;
            end
        end
    end

    // Assign the outputs.
    assign dline = outstate;
    assign clkline = ((pulsecnt == 2) & ~firstwrite);
    assign muxa = addr[0] & ~firstwrite;
    assign muxb = addr[1] & ~firstwrite;

    // Delay while we output the ws2812 data.
    // Lower busy when bitcnt==7, outstate==0, and pulsecnt==target
    assign busy_out = (~myaddr) ? busy_in : 
                      ~((bitcnt == 7) & (outstate == 0) & (pulsecnt == targetwidth));

    assign myaddr = (addr[11:8] == our_addr) && (addr[7:2] == 0);

    // Loop in-to-out where appropriate
    assign addr_match_out = myaddr | addr_match_in;
    assign datout = datin;                       // we are a write-only peripheral

endmodule

