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
//  File: busif.v:   A bus interface.
//  Description:  This bus interface accepts command and data from
//       the host compute and translates those commands into reads
//       and writes onto the DPCore bus. 
//
/////////////////////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////////////////////
//
//  The protocol to the host consists of a command byte, two bytes of
//  register address, a word transfer count, and if applicable, write
//  data.  See the sysdefs.h file for a full description of the protocol.
//
//  At a high level the state machine for the bus interface gets the
//  four bytes mentioned above and does the read or write.  There are
//  major states as we get each of the three fields in the request and
//  several minor states as we deal with the control and status lines
//  to the host.
//
//  Get a host command from the host interface
`define BI_WT_CMD      0     // Wait for a new request on the  RXF_ line
`define BI_WT_HIAD     1     // Got RXF_ low and we lowered RD_, get high address byte
`define BI_WT_LOAD     2     // Got high addr, raised RD_, wait for RXF_ for low reg addr
`define BI_WT_WDCT     3     // Got low addr, raised RD_, wait for RXF_ for the word count

//  Doing a command.  Here are the states for both read and write processing
`define BI_SN_START    4     // Set the In_Pkt flag
`define BI_SN_CMD      5     // Echo/send the command byte back to the host
`define BI_SN_HIAD     6     // Send the high byte of the address
`define BI_SN_LOAD     7     // Send the low byte of the address
`define BI_SN_RCNT     8     // Send the Requested count
//  Doing a READ command.  Here are the states for read processing
`define BI_RD_WORD     9     // Read the data from the peripheral
`define BI_RD_LODA    10     // Send the low byte of the data
//  These states are also common for both reads and writes
`define BI_SN_DCNT    11     // Sent the "sent count" -- an error check for send count
`define BI_SN_END     12     // Send the SLIP END character -- lower InPkt

//  Doing a WRITE command.  Here are the states for write processing
//  We echo the command and give the number of words successfully written
`define BI_WR_LODA    13     // Wait for RXF_ to get the low data byte
`define BI_WR_WRIT    14     // Write the data to the peripheral
`define BI_WR_ABORT   15     // Abort the rest of the packet -- used on error

