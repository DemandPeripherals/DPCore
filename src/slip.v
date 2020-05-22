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
//  File: slip.v:   A SLIP interface to an FT245
//  Description:  This modules converts the data stream to and from
//       a bus interface to a SLIP encoded data stream.  This module
//       sits between the FT245 USB interface and the bus interface
//       module.  Lines going to the bus interface are prefaces with
//       "bi" while those to the FT245 are prefaced with "ft".
//
/////////////////////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////////////////////
//
//  SLIP:
//      SLIP_END is decimal 192,  SLIP_ESC is decimal 219.
//  Rules:
//    -- Start and end a packet with END
//    -- In packet, replace END with ESC, 220
//    -- In packet, replace ESC with ESC, 221
//    -- Error on ESC not followed by 220 or 221, abort packet
//
`define SLIP_END             8'd192
`define SLIP_ESC             8'd219
`define INPKT_END            8'd220
`define INPKT_ESC            8'd221


/////////////////////////////////////////////////////////////////////////
//
//  There are really two separate state machines in this module, one for
//  the SLIP decoder and one for the SLIP encoder.  

//  The major states for the decoder are Waiting_For_Packet_End,
//  In_Packet, and In_ESC.  Waiting_For_Packet_End is the initial state
//  and is used to handle a protocol violations where we just want to
//  abort the current packet.
//
//  Waiting for the end of the current packet
`define HF_WT_END           0
//  In Packet waiting for RXF_ and the interface receiver to empty
`define HF_IN_PKT           1
//  In packet and got an ESC, get next character (should be 220 or 221)
`define HF_IN_ESC           2



//  The convention below is that "ft" refers to the FT245 side of the
//  interface, "bi" refers to the Bus Interface side, "hf" refers to
//  the host-to-FPGA direction, and "fh" refers to the FPGA-to-host
//  direction.  Basically we want to pass the fthf data to the bihf
//  side and the bifh data to the ftfh side.  
//
module slip(clk, fthfdata, fthfrxf_, fthfrd_, bihfdata, bihfrxf_, bihfrd_, bihfpkt,
            ftfhdata, ftfhtxe_, ftfhwr, bifhdata, bifhtxe_, bifhwr, bifhpkt);
    input  clk;              // system clock
    // FT245 side in the host-to-FPGA direction
    input  [7:0] fthfdata;   // Data in from the FT245
    input  fthfrxf_;         // Receiver full (not) at fthf port.  Data valid
    output fthfrd_;          // Read the new data, latch on clk rising edge
    // Bus Interface side in the host-to-FPGA direction
    output [7:0] bihfdata;   // Data out to the bus interface
    output bihfrxf_;         // Receiver full (not) at bihf port
    input  bihfrd_;          // Read the new data, latched on clk rising edge
    output bihfpkt;          // ==1 if in a packet.  Rising edge == new pkt
    // FT245 side in the FPGA-to-host direction
    output [7:0] ftfhdata;   // Data out to the FT245
    input  ftfhtxe_;         // Transmitter empty (not) at ftfh port
    output ftfhwr;           // Write the new data, latch on clk rising edge
    // Bus Interface side in the FPGA-to-host direction
    input  [7:0] bifhdata;   // Data in from the bus interface
    output bifhtxe_;         // Transmitter empty (not) at bifh port
    input  bifhwr;           // Take the new data, latched on clk rising edge
    input  bifhpkt;          // ==1 if in a packet.  Rising edge == new pkt

    reg  [1:0] hfstate;      // state of the host-to-FPGA data path

    initial
    begin
        hfstate = `HF_WT_END;    // clear out garbage in the USB fifo
    end


    //  The host-to-FPGA path has a SLIP decoder
    always @(posedge clk)
    begin
        //  Waiting for the end of the current packet
        if (hfstate == `HF_WT_END)
        begin
            if (fthfrxf_ == 0)
            begin
                hfstate <= (fthfdata == `SLIP_END) ? `HF_IN_PKT : `HF_WT_END;
            end
        end
        //  In Packet waiting for new character from the Host to the Fpga 
        if (hfstate == `HF_IN_PKT)
        begin
            if (fthfrxf_ == 0)
            begin
                if (fthfdata == `SLIP_ESC)
                    hfstate <= `HF_IN_ESC;
            end
        end
        //  In packet and got an ESC, get next character (should be 220 or 221)
        if (hfstate == `HF_IN_ESC)
        begin
            if (fthfrxf_ == 0)
            begin
                if ((fthfdata != `INPKT_END) && (fthfdata != `INPKT_ESC))
                begin
                    hfstate <= `HF_WT_END;
                end
                else
                    hfstate <= (bihfrd_ == 0) ? `HF_IN_PKT : `HF_IN_ESC;
            end
        end
    end

    assign bihfpkt = (((hfstate == `HF_IN_PKT) || (hfstate == `HF_IN_ESC)) && (fthfdata != `SLIP_END));
    assign bihfdata = (((hfstate == `HF_IN_ESC) && (fthfdata == `INPKT_END)) ?  `SLIP_END :
                       (((hfstate == `HF_IN_ESC) && (fthfdata == `INPKT_ESC)) ?  `SLIP_ESC :
                       fthfdata));
    assign fthfrd_ = ~((fthfrxf_ == 0) &&
                       ((hfstate == `HF_WT_END) ||
                        ((hfstate == `HF_IN_PKT) && (fthfdata == `SLIP_END)) ||
                        ((hfstate == `HF_IN_PKT) && (fthfdata == `SLIP_ESC)) ||
                        ((hfstate == `HF_IN_PKT) && (fthfdata != `SLIP_ESC) && (bihfrd_ == 0)) ||
                        ((hfstate == `HF_IN_ESC) && (fthfdata != `INPKT_END) && (fthfdata != `INPKT_ESC)) ||
                        ((hfstate == `HF_IN_ESC) && (fthfdata == `INPKT_END) && (bihfrd_ == 0)) ||
                        ((hfstate == `HF_IN_ESC) && (fthfdata == `INPKT_ESC) && (bihfrd_ == 0)) 
                       ));
    assign bihfrxf_ = ~(((fthfrxf_ == 0) && (hfstate == `HF_IN_PKT) && (fthfdata != `SLIP_ESC)
                                                                && (fthfdata != `SLIP_END)) ||
                        ((fthfrxf_ == 0) && (hfstate == `HF_IN_ESC) && (fthfdata == `INPKT_END)) ||
                        ((fthfrxf_ == 0) && (hfstate == `HF_IN_ESC) && (fthfdata == `INPKT_ESC)));



//////////////////////////////////////////////////////////////////////////
//
//  The encoder is completely separate from the decoder given above.  As
//  such we define all of the states and flow here.
//
//  The major states for the encoder are Waiting_For_Packet_Start,
//  In_Packet, and In_ESC.
//
//  Waiting for a packet start signal from the bus interface
`define FH_IDLE             0
//  In Packet waiting for a character from the bus interface
`define FH_WT_CHAR          1
//  Got a bus interface char and it requires an escape sequence
`define FH_SN_ESC           2
//  Lost the In_packet signal. Sending the SLIP_END terminator
`define FH_SN_END           3

//  These are the registers unique to the SLIP encoder
    reg  [2:0] fhstate;      // state of the FPGA-to-host data path
    reg  esctype;            // ==0 for ESC/END,  ==1 for ESC/ESC


    initial
    begin
        fhstate = `FH_IDLE;      // wait for new packet from the FPGA
    end

    always @(posedge clk)
    begin
        // input  [7:0] bifhdata;   // Data in from the bus interface
        // input  ftfhtxe_;         // Transmitter empty (not) at ftfh port
        // input  bifhpkt;          // ==1 if in a packet.  Rising edge == new pkt
        // input  bifhwr;           // Take the new data, latched on clk rising edge
        if (fhstate == `FH_IDLE)
        begin
            if ((bifhpkt == 1) && (ftfhtxe_ == 0))
            begin
                fhstate <= `FH_WT_CHAR;
            end
        end
        if (fhstate == `FH_WT_CHAR)
        begin
            if ((bifhwr == 1) && (ftfhtxe_ == 0)) // data to send but what kind?
            begin
                if (bifhdata == `SLIP_END)
                begin
                    esctype <= 1;    // ==1 for ESC/END
                    fhstate <= `FH_SN_ESC;      // sending escape sequence
                end
                else if (bifhdata == `SLIP_ESC)
                begin
                    esctype <= 0;    // ==0 for ESC/ESC
                    fhstate <= `FH_SN_ESC;      // sending escape sequence
                end
            end
            else if (bifhpkt == 0)
                fhstate <= `FH_SN_END;
        end
        if (fhstate == `FH_SN_ESC)               // Sending protocol character
        begin
            if (ftfhtxe_ == 0)
            begin
                fhstate <= `FH_WT_CHAR;
            end
        end
        if (fhstate == `FH_SN_END)               // Sending packet end character
        begin
            if (ftfhtxe_ == 0)
            begin
                fhstate <= `FH_IDLE;
            end
        end
    end

       // Data out to the FT245
    assign ftfhdata = ((fhstate == `FH_IDLE) && (bifhpkt == 1)) ? `SLIP_END :
                      (fhstate == `FH_SN_END) ? `SLIP_END :
                      ((fhstate == `FH_WT_CHAR) && 
                       ((bifhdata == `SLIP_END) || (bifhdata == `SLIP_ESC))) ? `SLIP_ESC :
                      ((fhstate == `FH_SN_ESC) && (esctype == 0)) ? `INPKT_ESC :
                      ((fhstate == `FH_SN_ESC) && (esctype == 1)) ? `INPKT_END :
                       bifhdata ;

           // Write the new data, latch on clk rising edge
    assign ftfhwr   = ((fhstate == `FH_IDLE) && (bifhpkt == 1) && (ftfhtxe_ == 0)) ||
                      ((fhstate == `FH_WT_CHAR) && (bifhwr == 1) && (ftfhtxe_ == 0)) ||
                      ((fhstate == `FH_SN_ESC) && (ftfhtxe_ == 0))  ||
                      ((fhstate == `FH_SN_END) && (ftfhtxe_ == 0)) ;

           // Transmitter empty (not) at bifh port
    assign bifhtxe_ = ~((ftfhtxe_ == 0) && ((fhstate == `FH_IDLE) || (fhstate == `FH_WT_CHAR)));

endmodule

