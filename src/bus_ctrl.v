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
//  File: bus_ctrl.v;   Bus control unit.
//  Description:  This generates the clocks and other lines used by all
//     of the peripherals. 
// 
/////////////////////////////////////////////////////////////////////////
//    As stated above, the bus control unit generates the common clocks
//  and signals used by most of the peripherals.  Specifically, it
//  generates the following:
//  
//  CLOCKS:
//  - sysclk: the basic system clock.  This can be the input 12.5 MHz clock
//    or, if in a sleep mode, a 1000 Hz clock.
//  - baudclk: this is the 8x over-sampling clock for the serial ports.
//    It is about 8x115200 or about 921600 Hertz. (not currently implemented)
//  - m100-u1: these are clock that can be used as the basis for longer time
//    delays in the system.
//  - pollevt; set equal 1 for one clock cycle at the start of a peripheral
//    poll for data to send up to the host.  The default is 4 milliseconds per
//    poll;
`define POLLTIME 3
//  
//  BUS CONTROL:
//  - bmaddr: The bus master address is a continuously increment 3 bit
//    counter.  The eight states of the counter each correspond to a bus
//    interface unit.  For example, the USB bus interface gets one address
//    from the eight and will only do bus transactions when its address
//    is selected.  This lets us have multiple bus masters and lets us
//    have peripheral-to-peripheral transfers.  (not implemented yet)
//  
//  SYSTEM CONTROL:
//  - mode: These two pins contain the mode of operation for the FPGA.
//    Mode 00 is system reset.  Mode 01 is sleep mode in which nothing
//    is running except the USB bus interface which is used to take it
//    out of sleep mode.  Mode 10 is doze mode in which the system clock
//    is 100 KHz and all peripherals which require precise timing are off.
//    Mode 11 is the full run mode.  The desired state has to come from
//    somewhere and it now comes from two input lines.  (not implemented yet)
//
/////////////////////////////////////////////////////////////////////////

module bus_ctrl(ck12, sysclk, pollevt, s1, m100, m10, m1, u100, u10, u1, n100);
    input ck12;          // 12.5 MHz input clock
    output sysclk;       // the global system clock
    output pollevt;      // time to poll peripherals for data to the host
    output s1;           // utility 1.000 second pulse
    output m100;         // utility 100.0 millisecond pulse
    output m10;          // utility 10.00 millisecond pulse
    output m1;           // utility 1.000 millisecond pulse
    output u100;         // utility 100.0 microsecond pulse
    output u10;          // utility 10.00 microsecond pulse
    output u1;           // utility 1.000 microsecond pulse
    output n100;         // utility 100.0 nanosecond pulse

    reg [1:0] n100div;   // 100 nanosecond divider
    reg [3:0] u1div;     // 1 microsecond divider
    reg [3:0] u10div;    // 10 microsecond divider
    reg [3:0] u100div;   // 100 microsecond divider
    reg [3:0] m1div;     // millisecond divider
    reg [2:0] polltmr;   // poll timer divider
    reg [3:0] m10div;    // 10 millisecond divider
    reg [3:0] m100div;   // 100 millisecond divider
    reg [3:0] s1div;     // 1 second divider
    reg n100pul;         // 100 nanosecond pulse
    reg u1pul;           // 1 microsecond pulse
    reg u10pul;          // 10 microsecond pulse
    reg u100pul;         // 100 microsecond pulse
    reg m1pul;           // millisecond pulse
    reg pollpul;         // poll event pulse
    reg m10pul;          // 10 millisecond pulse
    reg m100pul;         // 100 millisecond pulse
    reg s1pul;           // 1 second pulse
    wire ck20;           // the 20 MHz clock


    // Generate the 20 MHz clock from the 12.5 one
    clk12to20 get20(ck12, ck20);

    always @(posedge sysclk)
    begin
        if (n100div == 0)
        begin
            n100div <= 2'h1;
            n100pul <= 1'h1;
        end
        else
        begin
            n100div <= n100div - 2'h1;
            n100pul <= 1'h0;
        end

        if (n100pul)
        begin
            if (u1div == 4'h0)
            begin
                u1div <= 4'h9;
                u1pul <= 1'h1;
            end
            else
                u1div <= u1div - 4'h1;
        end
        else
            u1pul <= 1'h0;

        if (u1pul)
        begin
            if (u10div == 4'h0)
            begin
                u10div <= 4'h9;
                u10pul <= 1'h1;
            end
            else
                u10div <= u10div - 4'h1;
        end
        else
            u10pul <= 1'h0;

        if (u10pul)
        begin
            if (u100div == 4'h0)
            begin
                u100div <= 4'h9;
                u100pul <= 1'h1;
            end
            else
                u100div <= u100div - 4'h1;
        end
        else
            u100pul <= 1'h0;

        if (u100pul)
        begin
            if (m1div == 4'h0)
            begin
                m1div <= 4'h9;
                m1pul <= 1'h1;
            end
            else
                m1div <= m1div - 4'h1;
        end
        else
            m1pul <= 1'h0;

        if (m1pul)
        begin
            if (m10div == 4'h0)
            begin
                m10div <= 4'h9;
                m10pul <= 1'h1;
            end
            else
                m10div <= m10div - 4'h1;
        end
        else
            m10pul <= 1'h0;

        // poll timer is in units of milliseconds
        if (m1pul)
        begin
            if (polltmr == 3'h0)
            begin
                polltmr <= `POLLTIME;
                pollpul <= 3'h1;
            end
            else
                polltmr <= polltmr - 3'h1;
        end
        else
            pollpul <= 1'h0;

        if (m10pul)
        begin
            if (m100div == 4'h0)
            begin
                m100div <= 4'h9;
                m100pul <= 1'h1;
            end
            else
                m100div <= m100div - 4'h1;
        end
        else
            m100pul <= 1'h0;

        if (m100pul)
        begin
            if (s1div == 4'h0)
            begin
                s1div <= 4'h9;
                s1pul <= 1'h1;
            end
            else
                s1div <= s1div - 4'h1;
        end
        else
            s1pul <= 1'h0;
    end

    // Put the system clock on a global clock line, 20 MHz
    BUFG bufg_clk (.I(ck20), .O(sysclk));
    BUFG bufg_n100clk (.I(n100pul), .O(n100));
    BUFG bufg_u1clk (.I(u1pul), .O(u1));
    BUFG bufg_u10clk (.I(u10pul), .O(u10));
    BUFG bufg_u100clk (.I(u100pul), .O(u100));
    BUFG bufg_m1clk (.I(m1pul), .O(m1));
    BUFG bufg_m10clk (.I(m10pul), .O(m10));
    BUFG bufg_m100clk (.I(m100pul), .O(m100));
    BUFG bufg_s1clk (.I(s1pul), .O(s1));
    BUFG bufg_pollevt (.I(pollpul), .O(pollevt));

endmodule


//////////////////////////////////////////////////////////////////////////
//
// clk12to20() generates a 20 MHz clock from a 12.5 MHz one.
//
module clk12to20(CLKIN_IN, CLKFX_OUT);
    input CLKIN_IN;
    output CLKFX_OUT;
 
    wire CLKFX_BUF;
    wire GND_BIT;
    assign GND_BIT = 1'b0;
    assign CLKFX_OUT = CLKFX_BUF;

   DCM_SP #(
      .CLKDV_DIVIDE(5.0),          // Divide by: 1.5,2.0,2.5,3.0,3.5,4.0,4.5,5.0,5.5,6.0,6.5
                                   //   7.0,7.5,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0 or 16.0
      .CLKFX_DIVIDE(5),            // Can be any integer from 1 to 32
      .CLKFX_MULTIPLY(8),          // Can be any integer from 2 to 32
      .CLKIN_DIVIDE_BY_2("FALSE"), // TRUE/FALSE to enable CLKIN divide by two feature
      .CLKIN_PERIOD(60.0),         // Specify period of input clock
      .CLKOUT_PHASE_SHIFT("NONE"), // Specify phase shift of NONE, FIXED or VARIABLE
      .CLK_FEEDBACK("NONE"),         // Specify clock feedback of NONE, 1X or 2X
      .DESKEW_ADJUST("SYSTEM_SYNCHRONOUS"), // SOURCE_SYNCHRONOUS, SYSTEM_SYNCHRONOUS or
                                            //   an integer from 0 to 15
      .DFS_FREQUENCY_MODE("HIGH"),  // HIGH or LOW frequency mode for frequency synthesis
      .DLL_FREQUENCY_MODE("HIGH"),  // HIGH or LOW frequency mode for DLL
      .DUTY_CYCLE_CORRECTION("TRUE"), // Duty cycle correction, TRUE or FALSE
      .FACTORY_JF(16'hC080),        // FACTORY JF values
      .PHASE_SHIFT(0),             // Amount of fixed phase shift from -255 to 255
      .STARTUP_WAIT("FALSE")       // Delay configuration DONE until DCM LOCK, TRUE/FALSE
   ) DCM_SP_inst (
      .CLK0(),                     // 0 degree DCM CLK output
      .CLK180(),                   // 180 degree DCM CLK output
      .CLK270(),                   // 270 degree DCM CLK output
      .CLK2X(),                    // 2X DCM CLK output
      .CLK2X180(),                 // 2X, 180 degree DCM CLK out
      .CLK90(),                    // 90 degree DCM CLK output
      .CLKDV(),                    // Divided DCM CLK out (CLKDV_DIVIDE)
      .CLKFX(CLKFX_BUF),           // DCM CLK synthesis out (M/D)
      .CLKFX180(),                 // 180 degree CLK synthesis out
      .LOCKED(),                   // DCM LOCK status output
      .PSDONE(),                   // Dynamic phase adjust done output
      .STATUS(),                   // 8-bit DCM status bits output
      .CLKFB(),                    // DCM clock feedback
      .CLKIN(CLKIN_IN),            // Clock input (from IBUFG, BUFG or DCM)
      .PSCLK(1'b0),                // Dynamic phase adjust clock input
      .PSEN(1'b0),                 // Dynamic phase adjust enable input
      .PSINCDEC(1'b0),             // Dynamic phase adjust increment/decrement
      .RST(1'b0)                   // DCM asynchronous reset input
   );

   // End of DCM_SP_inst instantiation
endmodule
