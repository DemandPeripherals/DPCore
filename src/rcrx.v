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
//  File: irrx.v;   RC receiver
//
//  Registers: (high byte)
//      Reg 0:  Pulse #1 interval   (16 bits)  high or low, depending on sync polarity
//      Reg 2:  Pulse #1 interval   (16 bits)  low or high
//      Reg 4:  Pulse #2 interval   (16 bits)
//      Reg 6:  Pulse #2 interval   (16 bits)
//      Reg 8:  Pulse #3 interval   (16 bits)
//      Reg 10: Pulse #3 interval   (16 bits)
//      Reg 12: Pulse #4 interval   (16 bits)
//      Reg 14: Pulse #4 interval   (16 bits)
//      Reg 16: Pulse #5 interval   (16 bits)
//      Reg 18: Pulse #5 interval   (16 bits)
//      Reg 20: Pulse #6 interval   (16 bits)
//      Reg 22: Pulse #6 interval   (16 bits)
//      Reg 24: Pulse #7 interval   (16 bits)
//      Reg 26: Pulse #7 interval   (16 bits)
//      Reg 28: Pulse #8 interval   (16 bits)
//      Reg 30: Pulse #8 interval   (16 bits)
//      Reg 32: RC receiver status and configuration register
//
//      The pulse interval registers has two fields.  The MSB is the
//  value of the input during the interval being reported by the lower
//  15 bits.  The lower 15 bits are the duration of the interval in units
//  of 100 nanoseconds.
//
//      The low three bits of the configuration register specify the
//  number of channels to expect in the received signal.  Bit 3 of the
//  configuration register is unused.  Bits 4 and 5 set the GPIO
//  direction and bit 6 and 7 set the (output) GPIO values.
//
//      The first pin is the input from the RC receiver to the FPGA.  The
//  second pin is an output that is high when an RC packed is being received.
//  The second pin would usually be connected to an LED to show activity.
//  The remaining two pins are used for general purpose I/O.  The low two
//  bits of register 34 are the value of the pins and bits 4 and 5 control
//  the direction of the third and fourth connector pins respectively.  A
//  1 in the data direction bits indicates an output.  Reads and write to
//  the low two bits of register 34 read and set the pins depending on the
//  values in the data direction bits.
//
//
//  HOW THIS WORKS
//      Radio control systems encode the channel data as the position or
//  width of a string of pulses.  A "frame" is a complete sequence of these
//  pulses with a leading sync interval.  The sync interval is always at
//  least 3 milliseconds long.  The first edge after the sync interval is
//  the start of the pulse for channel #1.  The user value for a channel 
//  is the time from the leading edge of the channel pulse to the leading
//  edge of the next channel.  The signal may be inverted so we look for
//  edges and not specific values.  This circuit records both the high
//  and the low times for each pulse.  This additional information can be
//  used by the host to help determine if the signal is valid or not.
//      We send the data up to the host at an edge count of two times the
//  number of channels if none of the intervals exceeded 3.2 milliseconds.
//
/////////////////////////////////////////////////////////////////////////
module rcrx(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,
       n100clk, rcin, pktled, spare0, spare1);
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
    input  n100clk;          // 100 microsecond clock pulse
    input  rcin;             // Data from the RC receiver
    output pktled;           // Set high when we're getting a packet
    inout  spare0;
    inout  spare1;

    // RC pulse width registers and lines
    reg    ind1, ind2;       // Input delay lines
    reg    [14:0] main;      // Main pulse width measurement clock
    reg    [2:0] nchan;      // Channel count as set by the user.  Default is 6.
    reg    [4:0] count;      // Edge count.  At least 2x nchan
    reg    led;              // The latched state of the LED. 
    reg    state;            // wait for first edge, in pulses
    reg    data_ready;       // ==1 if a packet is ready for the host

    // Addressing, bus interface, and spare I/O lines and registers
    wire   myaddr;           // ==1 if a correct read/write on our address
    reg    [1:0] iodir;      // ==1 if pin is an output.  Default is input
    reg    [1:0] ioval;      // input values of I/O pins.

    // Pulse width data registers
    wire   [7:0] doutl;      // RAM output lines
    wire   [7:0] douth;      // RAM output lines
    wire   [3:0] raddr;      // RAM address lines
    wire   ramwen;           // RAM write enable
    rcrxram16x8 pulseL(doutl,raddr,main[7:0],clk,ramwen); // Register array in RAM
    rcrxram16x8 pulseH(douth,raddr,{ind2,main[14:8]},clk,ramwen);

    initial
    begin
        iodir = 0;       // spare pins default to input
        state = 0;       // Waiting for sync interval
        ind1 = 0;
        ind2 = 0;
        data_ready = 0;
        main = 0;
        count = 0;
        nchan = 6;
    end


    always @(posedge clk)
    begin
        // Do spare I/O stuff
        if (iodir[0] == 0)
            ioval[0] <= spare0;
        if (iodir[1] == 0)
            ioval[1] <= spare1;

        // Handle reads and writes from the host
        if (strobe && myaddr && (addr[5:0] == 32) && ~rdwr)
        begin
            nchan <= datin[2:0];      // latch channel count
            iodir <= datin[5:4];
            ioval <= datin[7:6];
        end
        else if (strobe && myaddr && rdwr && (addr[5:0] == 31))
        begin
            data_ready <= 0;
        end


        // Do all processing on edge of 100 ns clock
        else if (n100clk)
        begin
            // Get the input into our clock domain
            ind1 <= rcin;
            ind2 <= ind1;

            // We key on edges so just increment the counter if no edge
            if (ind2 == ind1)
            begin
                if (main != 15'h7fff)
                    main <= main + 1;
            end
            else if (main < 15'h0800)
            begin
                main <= main +1;
            end

            // Otherwise do edge / state machine processing
            else if (state == 0)     // waiting for first edge (and we got it!)
            begin
                // Sync has to be longer than 3.2 ms, otherwise continue looking
                if (main == 15'h7fff)
                begin
                    state <= 1;      // Start getting channel pulse widths
                    led <= 0;
                    count <= 0;      // Starting with an edge count of zero
                end
                main <= 0;           // Zero if wrong edge.  Zero for state=1 too.
            end
            else if (state == 1)     // Getting channel pulse widths
            begin
                // Validate data then store it in the registers
                if (main == 15'h7fff)
                begin
                    // Should not have a pulse this long in the data stream
                    state <= 0;
                end
                else begin
                    count <= count + 1;
                    if (count[3:1] == nchan)  // done with this packet??
                    begin
                        data_ready <= 1;
                        led <= 1;
                        state <= 0;
                    end
                end
                main <= 0;           // Get ready for next channel
            end
        end
    end


    // Assign the outputs.
    assign myaddr = (addr[11:8] == our_addr) && (addr[7:6] == 0);
    assign datout = (~myaddr) ? datin :
                    (~strobe && myaddr && data_ready) ? 8'h20 :   // Send up 32 bytes
                    (strobe && (addr[5:0] == 32)) ? {ioval,iodir,led,nchan} :
                    (strobe & (addr[0] ==0)) ? douth : 
                    (strobe & (addr[0] ==1)) ? doutl : 
                    0 ; 

    assign ramwen  = ((ind1 != ind2) && (state == 1) && (main != 15'h7fff));
    assign raddr = (strobe & myaddr) ? addr[4:1] : count ;

    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

    assign pktled = led;
    assign spare0 = (iodir[0] == 1) ? ioval[0]: 1'bz;
    assign spare1 = (iodir[1] == 1) ? ioval[1]: 1'bz;

endmodule




module rcrxram16x8(dout,addr,din,wclk,wen);
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



