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
//  File: ei2c.v;   General purpose I2C interface for up to 64 bit commands
//
//  Registers: 8 bit, read-write
//      Reg 0:  Bits 1/0 are the type of bit time as follows:
//                   0/0 Write a data bit of zero to the target I2C device
//                   0/1 Write a one or let the device write the bit value
//                   1/0 Start bit
//                   1/1 Stop bit
//              Bits 7/6 specify the clock frequency as:
//                   0/0 10 KHz
//                   0/1 100 KHz
//                   1/0 400 KHz
//                   1/1 1 MHz
//      Reg 1-31: Bits 0 to 1 as above.  Bits 6 and 7 are ignored.
//
//
//  HOW THIS WORKS
//      Each register visible to the host controls a single bit time
//  on the I2C bus.  Once the host has written all of the registers
//  it needs, the FPGA plays out the bits on the SDA and SCL lines.
//  The value for bit reads are written into Bit 0 of the register
//  for that bit time.
//
//  Start bits can occur more than once in a packet.  We use a stop
//  bit to indicate the end of a packet.  A data bit of one is either
//  a write of one or a read from the target I2C device since it can
//  pull the SDA line low if needed.  Either way we latch the SDA
//  value into Bit 0 to send back to the host as a reply.
//
//  Each I2c bit is broken into 4 quarter bits.  The bit quarter is
//  stored in bq (bit quarter) and goes from 0 to 3.  More details are
//  given below but Typical transitions are defined as follows:
//       bq  Outputs/inputs
//       0   SCL line is low if in data bit, set SDA if write
//       1   SCL goes high 
//       2   SCL stays high, change SDA if start or stop bit
//       3   SCL goes low if not stop.  End xfer/set pending if needed
//
//  Clock stretching is a way for the slave device to extend the length
//  of a clock pulse.  We honor clock stretching by staying in state 1 
//  until SCL goes high.
//
//  The cabling from the Baseboard to the ei2c has ringing on all of
//  the lines at any transition.  To overcome this we place a dual D
//  flip-flop on the card to latch the state of SCL and SDA.  Ringing
//  on the D inputs has no effect if the clock lines do not change and
//  ringing on the clock lines does not have any effect if the D input
//  does not change.  Pin2 is the D input to both flip-flops.  Pin4 is
//  is the clock input to the SDA flip-flop, and Pin6 is the clock to
//  the SCL flip-flop.  The low bits of the clock divider are used to
//  sequence the writes to Pin2, Pin4, and Pin6.  The SCA and SCL lines
//  are buffered with an open-drain NAND gate with the inputs going to
//  the Q output of the flip-flops.  Thus to write SDA high we actually
//  make the D input low.
//
//  Start Bit
//  bq=0  clkdiv=0  : set D low
//        clkdiv=1  : set SDA CK high (SDA goes high)
//        clkdiv=2  : set SDA CK low
//  bq=1  clkdiv=0  : set SCL CK high (SCL goes high)
//        clkdiv=1  : set SCL CK low
//  bq=2  clkdiv=0  : set D high
//        clkdiv=1  : set SDA CK high (SDA goes low)
//        clkdiv=2  : set SDA CK low
//  bq=3  clkdiv=0  : set SCL CK high (SCL goes low)
//        clkdiv=1  : set SCL CK low
//  
//  Data Bit
//  bq=0  clkdiv=0  : set D to data value inverted
//        clkdiv=1  : set SDA CK high (SDA goes high/low)
//        clkdiv=2  : set SDA CK low
//  bq=1  clkdiv=0  : set D low
//        clkdiv=1  : set SCL CK high (SCL should go high)
//            (wait in this state until SCL is high)
//        clkdiv=2  : set SCL CK low
//  bq=2  set D high
//        (latch SDA into bit 0 of the register)
//  bq=3  set D high
//        clkdiv=0  : set SCL CK high (SCL goes low)
//        clkdiv=1  : set SCL CK low
//  
//  Stop Bit
//  bq=0  clkdiv=0  : set D high
//        clkdiv=1  : set SDA CK high (SDA goes low)
//        clkdiv=2  : set SDA CK low
//  bq=1  clkdiv=0  : set D low
//        clkdiv=1  : set SCL CK high (SCL goes high)
//        clkdiv=1  : set SCL CK low
//  bq=2  clkdiv=0  : set SDA CK high (SDA goes high)
//        clkdiv=1  : set SDA CK low
//  
//  While not obvious we assume the D input remains unchanged until the
//  clock lines go low.
//
//  Clock Stretching
//  The FPGA gets both SDA and SCL from pin8.  Two open-drain NAND gates
//  form a multiplexer to select SDA, SCL, or neither.  A high on pin2
//  (D input) selects SDA.  A high on pin6 (SCL clock) selects SCL.  Both
//  low selects neither.  The use of a NAND gate means the signal on pin8
//  is inverted.
//      Pin2 is low and pin6 is high (SCL selected) just after clocking
//  SCL high.  Thus we can start watching pin8 immediately after setting
//  the SCL flip-flop clock line.  The state machine driving the counters
//  will pause just after raising SCL until it actually sees SCL go high.
//  
//  From the above we get:
//  Pin2 = D input = 1 if (start_bit & bq >= 2)  OR
//                        (data_bit & data==0 & bq==0) OR
//                        (data_bit & bq==2) OR
//                        (data_bit & bq==3) OR
//                        (stop_bit & bq==0)
//  Pin4 = SDA CLK = 1 if (start_bit & bq==0 & clkdiv==1) OR
//                        (start_bit & bq==2 & clkdiv==1) OR
//                        (data_bit & bq==0 & clkdiv==1) OR
//                        (stop_bit & bq==0 & clkdiv==1) OR
//                        (stop_bit & bq==2 & clkdiv==0)
//  Pin6 = SCL CLK = 1 if (start_bit & bq==1 & clkdiv==0) OR
//                        (start_bit & bq==3 & clkdiv==0) OR
//                        (data_bit & bq==1 & clkdiv==1) OR
//                        (data_bit & bq==3 & clkdiv==0) OR
//                        (stop_bit & bq==1 & clkdiv==1)
//
//                        
/////////////////////////////////////////////////////////////////////////
module ei2c(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout, pin2, pin4, pin6, pin8);
    input  clk;              // System clock
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
    output pin2;             // D input to both 7474 flip-flops
    output pin4;             // Clock input on flip-flop for the SDA line
    output pin6;             // Clock input on flip-flop for the SCL line
    input  pin8;             // SDA input

    // State variables
    reg    [2:0] smctr;      // State machine to control 7474 D and clk inputs
    reg    [1:0] bq;         // Bit quarter 
    reg    [6:0] bix;        // Packet bit index 
    reg    inxfer;           // set=1 if doing a transfer (set on end of packet stop bit)
    reg    dataready;        // set=1 to wait for an autosend to host
    reg    [5:0] clkdiv;     // divides 100 ns clock to get 1.6 MHz (about) for quarter bits
    reg    clkrate;          // ==1 for 400 KHz and 0 for 100 KHz
    wire   bqclk;            // ==1 on clock edge of quarter bit transitions
    wire   bqstart;          // in start of the quarter bit
    wire   start_bit;        // ==1 if in a start bit
    wire   data_bit;         // ==1 if in a data bit
    wire   stop_bit;         // ==1 if in a stop bit

    // Addressing and bus interface lines 
    wire   myaddr;           // ==1 if a correct read/write on our address

    // RAM for the I2C packet
    wire   [1:0] rout;       // RAM output lines
    wire   [6:0] raddr;      // RAM address lines
    wire   [1:0] rin;        // RAM input lines
    wire   wen;              // RAM write enable
    // RAM is broken into two 64x3 blocks
    wire   wen0;             // write enable for lower block
    wire   rout0[1:0];       // ram output lines
    ram64x1ei2c ram00(rout0[0],raddr[5:0],rin[0],clk,wen0); // i2c bit info as an array
    ram64x1ei2c ram01(rout0[1],raddr[5:0],rin[1],clk,wen0); // i2c bit info as an array
    wire   wen1;             // write enable for upper block
    wire   rout1[1:0];       // ram output lines
    ram64x1ei2c ram10(rout1[0],raddr[5:0],rin[0],clk,wen1); // i2c bit info as an array
    ram64x1ei2c ram11(rout1[1],raddr[5:0],rin[1],clk,wen1); // i2c bit info as an array


    initial
    begin
        bq = 0;
        bix = 0;
        dataready = 0;
        inxfer = 0;
        clkrate = 1;           // default is 400 KHz
    end

    always @(posedge clk)
    begin

        // Do 400/100 clock rate division from system clock.
        // But only if we are not doing SCL clock stretching
        //if (~(~pin8 & data_bit & (bq == 1) & (clkdiv == 1)))
        begin
            if ((clkrate && (clkdiv == 12)) || (~clkrate && (clkdiv == 48)))
                clkdiv <= 0;
            else
                clkdiv <= clkdiv + 1;
        end

        // reading the register for the last i2c bit clears the dataready flag
        if (strobe && rdwr && myaddr && ((addr[6:0] == (bix -1)) || (addr[6:0] == 7'h7f)))
        begin
            dataready <= 0;
        end

        // else look for first bit which had the clock rate in bit 7.
        if (strobe && ~rdwr && myaddr && (addr[6:0] == 0))
        begin
            clkrate <= datin[7];
        end

        // else look for end of packet (host is writing stop bit)
        if (strobe && ~rdwr && myaddr && (datin[1:0] == 2'b11))
        begin
            inxfer <= 1;       // Got packet from host, so start the i2c transfer
            clkdiv <= 0;       // reset clkdiv at start of bits
            bix <= 0;          // Start with bit zero
            bq <= 0;           // And sub-bit state of zero
        end

        // else if host is not rd/wr our regs and we're in an i2c transfer
        // and we're on a state machine edge 
        else if (~(strobe & myaddr & ~rdwr) & bqclk & inxfer)
        begin
            // Increment quarter bit state
            bq <= bq + 1;

            if (bq == 3)
            begin
                bix <= bix + 1;

                // A stop bit marks the end of a packet
                if (rout[1:0] == 2'b11)
                begin
                    dataready <= 1;
                    inxfer <= 0;
                end
            end
        end
    end


    // Assign the outputs.
    assign bqstart = (clkdiv[5:2] == 0) ;
    assign start_bit = inxfer && (rout[1:0] == 2'b10) ;
    assign data_bit  = inxfer && (rout[1] == 0) ;
    assign stop_bit  = inxfer && (rout[1:0] == 2'b11) ;

    //  Pin2 = D input = 1 if (start_bit & bq >= 2)  OR
    //                        (data_bit & data==0 & bq==0) OR
    //                        (data_bit & bq==2) OR
    //                        (data_bit & bq==3) OR
    //                        (stop_bit & bq==0)
    assign pin2 = (start_bit && (bq[1] == 1)) ||
                  (data_bit && bqstart && (rout[0] == 0) && (bq == 0)) ||
                  (data_bit && (bq == 2)) ||
                  (data_bit && (bq == 3)) ||
                  (stop_bit && bqstart && (bq ==0));

    //  Pin4 = SDA CLK = 1 if (start_bit & bq==0 & clkdiv==1) OR
    //                        (start_bit & bq==2 & clkdiv==1) OR
    //                        (data_bit & bq==0 & clkdiv==1) OR
    //                        (stop_bit & bq==0 & clkdiv==1) OR
    //                        (stop_bit & bq==2 & clkdiv==0)
    assign pin4 = (start_bit && bqstart && (bq == 0) && (clkdiv[1:0] == 1)) ||
                  (start_bit && bqstart && (bq == 2) && (clkdiv[1:0] == 1)) ||
                  (data_bit && bqstart && (bq == 0) && (clkdiv[1:0] == 1)) ||
                  (stop_bit && bqstart && (bq == 0) && (clkdiv[1:0] == 1)) ||
                  (stop_bit && bqstart && (bq == 2) && (clkdiv[1:0] == 0));

    //  Pin6 = SCL CLK = 1 if (start_bit & bq==1 & clkdiv==0) OR
    //                        (start_bit & bq==3 & clkdiv==0) OR
    //                        (data_bit & bq==1 & clkdiv==1) OR
    //                        (data_bit & bq==3 & clkdiv==0) OR
    //                        (stop_bit & bq==1 & clkdiv==1)
    assign pin6 = (start_bit && bqstart && (bq == 1) && (clkdiv[1:0] == 0)) ||
                  (start_bit && bqstart && (bq == 3) && (clkdiv[1:0] == 0)) ||
                  (data_bit && bqstart && (bq == 1) && (clkdiv[1:0] == 1)) ||
                  (data_bit && bqstart && (bq == 3) && (clkdiv[1:0] == 0)) ||
                  (stop_bit && bqstart && (bq == 1) && (clkdiv[1:0] == 1));


    assign bqclk = (clkrate && (clkdiv == 12)) || (~clkrate && (clkdiv == 48));

    // assign RAM signals
    assign wen0  = (raddr[6] == 0) &&
                   ((strobe & myaddr & ~rdwr) ||  // latch data on host write OR
                   (data_bit && bqstart && (bq == 2))); // i2c read/write
    assign wen1  = (raddr[6] == 1) &&
                   ((strobe & myaddr & ~rdwr) ||  // latch data on host write OR
                   (data_bit && bqstart && (bq == 2))); // i2c read/write
    assign rout[0]  = (raddr[6] == 0) ? rout0[0] : rout1[0];
    assign rout[1]  = (raddr[6] == 0) ? rout0[1] : rout1[1];
    assign raddr = (strobe & myaddr) ? addr[6:0] : bix ;
    assign rin[1] = (strobe & myaddr & ~rdwr) ? datin[1] : rout[1];
    assign rin[0] = (strobe & myaddr & ~rdwr) ? datin[0] :
                    (inxfer && (rout[1] == 0) && (bq == 2)) ? ~pin8 : rout[0];


    assign myaddr = (addr[11:8] == our_addr) && (addr[7] == 0);
    assign datout = (~myaddr) ? datin :
                    (~strobe && myaddr && (dataready)) ? {1'h0, (bix)} :
                    (strobe) ? {6'h00,rout} : 
                    0 ; 

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule



module ram64x1ei2c(dout,addr,din,wclk,wen);
   output dout;
   input  [5:0] addr;
   input  din;
   input  wclk;
   input  wen;

    // RAM64X1S: 64 x 1 posedge write distributed (LUT) RAM
    //           All FPGA
    // Xilinx HDL Libraries Guide, version 10.1.2

    RAM64X1S #(
        .INIT(64'h00000000)  // Initial contents of RAM
    ) RAM64X1S_inst (
    .O(dout),      // RAM output
    .A0(addr[0]),  // RAM address[0] input
    .A1(addr[1]),  // RAM address[1] input
    .A2(addr[2]),  // RAM address[2] input
    .A3(addr[3]),  // RAM address[3] input
    .A4(addr[4]),  // RAM address[4] input
    .A5(addr[5]),  // RAM address[5] input
    .D(din),       // RAM data input
    .WCLK(wclk),   // Write clock input
    .WE(wen)       // Write enable input
    );

    // End of RAM64X1S_inst instantiation
endmodule

