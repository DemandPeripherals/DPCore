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
//  File: espi.v;   Encoded Serial Peripheral Interface
//
//  Registers are
//    Addr=0    Clock select, chip select control, interrupt control and
//              SPI mode register
//    Addr=1    Max addr of packet data (== SPI pkt sz + 1)
//    Addr=1    Data byte #1 in/out
//    Addr=2    Data byte #2 in/out
//    Addr=3    Data byte #3 in/out
//    Addr=4    Data byte #4 in/out
//    Addr=5    Data byte #5 in/out
//    Addr=6    Data byte #6 in/out
//
//  NOTES: 
//   - The RAM addresses are numbered from zero and the first two locations
//     are mirrors of the two config registers.  Thus the actual SPI packet
//     data starts at addr=2 and goes up to (SPI_pkt_sz + 1).  Note that CS
//     is asserted for one full byte time before SCLK starts.
//   - The ribbon cables connecting daughter cards to the FPGA card will
//     have ringing on them.  This would be disastrous if tied directly
//     to the SCLK line.  To work around this we add a circuit on each espi
//     card to give the SCLK line as the output of a 7474 dual flip-flop.
//     The clkdiv register runs the state transitions for the circuit.  If
//     there are three lines called a, b, and c, the info on them as a
//     function of clkdiv is as follows:
//     clkdiv = 0;  a=MOSI, b=1, c=1.   SCLK goes high at the start of period
//     clkdiv = 1;  a=CS,   b=0, c=1.   MISO strobe high, latching at end of period
//     clkdiv = 2;  a=CS,   b=0, c=0.   SCLK goes low at the start of period
//     clkdiv = 3;  a=CS,   b=0, c=1.   
//     clkdiv = 4;  a=MOSI, b=0, c=1.   SCLK goes high at the end of period
//
//
/////////////////////////////////////////////////////////////////////////

`define IDLE         2'h0
`define GETBYTE      2'h1
`define SNDBYTE      2'h2
`define SNDRPLY      2'h3
`define CS_MODE_AL   2'h0   // Active low chip select
`define CS_MODE_AH   2'h1   // Active high chip select
`define CS_MODE_FL   2'h2   // Forced low chip select
`define CS_MODE_FH   2'h3   // Forced high chip select
`define CLK_2M       2'h0   // 2 MHz
`define CLK_1M       2'h1   // 1 MHz
`define CLK_500K     2'h2   // 500 KHz
`define CLK_100K     2'h3   // 100 KHz


