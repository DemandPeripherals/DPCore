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
//  File: irio.v;   IR receiver / transmitter
//
//  Registers: (8 bit)
//      Reg 0:  IR data bit in bit 0
//      Reg 1:  IR data bit in bit 0
//      Reg 2:  IR data bit in bit 0
//      Reg 3:  IR data bit in bit 0
//      :::::::::::::::::::::::::::::::::::::::::
//      Reg 30: IR data bit in bit 0
//      Reg 31: IR data bit in bit 0
//
//      There are up to 32 bits of IR packet data.
//      The configuration register is just the high bit of register 32.
//  It indicates the value of the input while an IR signal is being
//  received.
//
//  Hardware:
//      The first pin is the output to the Rx Activity LED.  The second
//  pin is the output to the Tx Activity LED.  The third pin is the output
//  to the IR transmit LEDs.  The fourth pin is the input from the IR
//  receiver to the FPGA.
//
//
//  HOW THIS WORKS : Receiver
//      The input is sampled every 200 microseconds.  When idle the circuit
//  is waiting for a AGC pulse of at least 8 ms followed by an off time of
//  at least 1.8 milliseconds.  If both of these conditions are met the
//  circuit starts taking reading of the "off" intervals. A reading is the
//  count (units of 200 us) of the duration of the off time.  Each reading
//  is resolved to a one or a zero depending on whether or not it is longer
//  than 1 millisecond.  The bit is put into a shift register and the "bit
//  count" is incremented by one.  The IR packet is considered complete if
//  the signal is off for more that 5 milliseconds.  The "data ready" flag
//  is set to indicate that a full packet is ready to be sent to the host.
//      The states of the receiver are "waiting for AGC". "in AGC", in 
//  "pause", and in "samples".
//
//  HOW THIS WORKS : Transmitter
//      Any write from the host forces the receiver into a "waiting for AGC"
//  state which effectively aborts any receive in progress.  This prevents
//  sending to the host a receive packet that has been corrupted by bits
//  from a send packet.  (Receiver and transmitter share the same RAM).
//  The receiver input is ignored during an IR transmission.
//      On receipt of a write to bit 31 the transmitter turns on "inxmit"
//  and enters the "sending AGC" state which sends 9 milliseconds of signal
//  at 38 KHz.  At the end of the the AGC pulse the transmitter enters "in
//  xmit pause", a 4.4 ms pause with the IR LEDs off.  At the end of the
//  pause the transmits enters the "in xmit bits" state which sends each
//  of the 32 bits in the RAM.  After the bits are send, the transmitter
//  goes to the "send trailing bit" state which defines the off time for the
//  last bit in the packet.
//      The IR clock is two cycles (high, then low) of a 13 microsecond 
//  counter.
//
/////////////////////////////////////////////////////////////////////////
module irio(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,
       u100clk, u1clk, rxled, txled, irout, irin);
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
    input  u1clk;            // 1 microsecond clock pulse
    output rxled;            // Set low when we're getting a packet
    output txled;            // Set low when sending a packet
    output irout;            // Controls the IR LEDs.  Low=on
    input  irin;             // Data from the IR receiver

    // IR pulse width registers and lines
    reg    in0;              // The value of the IR input but in our clock domain
    reg    [5:0] main;       // Main pulse width comparison clock
    reg    pclk;             // Period clock (200 us)
    reg    [5:0] count;      // Count of bits received after AGC/pause
    reg    [1:0] state;      // receiver: wait agc, in agc, in pause, in data
                             // transmitter: agc, agc pause, data, data trailing bit
    reg    inone;            // sub-state to the "in data" state.
    reg    data_ready;       // ==1 if a packet is ready for the host
    reg    inxmit;           // ==1 if we are transmitting an IR packet
    reg    [3:0] c76k;       // 76 KHz clock (about)
    reg    c38k;             // 38.4 KHz clock (about)

    // Addressing, bus interface, and spare I/O lines and registers
    wire   myaddr;           // ==1 if a correct read/write on our address

    // Registers for Rx and Tx data
    wire   rxout;            // Rx RAM output line
    wire   [4:0] rxaddr;     // Rx RAM address lines
    wire   rxin;             // Rx RAM input lines
    wire   rxwen;            // Rx RAM write enable
    irioram32x1 irrx(rxout,rxaddr,rxin,clk,wen);

    initial
    begin
        state = 0;       // Receiver is waiting for AGC pulse
        inone = 1;       // state 3 starts with the input high
        in0 = 0;         // Start assuming no IR signal present
        data_ready = 0;
        main = 0;
        inxmit = 0;
    end


    always @(posedge clk)
    begin
        // Get the 200 microsecond clock
        if (u100clk)
            pclk <= ~pclk;

        // Get the 38 KHz clock
        if (u1clk)
        begin
            if (c76k == 12)          // 0-12 is 13 useconds
            begin
                c76k <= 0;
                c38k <= ~c38k;
            end
            else
                c76k <= c76k + 4'h1;
        end

        // Handle reads and writes from the host
        if (strobe && myaddr && (addr[4:0] == 31))
        begin
            if (rdwr)
                data_ready <= 0;     // Clear data ready on a read
            else
            begin
                inxmit <= 1;         // Start xmit state machine   
                state <= 0;          // xmitter sends AGC first
                main <= 0;
            end
        end

        // Do xmit state machine on each edge of the 1 MHz clock
        else if (pclk && u100clk && inxmit)
        begin
            if (state == 0)          // Sending a 10 ms AGC pulse
            begin
                if (main == 50)
                begin
                    main <= 0;
                    state <= 1;
                end
                else
                    main <= main + 6'h01;
            end
            if (state == 1)          // Sending 4.4 ms pause after AGC
            begin
                if (main == 22)
                begin
                    main <= 0;
                    state <= 2;      // Go to 'sending bits' state
                    count <= 0;      // Start on bit #0
                    inone <= 1;      // start bit by sending IR pulse
                    c38k <= 0;
                end
                else
                    main <= main + 6'h01;
            end
            if (state == 2)          // Sending data bits
            begin
                if (inone)
                begin
                    if (main == 2)   // End of 600 us IR pulse?
                    begin
                        main <= 0;
                        inone <= 0;
                    end
                    else
                        main <= main + 6'h01;
                end
                else  // must be in pause after bit's IR pulse
                begin
                    if (((rxout == 0) && (main != 2)) ||
                        ((rxout == 1) && (main != 7)))
                    begin
                        main <= main + 6'h01;
                    end
                    else  // done with this bit
                    begin
                        if (count == 31)
                        begin
                            state <= 3;
                        end
                        else  // go to start of next bit
                        begin
                            count <= count + 6'h01;
                        end
                        inone <= 1;
                        c38k <= 0;
                        main <= 0;
                    end
                end
            end
            if (state == 3)          // Sending trailing pulse to define last bit
            begin
                if (main == 2)       // Trailing pulse is 600 us
                begin
                    main <= 0;
                    inxmit <= 0;
                    state <= 0;      // Let receiver listen for AGC pulse
                end
                else
                    main <= main + 6'h01;
            end
        end

        // Do all receiver processing on edge of 200 us clock
        else if (pclk && u100clk && ~data_ready && ~inxmit)
        begin
            // Get the input into our clock domain
            // in0 == 1 when IR signal is present.
            in0 <= ~irin;

            // Process the state machine
            if (state == 0)          // waiting for AGC
            begin
                main <= (in0) ? (main + 6'h01) : 6'h00;
                if (main == 40)      // 8 milliseconds ?
                    state <= 1;      // go to "in AGC"
            end
            else if (state == 1)     // in AGC pulse, wait for its end
            begin
                if (in0 == 0)
                begin
                    state <= 2;      // go to "in pause"
                    main <= 0;
                end
            end
            else if (state == 2)     // in pause
            begin
                if (in0 == 0)
                begin
                    main <= main + 6'h01;
                    if (main == 6'h3f)   // error if main wraps while in pause period
                        state <= 0;  // Back to waiting for AGC pulse
                end
                else
                begin                // getting an IR signal, go get data bits
                    if (main > 9)    // pause period is at least 1.8 milliseconds
                    begin
                        state <= 3;  // Go get data bits
                        inone <= 1;
                        count <= 0;
                    end
                    else             // pause less than 2 ms is an error
                    begin
                        state <= 0;  // Back to waiting for AGC pulse
                    end
                    main <= 0; 
                end
            end
            else if (state == 3)     // collecting data bits
            begin
                if (inone == 0)      // data is in the low period.  Measure this time
                begin
                    if (in0 == 0)
                    begin
                        main <= main + 6'h01;
                        if (main > 20)
                        begin
                            data_ready <= 1;
                            state <= 0;
                            main <= 0;
                        end
                    end
                    else             // Got the edge of the next bit.  Record this bit
                    begin
                        // The value of main is stored in the shift register at this time
                        main <= 0;
                        inone <= 1;
                        count <= count + 6'h01;
                        if (count == 5'h1f)   // Force packet end on bit 31
                        begin
                            data_ready <= 1;
                            state <= 0;
                            main <= 0;
                        end
                    end
                end
                else     // inone==1
                begin
                    if (in0 == 0)
                    begin
                        // At the end of the IR pulse.  Was it the right width?
                        if (main > 5)
                        begin
                            main <= 0;
                            state <= 0;
                        end
                        else         // switch to inone==false and measure time
                        begin
                            inone <= 0;
                            main <= 0;
                        end
                    end
                    else             // input==1 so state in the 'inone==true' state
                    begin
                        main <= main + 6'h01;
                    end
                end
            end
        end
    end


    // Route the RAM and output lines
    assign rxaddr = (strobe & myaddr) ? addr[4:0] : count[4:0] ;
    // data into the RAM is the data bus on host write or the IR signal on receive pkts
    assign rxin = (strobe & myaddr & ~rdwr & ~(addr[5:0] == 32)) ? datin[0] :
                  (main > 4) ? 1'b1 : 1'b0;   // decide if bit is a zero or a one
    // latch data while receiving IR or when getting a packet from the host
    assign wen  = ((state == 3) && (inone == 0) && (in0 == 1))  // start of next IR bit
                  | (strobe & myaddr & ~rdwr & ~(addr[5:0] == 32)); // latch host write

    // Assign the outputs.
    assign myaddr = (addr[11:8] == our_addr) && (addr[7:5] == 0);
    assign datout = (~myaddr) ? datin :
                    (~strobe && myaddr && data_ready) ? 8'h20 :  // Send 32 bytes if ready
                    (strobe) ? {7'h0,rxout} : 
                    8'h00 ; 

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

    assign rxled = ~(((state != 0) && ~inxmit) || data_ready);
    assign txled = ~inxmit;
    assign irout = ~(inxmit & c38k & inone & (state != 1));

endmodule


module irioram32x1(dout,addr,din,wclk,wen);
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

