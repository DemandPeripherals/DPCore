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
// See LICENSE.txt for more information.
// *********************************************************

//////////////////////////////////////////////////////////////////////////
//
//  File: servo4.v;   Four channel servo controller
//
//  Registers: (high byte)
//      Reg 0:  Servo channel 0 pulse width with a resolution of 50 ns.
//              The value in the register specifies the 50 ns count at
//              which the pin goes high.  The pin stays high until the
//              count reaches 2.5 milliseconds or a count of 50000 50
//              nanosecond pulses.  Thus to get a pulse width of 1.0 ms
//              you would subtract 1.0 from 2.5 giving how long the low
//              time should be.  The low time would be 1.5 ms or a count
//              of 30000 clock pulses, or a count of 16'h7530.
//      Reg 2:  Servo 1 low pulse width in units of 50 ns.
//      Reg 4:  Servo 2 low pulse width in units of 50 ns.
//      Reg 6:  Servo 3 low pulse width in units of 50 ns.
//
//  Each pulse is from 0 to 2.50 milliseconds.  The cycle time for
//  all four servoes is 20 milliseconds.
//
/////////////////////////////////////////////////////////////////////////
module servo4(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,servo);
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
    inout  [3:0] servo;      // Simple Bidirectional I/O 
 
    wire   myaddr;           // ==1 if a correct read/write on our address
    wire   [7:0] doutl;      // RAM output lines
    wire   [7:0] douth;      // RAM output lines
    wire   [3:0] raddr;      // RAM address lines
    wire   wclk;             // RAM write clock
    wire   wenl;             // Low RAM write enable
    wire   wenh;             // High RAM write enable
    reg    [2:0] servoid;    // Which servo has the clock
    reg    [15:0] servoclk;  // Comparison clock
    reg    val;              // Latched value of the comparison


    // Register array in RAM
    sv4ram16x8 freqramL(doutl,raddr,datin,wclk,wenl);
    sv4ram16x8 freqramH(douth,raddr,datin,wclk,wenh);


    always @(posedge clk)
    begin
        if (~(strobe & myaddr & ~rdwr))  // Only when the host is not writing our regs
        begin
            if (servoclk[15:0] == 49999)  // 2.500 ms @ 20 MHz
            begin
                val <= 0;
                servoclk <= 0;
                // 8 servos at 2.5 ms each is 20 ms
                servoid <= servoid + 3'h1;
            end
            else
            begin
                // check for a value match
                if ((doutl == servoclk[7:0]) && (douth == servoclk[15:8]))
                    val <= 1;

                servoclk <= servoclk + 16'h0001;   // increment PWM clock
            end
        end
    end


    // Assign the outputs.
    assign servo[3] = (servoid != 3) ? 1'b0 : val ;
    assign servo[2] = (servoid != 2) ? 1'b0 : val ;
    assign servo[1] = (servoid != 1) ? 1'b0 : val ;
    assign servo[0] = (servoid != 0) ? 1'b0 : val ;

    assign wclk  = clk;
    assign wenh  = (strobe & myaddr & ~rdwr & (addr[0] == 0)); // latch data on a write
    assign wenl  = (strobe & myaddr & ~rdwr & (addr[0] == 1)); // latch data on a write
    assign raddr = (strobe & myaddr) ? {2'h0,addr[2:1]} : {1'h0,servoid} ;

    assign myaddr = (addr[11:8] == our_addr) && (addr[7:3] == 0);
    assign datout = (~myaddr) ? datin :
                    (strobe & (addr[0] == 0)) ? douth :
                    (strobe & (addr[0] == 1)) ? doutl :
                    8'h00 ; 

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule


module sv4ram16x8(dout,addr,din,wclk,wen);
   output [7:0] dout;
   input  [3:0] addr;
   input  [7:0] din;
   input  wclk;
   input  wen;

   // RAM16X8S: 16 x 8 posedge write distributed (LUT) RAM
   //           Virtex-II/II-Pro
   // Xilinx HDL Language Template, version 10.1

   RAM16X8S #(
      .INIT_00(16'hffff), // INIT for bit 0 of RAM
      .INIT_01(16'hffff), // INIT for bit 1 of RAM
      .INIT_02(16'hffff), // INIT for bit 2 of RAM
      .INIT_03(16'hffff), // INIT for bit 3 of RAM
      .INIT_04(16'hffff), // INIT for bit 4 of RAM
      .INIT_05(16'hffff), // INIT for bit 5 of RAM
      .INIT_06(16'hffff), // INIT for bit 6 of RAM
      .INIT_07(16'hffff)  // INIT for bit 7 of RAM
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
