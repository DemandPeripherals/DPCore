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
//  File: ft245.v:   An interface to the FTDI FT245 USB interface.
//  Description:  This module provides an interface to the FT245.  
//       There are separate interfaces for the transmit (bus-phy)
//       and receive (phy-bus) data paths.  
//       We use the nomenclature of the FT245 to provide consistency.
//
/////////////////////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////////////////////
//  Design notes:
//  - The requirement is that we be able to get or send a byte within 8
//    clock cycles.  Doing so means we can saturate a full-speed USB 
//    device.  There is a lot of possibility for going faster ...
//  - Let a write cycle start directly from the RD_T2 state
//  - Do not latch the data going to the bus interface.  Let the bus
//    interface get it directly from the USB port. 
/////////////////////////////////////////////////////////////////////////


// A state machine does the arbitration and locking for access to the
// shared USB data bus.  The states are BUS_IDLE and various states for
// both a read cycle and a write cycle.  Once a read or write is started
// it is driven to completion.   The various "Tx" states refer to the
// timing diagrams for the FT245 reads and writes.
`define IDLE_BUS    0
`define RX_T1       1
`define RX_T2       2
`define TX_T7       3
`define TX_T8       4

module ft245(clk, phydata, phyrd_, phyrxf_, phytxe_, phywr,
             ifdatout, ifrxf_, ifrd_, ifdatin, iftxe_, ifwr, debug0);
    input   clk;            // system clock
    inout   [7:0] phydata;  // FT245 8 bit data bus
    output  phyrd_;         // active low read signal
    input   phyrxf_;        // receiver has data (not)
    input   phytxe_;        // transmitter buffer empty (not)
    output  phywr;          // active negative edge write signal
    output  [7:0] ifdatout; // data toward the FPGA bus interface
    output  ifrxf_;         // New data for the bus interface (not)
    input   ifrd_;          // data taken (not) on next posedge of clk
    input   [7:0] ifdatin;  // data toward the USB interface
    output  iftxe_;         // transmitter empty (not)
    input   ifwr;           // write new ifdata on next posedge of clk
    output  [15:0] debug0;

    // Control the direction of the bidirectional USB data lines and
    // the state of the read or write.
    reg     [2:0] busstate; // Idle, read, or write.
    reg     [2:0] delay;    // In-state delay counter

    // Registers for the data bytes to/from the bus interface
    reg     [7:0] rxdata;   // registered data for the bus interface
    reg     rxf;            // ==1 when the above register has data
    reg     [7:0] txdata;   // registered data from the bus interface
    reg     txe;            // ==1 when the above register is empty

    // Bring external signal into our clock domain
    reg     phyrxf_1;
    reg     phyrxf_2;
    reg     phytxe_1;
    reg     phytxe_2;


    initial
    begin
        rxf = 0;                // no data from the host
        txe = 1;                // no data to send to the host
        busstate = `IDLE_BUS;   // idle
        delay = 0;
    end

    always @(posedge clk)
    begin
        // Bring external lines into our clock domain.
        phyrxf_1 <= phyrxf_;
        phyrxf_2 <= phyrxf_1;
        phytxe_1 <= phytxe_;
        phytxe_2 <= phytxe_1;

        if (busstate == `IDLE_BUS)
        begin
            if ((phytxe_2 == 0) && (txe == 0))
            begin   // character to send and room to send it.  Switch to Xmit state machine
                delay <= 3'h3;
                busstate <= `TX_T7;
            end
            else if ((phyrxf_2 == 0) && (rxf == 0))
            begin   // receiving a new character.  Switch to Receive state machine
                delay <= 3'h2;
                busstate <= `RX_T1;
            end
        end
        if (busstate == `RX_T1)
        begin
            if (delay == 3'h0)   // data valid at end of T1 
            begin
                delay <= 3'h6;   // 120 ns at 50 MHz (+20ns for the Idle state)
                busstate <= `RX_T2;
                rxdata <= phydata;
                rxf <= 1;
            end
            else
                delay <= delay - 3'h1;
        end
        if (busstate == `RX_T2)
        begin
            if (delay == 3'h0)   // Go to IDLE at end of delay
            begin
                busstate <= `IDLE_BUS;
            end
            else
                delay <= delay - 3'h1;
        end
        if (busstate == `TX_T7)  // sending a character up to the host
        begin
            if (delay == 3'h0)   // data valid at end of T7 
            begin
                delay <= 3'h3;   // 60 ns at 50 MHz (+20ns for the Idle state)
                busstate <= `TX_T8;
            end
            else
                delay <= delay - 3'h1;
        end
        if (busstate == `TX_T8)
        begin
            if (delay == 3'h0)   // Go to IDLE at end of delay
            begin
                busstate <= `IDLE_BUS;
                txe <= 1;
            end
            else
                delay <= delay - 3'h1;
        end

        // rd_ low means the data is accepted on the next clk
        if (ifrd_ == 0)
        begin
            rxf <= 0;
        end

        // Latch the data from the bus interface on the next clk
        // if ifwr is high
        if (ifwr == 1)
        begin
            txdata <= ifdatin;
            txe <= 0;
        end
    end

    assign phyrd_ = ~(((busstate == `IDLE_BUS) && ~phyrxf_2 && ~rxf) ||
                      (busstate == `RX_T1));
    assign phywr  =  (((busstate == `IDLE_BUS) && ~phytxe_2 && ~txe) ||
                      (busstate == `TX_T7));
    assign phydata = (phywr) ? txdata : 8'bz;
    assign iftxe_ = ~txe;
    assign ifrxf_ = ~rxf;
    assign ifdatout = rxdata;


    assign debug0[3:0] = busstate;
    assign debug0[4] = rxf;
    assign debug0[5] = phyrxf_2;
    assign debug0[6] = txe;
    assign debug0[7] = phytxe_2;
    assign debug0[15:8] = txdata;




    endmodule