`define CMD_OP_FIELD      8'h0C
`define CMD_OP_READ       8'h04
`define CMD_OP_WRITE      8'h08
`define CMD_OP_WRRD       8'h30 
`define CMD_SAME_FIELD    8'h02
`define CMD_SAME_REG      8'h00
`define CMD_SUCC_REG      8'h02


module busif(clk, phydatin, phyrxf_, phyrd_, pkt_in, phydatout,
    phytxe_, phywr, pkt_out, addr, datout, rdwr, strobe, busy, u100clk,
    addr_match, datin);
    // Lines to and from the bus controller
    input  clk;              // 50MHz system clock
    // Lines to and from the physical (slip) interface
    input  [7:0] phydatin;   // Data from the physical interface
    input  phyrxf_;          // Data available if low
    output phyrd_;           // Get data from bus when low
    input  pkt_in;           // High if we're receiving a packet
    output [7:0] phydatout;  // Data toward the physical interface
    input  phytxe_;          // Able to send new data if low
    output phywr;            // Write data on positive edge
    output pkt_out;          // High when we want to send a packet
    // Lines to and from the peripherals
    output [11:0] addr;      // address of target peripheral
    output [7:0] datout;     // Data OUT to the peripherals
    output rdwr;             // direction of this transfer. Read=1; Write=0
    output strobe;           // true on full valid command
    input  busy;             // ==1 if target peripheral is busy
    input  u100clk;          // ==1 if it's time to start a peripheral poll cycle
    input  addr_match;       // ==1 if target peripheral claims the address
    input  [7:0] datin;      // Data INto the bus interface;


    reg  [3:0] state;        // state of the interface
    reg  [7:0] cmd;          // The command for this request
    reg  [11:0] paddr;       // The peripheral address of the target
    reg  [7:0] count;        // The number of words to transfer
    reg  sendingpkt;         // Set high when we are sending a packet.
    reg  [7:0] data;         // The data to/from the peripheral
    reg  [3:0] polladdr;     // Poll address.  Cycle to each peripheral asking for new data

    initial
    begin
        state = `BI_WT_CMD;
        sendingpkt = 0;
        polladdr = 0;
    end


    always @(posedge clk)
    begin
        // trigger peripheral poll outside of main bus state machine.
        if ((u100clk == 1) && (polladdr == 0))
            polladdr <= 4'hf;

        // Main bus state machine .....
        if (state == `BI_WT_CMD)    // Idle.  Waiting for a new command from the host
        begin
            if (pkt_in && (phyrxf_ == 0))
            begin
                // set phyrd_ = 0
                cmd <= phydatin;
                state <= `BI_WT_HIAD;
                // Sanity check.  Command must be either a read or write
                if (((phydatin & 8'hfd) != 8'hf8) && ((phydatin & 8'hfd) != 8'hf4))
                begin
                    state <= `BI_WR_ABORT;
                end
            end
            else
            begin
                //  This is where we do the background polling for new data
                //  from the peripherals that needs to be sent up to the host
                if ((polladdr != 0) && (sendingpkt == 0))
                begin
                    // Any bytes to transfer up to the host?
                    if (datin != 0)
                    begin
                        cmd <= 8'h46;
                        count <= datin[7:0];
                        state <= `BI_SN_START;
                        sendingpkt <= 1;
                    end
                    else  // No new data at that address, try the next
                    begin
                        paddr[11:8] <= polladdr;
                        polladdr <= polladdr - 4'h1;
                    end
                    paddr[7:0] <= 0;
                end
            end
        end
        else if (state == `BI_WT_HIAD)   // Got a command.  Get the high address
        begin
            if (pkt_in && (phyrxf_ == 0))
            begin
                // set phyrd_ = 0
                paddr[11:8] <= phydatin[3:0];
                state <= `BI_WT_LOAD;
                if (phydatin[7:4] != 4'he)  // another sanity check
                begin
                    state <= `BI_WR_ABORT;
                end
            end
            else if (pkt_in == 0)   // abort on loss of incoming packet
            begin
                state <= `BI_WT_CMD;
            end
        end
        else if (state == `BI_WT_LOAD)   // Got the high address.  Get the low address
        begin
            if (pkt_in && (phyrxf_ == 0))
            begin
                // set phyrd_ = 0
                paddr[7:0] <= phydatin;
                state <= `BI_WT_WDCT;
            end
            else if (pkt_in == 0)   // abort on loss of incoming packet
            begin
                state <= `BI_WT_CMD;
            end
        end
        else if (state == `BI_WT_WDCT)   // Got the full address. Get the send count
        begin
            if (pkt_in && (phyrxf_ == 0))
            begin
                count <= phydatin;
                state <= `BI_SN_START;
            end
            else if (pkt_in == 0)   // abort on loss of incoming packet
            begin
                state <= `BI_WT_CMD;
            end
        end
        // Both reads and writes have the command echoed back to the host
        else if (state == `BI_SN_START)  // Set the In_Pkt flag, the SLIP_END character
        begin
            if (phytxe_ == 0)
            begin
                sendingpkt <= 1;
                state <= `BI_SN_CMD;
            end
        end
        else if (state == `BI_SN_CMD)    // Echo/send the command byte back to the host
        begin
            if (phytxe_ == 0)
            begin
                state <= `BI_SN_HIAD;
            end
        end
        else if (state == `BI_SN_HIAD)   // Send the high byte of the address
        begin
            if (phytxe_ == 0)
            begin
                state <= `BI_SN_LOAD;
            end
        end
        else if (state == `BI_SN_LOAD)   // Send the low byte of the address
        begin
            if (phytxe_ == 0)
                state <= `BI_SN_RCNT;
            begin
            end
        end
        else if (state == `BI_SN_RCNT)   // Send the Requested count
        begin
            if (phytxe_ == 0)
            begin
                // Switch on the command type to get to the next state 
                if ((cmd & `CMD_OP_FIELD) == `CMD_OP_READ)
                    state <= `BI_RD_WORD;    // go read the data from the peripheral
                else if ((cmd & `CMD_OP_FIELD) == `CMD_OP_WRITE)
                    //state <= ((cmd & `CMD_LEN_FIELD) == `CMD_WORD16) ? `BI_WR_HIDA : `BI_WR_LODA;
                    state <= `BI_WR_LODA;
                else
                    state <= `BI_SN_DCNT;    // Hmmm, a no-op
            end
        end

        ////////////////////////////////////////////////////////////////////////////
        // We have a READ command.  Handle it in this part of the state machine
        else if (state == `BI_RD_WORD)   // Read the data from the peripheral
        begin
            // get data from the peripheral.  Watch for busy and valid_address flags
            data <= datin;
            if (busy == 1)
                state <= `BI_RD_WORD;
            else if (count == 0)   // ALL DONE ???
                state <= `BI_SN_DCNT;
            else if (addr_match == 0)
                state <= `BI_SN_DCNT;
            else
                state <= `BI_RD_LODA;
        end
        else if (state == `BI_RD_LODA)   // Send the low byte of the data
        begin
            if (phytxe_ == 0)
            begin
                state <= `BI_RD_WORD;
                count <= count - 8'h01;
                if ((cmd & `CMD_SAME_FIELD) == `CMD_SUCC_REG)
                    paddr <= paddr + 12'h001;
            end
        end

        ////////////////////////////////////////////////////////////////////////////
        // We have a WRITE command.  Handle it in this part of the state machine
        else if (state == `BI_WR_LODA)   // Get the low byte of the data
        begin
            if (pkt_in && (phyrxf_ == 0))
            begin
                // set phyrd_ = 0
                data[7:0] <= phydatin;
                state <= `BI_WR_WRIT;
            end
            else if (pkt_in == 0)   // abort on loss of incoming packet
            begin
                state <= `BI_SN_END;
            end
        end
        else if (state == `BI_WR_WRIT)   // Do the write to the peripheral
        begin
            // write data to the peripheral.  Watch for busy and valid_address flags
            if (busy == 1)
                state <= `BI_WR_WRIT;
            else if (addr_match == 0)
                state <= `BI_WR_ABORT;
            else
            begin
                count <= count - 8'h01;
                if (count == 1)   // ALL DONE ???
                    state <= `BI_SN_DCNT;
                //else if ((cmd & `CMD_LEN_FIELD) == `CMD_WORD16)
                //begin
                    //state <= `BI_WR_HIDA;
                    //if ((cmd & `CMD_SAME_FIELD) == `CMD_SUCC_REG)
                        //paddr <= paddr + 2;
                //end
                else
                begin
                    state <= `BI_WR_LODA;
                    if ((cmd & `CMD_SAME_FIELD) == `CMD_SUCC_REG)
                        paddr <= paddr + 12'h001;
                end
            end
        end
        else if (state == `BI_WR_ABORT)
        begin              // Aborting the write -- read and discard rest of input pkt
            if (pkt_in && (phyrxf_ == 0))
            begin
                // set phyrd_ = 0
                data[7:0] <= phydatin;   // really just a no-op
            end
            else if (pkt_in == 0)   // Done. Go send the data count
            begin
                state <= `BI_SN_DCNT;
            end
        end

        // Both reads and write end with a send of the processed word count
        else if (state == `BI_SN_DCNT)   // Sent the "did count" -- an error check for request count
        begin
            if (phytxe_ == 0)
            begin
                state <= `BI_SN_END;
            end
        end
        else if (state == `BI_SN_END)    // Send the SLIP END character -- lower InPkt
        begin
            if (phytxe_ == 0)
            begin
                sendingpkt <= 0;
                state <= `BI_WT_CMD;
            end
        end
    end


    // Deal with the output lines toward the USB receiver
    assign phyrd_ = ~(pkt_in && (phyrxf_ == 0) &&
                 ((state == `BI_WT_CMD) || (state == `BI_WT_HIAD) || (state == `BI_WT_LOAD) ||
                  //(state == `BI_WT_WDCT) || (state == `BI_WR_HIDA) ||(state == `BI_WR_LODA) ||
                  (state == `BI_WT_WDCT) || (state == `BI_WR_LODA) ||
                  (state == `BI_WR_ABORT)));
    assign pkt_out = sendingpkt || ((state == `BI_SN_START) && (phytxe_ == 0));

    // Deal with the output lines toward the USB transmitter
    assign phydatout = (state == `BI_SN_CMD) ? cmd :
                       (state == `BI_SN_HIAD) ? {4'he,paddr[11:8]} :
                       (state == `BI_SN_LOAD) ? paddr[7:0] :
                       (state == `BI_SN_RCNT) ? count :
                       (state == `BI_RD_LODA) ? data[7:0] :
                       (state == `BI_SN_DCNT) ? count : 8'h00;
    assign phywr = ((phytxe_ == 0) && ((state == `BI_SN_CMD) || (state == `BI_SN_HIAD) ||
                                       (state == `BI_SN_LOAD) || (state == `BI_SN_RCNT) ||
                                       //(state == `BI_RD_HIDA) || (state == `BI_RD_LODA) ||
                                       (state == `BI_RD_LODA) ||
                                       (state == `BI_SN_DCNT)));

    // Deal with output lines to the peripherals
    assign addr = paddr;      // address of target peripheral
    assign datout = (state == `BI_WR_WRIT) ? data : 8'h00;     // Data OUT to the peripherals
    assign rdwr = (state == `BI_RD_WORD);
    assign strobe = (((state == `BI_RD_WORD) || (state == `BI_WR_WRIT)) && (count != 0));

endmodule



