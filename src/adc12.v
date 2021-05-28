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
//  File: adc12.v;   Eight channel, 12 bit ADC peripheral
//
//  Registers are 8 bit
//    Addr=0    Channel 0 ADC value (high/low)
//    Addr=2    Channel 1 ADC value (high/low)
//    Addr=4    Channel 2 ADC value (high/low)
//    Addr=6    Channel 3 ADC value (high/low)
//    Addr=8    Channel 4 ADC value (high/low)
//    Addr=10   Channel 5 ADC value (high/low)
//    Addr=12   Channel 6 ADC value (high/low)
//    Addr=14   Channel 7 ADC value (high/low)
//    Addr=16   Sample interval in ms
//    Addr=17   differ bits (set for differential input)
//  NOTES: 
//
//
/////////////////////////////////////////////////////////////////////////

`define ADCIDLE         2'h0
`define ADCGETSMPL      2'h1
`define ADCSNDRPLY      2'h2


module adc12(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,n100clk,m1clk,
       mosi,a,b,miso);
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
    input  n100clk;          // 100 nanosecond clock pulse
    input  m1clk;            // 1 millisecond clock pulse
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
    reg    meta;             // Used to bring miso into our clock domain
    reg    [7:0] smplrate;   // Sample rate in milliseconds input or not (zero indexed)
    reg    [7:0] ratediv;    // Sample rate counter/divider
    reg    [7:0] differ;     // Specifies whether to use single ended or differential ADC
    reg    [1:0] state;      // idle, getting samples, waiting to send samples
    reg    [2:0] smplinx;    // Which sample we're reading
    reg    [4:0] bitinx;     // Which bit of smplinx we reading/writing
    reg    [2:0] espiinx;    // Which substate of an espi bit we're in

    initial
    begin
        smplrate = 249;      // Send samples up every 250 milliseconds
        ratediv = 0;
        differ = 0;
        state = `ADCIDLE;
    end


    // Register array in RAM
    adcram16x8 adcram(dout,raddr,din,wclk,wen);

    always @(posedge clk)
    begin
        // Bring MISO into our clock domain
        meta <= miso;

        // Handle write and read requests from the host
        if (strobe & myaddr & ~rdwr)  // latch data on a write
        begin
            if (addr[4:0] == 16)
            begin
                smplrate <= datin[7:0];
            end
            else if (addr[4:0] == 17)
            begin
                differ <= datin[7:0];
            end
        end
        else if (strobe & myaddr & (state == `ADCSNDRPLY))  // back to idle after the reply pkt read
        begin
            state <= `ADCIDLE;
        end

        // Increment sample timer and switch state if time to sample
        else if (m1clk)
        begin
            if (ratediv == smplrate)
            begin
                ratediv <= 0;
                state <= `ADCGETSMPL;
                smplinx <= 0;     // First ADC input
                bitinx  <= 0;     // First bit of first ADC input
                espiinx <= 0;     // First espi state is to output the chip select
            end
            else
                ratediv <= ratediv + 8'h01;
        end

        // Do state machine to shift in/out the SPI data if getting smpl and on 10 MHz clk
        else if (n100clk  & (state == `ADCGETSMPL))
        begin
            if (espiinx != 5)  // Done with espi bit?
                espiinx <= espiinx + 3'h1;
            else
            begin
                espiinx <= 0;
                if (bitinx != 20)  // Done getting sample?
                    bitinx <= bitinx + 5'h01;
                else
                begin
                    bitinx <= 0;
                    if (smplinx != 7)  // Done getting all 8 samples?
                        smplinx <= smplinx + 3'h1;
                    else
                    begin
                        state <= `ADCSNDRPLY;
                    end
                end
            end
        end 
    end

    // espi bit timing ....
    // PERIOD =  0    1    2    3    4    5    0
    //      a =    L    L    L    L   H    L    H
    //      b =    H    L    H    H   H    H    H
    //   mosi =    cs   cs   cs   b0  b0   b0   cs

    // MCP3304 bit timing ....
    // BIT TIME = 0   1   2   3   4   5   6   7   8   9   10  11  12  13  14  15  16  17  18  19  20  0
    //       cs =  1   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   1  
    //     mosi =  x   1   s/d  a2  a1  a0  x   x   x   x   x   x   x   x   x   x   x   x   x   x   x   x
    //     miso =  x   x   x    x   x   x   x   0   d12 d11 d10 d9  d8  d7  d6  d5  d4  d3  d2  d1  d0  x

    // Assign the outputs.
    assign a = (state == `ADCGETSMPL) & (espiinx == 4);
    assign b = ~(espiinx == 1) & (state == `ADCGETSMPL);
    assign mosi = (espiinx < 3) ? (bitinx == 0) :
                  (bitinx == 1) ? 1'b1 :
                  (bitinx == 2) ? ~differ[smplinx] :
                  (bitinx == 3) ? smplinx[2] :
                  (bitinx == 4) ? smplinx[1] :
                  (bitinx == 5) ? smplinx[0] :
                  1'b0;


    // Assign the RAM control lines
    assign wclk  = clk;
    assign wen   = (state == `ADCGETSMPL) & (bitinx > 6) & (espiinx == 4); // latch while sck high
    assign din[0] = ((state == `ADCGETSMPL) && ((bitinx == 20) || (bitinx == 12))) ? meta : dout[0];
    assign din[1] = ((state == `ADCGETSMPL) && ((bitinx == 19) || (bitinx == 11))) ? meta : dout[1];
    assign din[2] = ((state == `ADCGETSMPL) && ((bitinx == 18) || (bitinx == 10))) ? meta : dout[2];
    assign din[3] = ((state == `ADCGETSMPL) && ((bitinx == 17) || (bitinx == 09))) ? meta : dout[3];
    assign din[4] = ((state == `ADCGETSMPL) && ((bitinx == 16) || (bitinx == 08))) ? meta : dout[4];
    assign din[5] = ((state == `ADCGETSMPL) && ((bitinx == 15) || (bitinx == 07))) ? meta : dout[5];
    assign din[6] = ((state == `ADCGETSMPL) && ((bitinx == 14) || (bitinx == 06))) ? meta : dout[6];
    assign din[7] = ((state == `ADCGETSMPL) && ((bitinx == 13) || (bitinx == 05))) ? meta : dout[7];
    assign raddr = (state == `ADCGETSMPL) ? {smplinx[2:0],(bitinx > 12)} : addr[3:0];

    // Assign the bus control lines
    assign myaddr = (addr[11:8] == our_addr) && (addr[7:5] == 0);
    assign datout = (~myaddr) ? datin :
                    (~strobe & (state == `ADCSNDRPLY)) ? 8'h10 :  // all replies have 16 bytes
                    (strobe) ? dout : 8'h00 ; 
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule


module adcram16x8(dout,addr,din,wclk,wen);
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
