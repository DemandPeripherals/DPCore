// *********************************************************
// Copyright (c) 2021 Demand Peripherals, Inc.
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


`define BAUD460800   2'b00
`define BAUD230400   2'b01
`define BAUD115200   2'b11
`define BAUD_DEFAULT 2'b11


//////////////////////////////////////////////////////////////////////////
//
//  File: hostserial.v;   Serial interface to the bus controller
//
//  Registers are
//    Addr=0    Configuration:
//              bit 2: enabled.  Default is 0, off
//              bits 1-0: baud.  00=460K,01=230K,11=115K
//
//  Notes:
//     The trsnsmit FIFO should never get full.  When it does it resets
//  the pointers and a full buffer of data is lost.
//
/////////////////////////////////////////////////////////////////////////
module hostserial(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,txd,rxd,spare1,spare2,
       sec_enabled,rxbyteout,ready_,ack_,txdstrobe,nomore,dattxd);
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
    // Pins on the baseboard connector
    output txd;              // serial data to the host
    input  rxd;              // serial data from the host
    output spare1;           // debug value of buffull
    output spare2;           // debug value of overflow
    // Signals to the bus interface unit
    output sec_enabled;      // set if the secondary interface is enabled
    output [7:0] rxbyteout;  // data byte into the FPGA bus interface
    output ready_;           // data ready strobe to the FPGA bus interface
    input  ack_;             // the bus interface acknowledges the new byte
    input  txdstrobe;        // pulse to write data to txd output buffer
    output nomore;           // ==1 to tell SLIP to stop sending characters
    input  [7:0] dattxd;     // Data into the txd FIFO


    wire   myaddr;           // ==1 if a correct read/write on our address
    reg    [1:0] baudrate;   // baudrate as a divider from 460K
    reg    enabled;          // set to 1 to make this the host interface
    assign sec_enabled = enabled;
    wire   buffull;          // ==1 if the tx FIFO is full
    // Uncomment the following line if you want to apply backpressue to the
    // bus when the tx FIFO is full.  You'll also need to change the test 
    // for buffull in the hosttx module.  
    // assign nomore = buffull;   // apply bus backpressure
    assign nomore = 1'b0;         // no bus backpressure
    reg    overflow;          // ==1 if the tx FIFO is about to overflow
    assign spare1 = buffull;  // used in debugging
    assign spare2 = overflow; // used in debugging

    // instantiate the receiver
    hostrx rx(clk,rxd,rxbyteout,ready_,ack_,baudrate);

    // instantiate the transmitter
    // Only take data in if we're enabled
    hosttx tx(clk,(txdstrobe & enabled),buffull,dattxd,txd,baudrate);

    initial
    begin
        baudrate = `BAUD_DEFAULT;
        enabled = 1'b0;
        overflow = 1'b0;
    end

    always @(posedge clk)
    begin
        if (strobe & myaddr & (addr[0] == 1'b0))
        begin
            if (~rdwr)
            begin
                baudrate <= datin[1:0];  // latch data on a write
                enabled <= datin[2];
            end
            else
                overflow <= 1'b0;     // clear flag on read
        end
        if (buffull)
            overflow <= 1'b1;
    end

    // Assign the outputs.
    assign myaddr = (addr[11:8] == our_addr) && (addr[7:1] == 0);
    assign datout = (~myaddr) ? datin : 
                     (~strobe & overflow) ? 8'h01 :  // Send data on tx fifo overflow
                     (strobe && (addr[0] == 0)) ? {3'h0,spare1,overflow,enabled,baudrate} :
                     8'h00;

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule



// Serial receive from host
module hostrx(clk,rxd,byteout,ready_,ack_,baudrate);
    input    clk;               // system clock
    input    rxd;               // serial data from host
    output   [7:0] byteout;     // completed serial character
    output   ready_;            // active low, data at byteout is valid 
    input    ack_;              // bus interface acknowledges the new byte (low)
    input    [1:0] baudrate;    // 0=460800,1=230400,3=115200

           // Target baud rate
    reg    [1:0] smplctr;       // sets rxd sample rate based on baudrate

           // Bit state and shift register info
    reg    inxfer;              // ==1 while in a byte transfer
    reg    [2:0] bitidx;        // which bit we are receiving
    reg    [6:0] bitdly;        // interbit delay counter
    reg    [7:0] shiftbyte;     // byte as it is being received
    reg    [7:0] latchbyte;     // latched byte
    reg    rdy_;                // bit for the ready flad
    assign byteout = latchbyte;
    assign ready_ = rdy_; 

           // Low Pass Filter
           // The low pass filter looks at each input in turn (based on rdsel)
           // and accumulates a +1 if the input is high or a -1 if the input
           // is low.  The outputs are the current bit for rxd and
           // the next bit.  The inputs are examined only when smplctr is zero
           // which should be about 44 times per bit
    wire   nxtbit;     // next value of LPF output for rxd
    wire   curbit;     // current value of LPF output for rxd
    wire   enable;     // do addumulation if set
    lpf    lpfrx(clk, rxd, enable, nxtbit, curbit);
    assign enable = (smplctr == 1'b0);

    initial
    begin
        smplctr = 1'h0;
        inxfer = 1'b0;
        bitidx = 3'h0;
        bitdly = 7'h00;
        shiftbyte = 8'h00;
        latchbyte = 8'h00;
        rdy_ = 1'b1;
    end

    always @(posedge clk)
    begin
        // We want to sample the inputs at a rate that is set by the
        // baudrate.  At 460K we sample one input on every sysclk.  
        // At 230K, every two sysclk.  The down counter smplctr is
        // is decremented to zero and then reloaded from baudrate
        if (smplctr != 3'h0)
        begin
            smplctr <= smplctr - 2'h1;
        end
        else
        begin
            smplctr <= baudrate;   // reset the sample down counter

            // Check for start bit in idle input port
            if ((inxfer == 1'b0) && (nxtbit == 1'b0) && (curbit == 1'b1))
            begin
                inxfer <= 1'b1;
                bitdly <= 7'd76;   // (42 + 34) one and three-quarters of a bit
            end
            // else process input if we are already in an xfer
            if (inxfer == 1'b1)
            begin
                // decrement the bit delay counter and reload it if needed
                if (bitdly == 7'h00)
                begin
                    // it is at this point that we write the current bit
                    // and go to the next bit
                    bitdly <= 7'd42;
                    bitidx <= bitidx + 3'h1;  // go to next bit
                    shiftbyte <= (shiftbyte >> 1) | {curbit,7'h00};
                    if (bitidx == 3'h7)              // done with char?
                    begin
                        // Done with this char. update ready flag
                        latchbyte <= (shiftbyte >> 1) | {curbit,7'h00};
                        inxfer <= 1'b0;
                        rdy_ <= 1'b0;
                    end
                end
                else
                begin
                    bitdly <= bitdly - 1;
                end
            end
        end

        // clear ready_ flag on ack
        if ((rdy_ == 0) && (ack_ == 0))
            rdy_ <= 1;
    end

endmodule


//
// Low Pass Filter.
// Accumulate a +1 if input[insel] is one and -1 if zero.  Saturate at
// values of 15 and 0.  We use hysteresis as part of the noise rejection.
// A zero bit must reach a value of 12 before it is switched to a one bit,
// and a one bit must get down to 3 to be declared a zero bit.
// We do this accumulation about 44 times per baud bit.
module lpf(clk, rxd, enable, nxtbit, curbit);
    input    clk;                           // system clock
    input    rxd;                           // input Rx lines
    input    enable;                        // do accumulation if set
    output   nxtbit;                        // new value of LPF output for bit
    output   curbit;                        // old value of LPF output for bit

    reg      [3:0] accum;                   // accumulator
    reg      current;                       // Current bit value
    wire     next;                          // the next value of the bit

    initial
    begin
        accum = 4'h0;
        current  = 1'b0;
    end

    always@(posedge clk)
    begin
        if (enable)
        begin
            current <= next;

            // if input line is a zero and not zero saturated
            if ((rxd == 1'b0) && (accum != 4'h0))
                accum <= accum - 1;
            // if input line is a one and we're not saturated
            if ((rxd == 1'b1) && (accum != 4'hf))
                accum <= accum + 1;
        end
    end

    // The next bit is one if the accumulator is 12 or above,
    // is zero if the accumulator is 3 or below, and is not
    // changed if between 4 and 11
    assign next = (accum >= 4'd12) ? 1'b1 :
                  (accum <= 4'd3) ? 1'b0 :
                  current;

    assign nxtbit = next;
    assign curbit = current;

endmodule



        // Log Base 2 of the output buffer size
`define LB2BUFSZ   10