module espi(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,u100clk,
       u10clk,u1clk,n100clk,mosi,a,b,miso);
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
    input  u100clk;          // 100 microsecond clock pulse
    input  u10clk;           // 10 microsecond clock pulse
    input  u1clk;            // 1 microsecond clock pulse
    input  n100clk;          // 100 nanosecond clock pulse
    output mosi;             // SPI Master Out / Slave In
    output a;                // Encoded SCK/CS strobe
    output b;                // Encoded SCK/CS strobe
    input  miso;             // SPI Master In / Slave Out
 
    wire   myaddr;           // ==1 if a correct read/write on our address
    wire   [7:0] dout;       // RAM output lines
    wire   [3:0] raddr;      // RAM address lines
    wire   [7:0] din;        // RAM input lines
    wire   wclk;             // RAM write clock
    wire   wen;              // RAM write enable
    wire   smclk;            // The SPI state machine clock (=2x sck)
    wire   rawcs;            // CS from the user
    reg    [1:0] clksrc;     // SCK clock frequency (2,1,.5,.1 MHz)
    reg    [1:0] csmode;     // Chip select mode of operation
    reg    [3:0] mxaddr;     // Number of bytes in the SPI pkt +1  (or RAM addr 0-to-(N-1))
    reg    meta;             // Used to bring miso into our clock domain
    reg    [1:0] clkpre;     // clock prescaler
    reg    [2:0] clkdiv;     // clock state divider
    reg    [1:0] state;      // idle, getting bytes, sending bytes, sending response
    reg    [3:0] bytcnt;     // counter for getting and sending bytes
    reg    [3:0] bitcnt;     // bit counter for shift register
    reg    int_en;           // Interrupt enable. 1==enabled
    reg    int_pol;          // Interrupt polarity, 1==int pending if MISO is high while CS=0
    reg    int_pend;         // We've sent an interrupt packet, no need to send another

    initial
    begin
        clksrc = 0;
        csmode = 0;
        state = `IDLE;
        clkdiv[2:0] = 0;
        int_en = 0;
        int_pol = 0;
        int_pend = 0;
    end


    // Register array in RAM
    espiram16x8 spipkt(dout,raddr,din,wclk,wen);

    // Generate the state machine clock for the ESPI interface
    assign smclk = (clksrc[1:0] == `CLK_2M)   ? (clkpre[0]) :
                   (clksrc[1:0] == `CLK_1M)   ? (clkpre[1:0] == 3) :
                   (clksrc[1:0] == `CLK_500K) ? ((clkpre[1:0] == 3) & n100clk) :
                   (clksrc[1:0] == `CLK_100K) ? ((clkpre[0]) & u1clk) : 0 ;

    always @(posedge clk)
    begin
        // Bring MISO into our clock domain
        meta <= miso;

        // Do frequency division for the sck
        if ((clksrc == `CLK_2M) || (clksrc == `CLK_1M) ||
            (n100clk & (clksrc == `CLK_500K)) ||
            (u1clk & (clksrc == `CLK_100K)))
        begin
            clkpre <= clkpre + 1;
        end

        if (smclk)
        begin
            if (clkdiv[2:0] == 4)
                clkdiv[2:0] <= 0;
            else
                clkdiv[2:0] <= clkdiv[2:0] + 1;
        end

        // Handle write and read requests from the host
        if (strobe & myaddr & ~rdwr)  // latch data on a write
        begin
            if (addr[3:0] == 0)
            begin
                clksrc <= datin[7:6];
                int_en <= datin[5];
                int_pol <= datin[4];
                csmode <= datin[3:2];
                state <= `IDLE;
            end
            else if (addr[3:0] == 1)
            begin
                mxaddr <= datin[3:0];
                bytcnt <= 2;
                state <= `GETBYTE;
            end
            else
            begin    // Getting bytes from the host.  Send SPI pkt when done
                bytcnt <= bytcnt + 1;
                if (bytcnt == mxaddr)
                begin
                    state <= `SNDBYTE;
                    bytcnt <= 1;
                    bitcnt <= 0;
                end
            end
        end
        else if (strobe & myaddr & (state == `SNDRPLY))  // back to idle after the reply pkt read
        begin
            state <= `IDLE;
            bytcnt <= 0;
        end

        // Do the state machine to shift in/out the SPI data if sending and on clk edge
        else if (smclk  & (state == `SNDBYTE))
        begin
             if (clkdiv[2:0] == 2)
             begin
                if (bitcnt == 9)
                begin
                    bitcnt <= 0;
                    bytcnt <= bytcnt + 1;
                    if (bytcnt == mxaddr)
                    begin
                        state <= `SNDRPLY;
                    end
                end
                else
                begin
                    bitcnt <= bitcnt + 1;
                end
            end
        end 
        // set the interrupt pending flag just as we start the 1 byte transmission
        // to the host.  This way only one packet is sent
        if (myaddr & ~strobe & (state ==`IDLE) & (miso == int_pol) & (int_en) & (~int_pend))
        begin
            int_pend <= 1;
        end
        if(myaddr & ~strobe & (state == `SNDRPLY) & (int_pend))
        begin
            // Clear the interrupt pending flag on any data to host
            int_pend <= 0;
        end
    end


    // Assign the outputs.
    assign rawcs = (csmode == `CS_MODE_AL) ? ~(state == `SNDBYTE) :
                   (csmode == `CS_MODE_AH) ? (state == `SNDBYTE) :
                   (csmode == `CS_MODE_FH) ? 1 : 0;
    assign a = (state == `SNDBYTE) & (bytcnt > 1) & (bitcnt < 8) & (clkdiv[2:0] == 0);
    assign b = ~(clkdiv[2:0] == 2);
    assign mosi = ((clkdiv[2:0] > 0) & (clkdiv[2:0] < 4)) ? rawcs :
                          ((dout[0] & (bitcnt == 7)) |
                           (dout[1] & (bitcnt == 6)) |
                           (dout[2] & (bitcnt == 5)) |
                           (dout[3] & (bitcnt == 4)) |
                           (dout[4] & (bitcnt == 3)) |
                           (dout[5] & (bitcnt == 2)) |
                           (dout[6] & (bitcnt == 1)) |
                           (dout[7] & (bitcnt == 0))) ;


    // Assign the RAM control lines
    assign wclk  = clk;
    assign wen   = (state != `SNDBYTE) ? (strobe & myaddr & ~rdwr) :
                   ((bitcnt < 8) & (clkdiv[2:0] == 1)) ;
    assign din[0] = (state != `SNDBYTE) ? datin[0] : (bitcnt == 7) ? meta : dout[0];
    assign din[1] = (state != `SNDBYTE) ? datin[1] : (bitcnt == 6) ? meta : dout[1];
    assign din[2] = (state != `SNDBYTE) ? datin[2] : (bitcnt == 5) ? meta : dout[2];
    assign din[3] = (state != `SNDBYTE) ? datin[3] : (bitcnt == 4) ? meta : dout[3];
    assign din[4] = (state != `SNDBYTE) ? datin[4] : (bitcnt == 3) ? meta : dout[4];
    assign din[5] = (state != `SNDBYTE) ? datin[5] : (bitcnt == 2) ? meta : dout[5];
    assign din[6] = (state != `SNDBYTE) ? datin[6] : (bitcnt == 1) ? meta : dout[6];
    assign din[7] = (state != `SNDBYTE) ? datin[7] : (bitcnt == 0) ? meta : dout[7];
    assign raddr = (state == `SNDBYTE) ? bytcnt[3:0] : addr[3:0];

    // Assign the bus control lines
    assign myaddr = (addr[11:8] == our_addr) && (addr[7:4] == 0);
    assign datout = (~myaddr) ? datin :
                    (~strobe & (state == `SNDRPLY)) ? 8'h10 :  // all replies have 16 bytes
                    // send one byte if device is requesting service/interrupt
                    (~strobe & (state ==`IDLE) & (miso == int_pol) & (int_en) & (~int_pend)) ? 8'h01 :
                    (strobe) ? dout : 0 ; 
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule


module espiram16x8(dout,addr,din,wclk,wen);
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