// Serial transmit to the host
module hosttx(clk,strobe,buffull,datin,txd,baudrate);
    input  clk;              // system clock
    input  strobe;           // true on full valid command
    output buffull;          // ==1 if FIFO can not take more characters
    input  [7:0] datin ;     // Data toward the host
    output txd;              // output line
    input  [1:0] baudrate;   // divider of 460K to get bit rate

           //   baud rate generator and divider
    reg    [1:0] baudcount;  // counter to divide the 461k clock down
    wire   baudclk;
    baud461k b1(clk, baudclk);


           //  FIFO control lines
    reg    [`LB2BUFSZ-1:0] watx; // FIFO write address for Tx
    reg    [`LB2BUFSZ-1:0] ratx; // FIFO read address for Tx
    wire   bufempty;   // ==1 if there are no characters to send
    assign buffull = ((watx + `LB2BUFSZ'h01) == ratx) ? 1'b1 : 1'b0 ;
    assign bufempty = (watx == ratx) ? 1'b1 : 1'b0 ;
           // latch the buff empty status at start of each Tx byte
    reg    emptylatch;

           // RAM control lines
    wire   we;                    // RAM write strobe for Tx
    wire   [`LB2BUFSZ-1:0] wa;     // bit write address (`LB2BUFSZ bytes per port)
    wire   [`LB2BUFSZ-1:0] ra;     // bit read address
    wire   [7:0] rd;              // registered read data from RAM
    dpram  memtx(clk, we, wa, datin, ra, rd);
           // write when (our address) and (not config register) and (selected 
           // port is not full)
    assign we = (strobe & (buffull == 0));
           // write address is port number in high two bits and port's FIFO
           // write address in the lower bits
    assign wa = watx;
           // read address is port number from rdsel and the FIFO read address
    assign ra = ratx;

           // Serial bit shifting
           // baudflag is set on each baudclk.  It starts the port counter rdsel
    reg    baudflag;
           // Bit multiplexer to select start bit, stop bits, or data bits
    reg    [3:0] bitreg;     // shift counters to set which bit is on output Tx line
           // state of the Tx lines
    reg    sendbit;
    assign txd = sendbit;


    initial
    begin
        watx = `LB2BUFSZ'h000;
        ratx = `LB2BUFSZ'h000;
        bitreg = 1'h0;
        baudcount = 2'h0;
    end

    always @(posedge clk)
    begin
        // Pick which of the following two lines based on how you
        // want a full buffer to be handled.  If you test for buffull
        // you will apply back pressure onto the bus and chaos will
        // follow.  If you don't test for buffull the buffer will wrap,
        // you'll lose a buffer full of data, and chaos will follow.
        if (strobe)                  // latch data on a write
        //if (strobe && (~buffull))  // latch data on a write
        begin
            watx <= watx + `LB2BUFSZ'h01;
        end

        if (baudclk)
        begin
            // divide baudclk by bauddiv and set flag to start new bit output
            if (baudcount == 0)
            begin
                baudflag <= 1'b1;
                baudcount <= baudrate;
                // Increment bitreg if not the last bit.
                // 10 bits (0-9) if 1 stop bit.  More if more stop bits
                if (bitreg == 4'd10)
                begin
                    bitreg <= 4'h0;
                    emptylatch <= bufempty;
                end
                else // not last bit to send
                    bitreg <= bitreg + 4'h1;
            end
            else
                baudcount <= baudcount - 4'h1;
        end
        if (baudflag)
        begin
            // reset baudflag
            baudflag <= 1'b0;

            // Latch the serial bit from RAM on the second (of two) 
            // states of rdsel.
            if (~emptylatch)
            begin
                sendbit <= 
                    (bitreg == 0) ? 1'b0 :
                    (bitreg == 1) ? rd[0] :
                    (bitreg == 2) ? rd[1] :
                    (bitreg == 3) ? rd[2] :
                    (bitreg == 4) ? rd[3] :
                    (bitreg == 5) ? rd[4] :
                    (bitreg == 6) ? rd[5] :
                    (bitreg == 7) ? rd[6] :
                    (bitreg == 8) ? rd[7] :
                    (bitreg == 9) ? 1'b1 :
                    (bitreg == 10) ? 1'b1 :
                    (bitreg == 11) ? 1'b1 :
                    (bitreg == 12) ? 1'b1 :
                    (bitreg == 13) ? 1'b1 :
                    (bitreg == 14) ? 1'b1 : 1'b1;

                // We are at the bit transition of the port specified by the
                // high bits of rdsel.  If this the last bit to send then
                // increment the read index to the next location in the FIFO.
                // 10 bits (0-9) if 1 stop bit.  More if more stop bits
                if (bitreg == 4'd10)
                begin
                    ratx <= ratx + `LB2BUFSZ'h01;
                end
            end
        end
    end
endmodule


// baud461k
// This module generates a 460800 Hertz clock with an error of less
// 0.2 percent.  
module baud461k(clk, baudout);
    input  clk;              // system clock (20 MHz)
    output baudout;          // a clk wide pulse 461k times per second

    //  460800 is between 43 and 44 50ns clocks.  We use a phase accumulator to
    //  delay 43 or 44 clocks depending on the accumulated phase.  We accumulate
    //  50 ns of phase on each 20 MHz clock.  The period jumps between 2150 and
    //  2200 nanoseconds.  The number of bits in the accumulator sets the average
    //  error.  We use 8 bits and error on the slow side by 0.23 percent.  The
    //  following table shows the average baud period.  Ideal is 2170ns.
    //  BITS, TESTBIT, INITIAL, DECREMENT, PERIOD(ns)
    //    13,      12,    2120,        50,    2169.99
    //    12,      11,    1060,        25,    2169.99
    //    11,      10,     509,        12,    2170.82
    //    10,       9,     255,         6,    2175.00
    //     9,       8,     127,         3,    2166.67
    //     8,       7,      85,         2,    2175.00

    reg    [7:0] phacc;     // phase accumulator
    reg    baudreg;

    initial
    begin
        phacc = 0;
    end

    always @(posedge clk)
    begin
        if (phacc[7] == 1)          // TESTBIT
        begin
            phacc <= phacc + 8'd85; // INITIAL
            baudreg <= 1;
        end
        else
        begin
            phacc <= phacc - 2;     // DECREMENT
            baudreg <= 0;
        end
    end

    assign baudout = baudreg;

endmodule


//
// Dual-Port RAM with synchronous Read
//
module dpram(clk,we,wa,wd,ra,rd);
    parameter LOGNPORT = 3;
    input    clk;                           // system clock
    input    we;                            // write strobe
    input    [`LB2BUFSZ-1:0] wa;            // write address
    input    [7:0] wd;                      // write data
    input    [`LB2BUFSZ-1:0] ra;            // read address
    output   [7:0] rd;                      // read data

    reg      [7:0] rdreg;
    reg      [7:0] ram [2047:0];

    always@(posedge clk)
    begin
        if (we)
            ram[wa] <= wd;
        rdreg <= ram[ra];
    end

    assign rd = rdreg;

endmodule


