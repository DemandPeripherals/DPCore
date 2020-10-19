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
//  File: stepu.v;   A unipolar stepper controller.
//
//      This design has a read/write register for the number of steps to go,
//  a read/write register for step rate (step period actually), a read/write
//  flag to indicate full or half steps, and a write-only register that adds
//  or removes steps from the target step count.
//      The hardware outputs go to each of the four windings on the stepper.
//
//  Outputs are inverted to match the power-on state of the FPGA.  The outputs
//  are as follows for full and half steps (without output inverters):
//
//  Full Step
//    phac[1:0]  Coil A  B  C  D
//           0        1  1  0  0
//           1        0  1  1  0
//           2        0  0  1  1
//           3        1  0  0  1
//
//
//  Half Step
//    phac[2:0]  Coil A  B  C  D
//           0        1  1  0  0
//           1        0  1  0  0
//           2        0  1  1  0
//           3        0  0  1  0
//           4        0  0  1  1
//           5        0  0  0  1
//           6        1  0  0  1
//           7        1  0  0  0
//
//  Registers are (high byte)
//    Addr=0    12 bit target step count, decremented to zero
//    Addr=2    12 bit value synchronously added to the target, write only
//    Addr=4    High 5 bits are the setup, low 8 bits are the period
//    Addr=6    Low 7 bits are the holding current PWM value
//
//  The setup register has the following bits
//   Bit 12   on/off     1==on
//   Bit 11   direction  1==abcd, 0=dcba
//   Bit 10   half/full  1==half
//   bit 9,8  00         period clock is 1 microsecond
//            01         period clock is 10 microseconds
//            10         period clock is 100 microseconds
//            11         period clock is 1 millisecond
//
/////////////////////////////////////////////////////////////////////////
module stepu(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,
       m1clk, u100clk, u10clk, u1clk,coila,coilb,coilc,coild);
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
    input  m1clk;            // Millisecond clock pulse
    input  u100clk;          // 100 microsecond clock pulse
    input  u10clk;           // 10 microsecond clock pulse
    input  u1clk;            // 1 microsecond clock pulse
    output coila;            // Output for coil #A
    output coilb;            // Output for coil #B
    output coilc;            // Output for coil #C
    output coild;            // Output for coil #D
 
    wire   myaddr;           // ==1 if a correct read/write on our address
    reg    [11:0] target;    // Step target.
    reg    [7:0] period;     // Inter-step period
    reg    [4:0] setup;      // Setup has on/off, direction, half/full steps, and frequency selector
    wire   onoff,dir;        // on/off and direction
    wire   full,half;        // indicators for full or half steps
    reg    [7:0] pdiv;       // period clock divider and holding PWM counter
    wire   pclk;             // period input clock
    reg    [2:0] phac;       // phase accumulator -- actual stepper position
    reg    [6:0] holding;    // holding current as a 7 bit number


    assign onoff = setup[4]; // on/off bit
    assign dir   = setup[3];
    assign full = onoff & (~setup[2]);
    assign half = onoff & setup[2];
    assign pclk = (setup[1:0] == 0) ? u1clk :
                  (setup[1:0] == 1) ? u10clk :
                  (setup[1:0] == 2) ? u100clk : m1clk ;

    initial
    begin
        target = 0;
        period = 8'hff;
        setup = 0;
        phac = 0;
    end

    always @(posedge clk)
    begin
        if (strobe & myaddr & ~rdwr)  // latch data on a write
        begin
            if (addr[2:0] == 0)
                target[11:8] <= datin[3:0];
            else if (addr[2:0] == 1)
                target[7:0] <= datin[7:0];
            else if (addr[2:0] == 2)
                target[11:8] <= target[11:8] + datin[3:0];
            else if (addr[2:0] == 3)
                target <= target + {4'h0,datin[7:0]};
            else if (addr[2:0] == 4)
                setup <= datin[4:0];
            else if (addr[2:0] == 5)
                period <= datin[7:0];
            //else if (addr[2:0] == 6) //not used
            else if (addr[2:0] == 7)
                holding <= datin[6:0];
        end
        else if ((target != 0) && pclk && (onoff == 1))  // Decrement the period counter
        begin
            if (pdiv == 0)
            begin
                pdiv <= period;
                target <= target - 12'h001;
                if (half)
                    phac <= (dir) ? phac + 3'h1 : phac - 3'h1;
                else
                    phac <= (dir) ? phac + 3'h2 : phac - 3'h2;
            end
            else
                pdiv <= pdiv - 8'h01;
        end
        else if (u1clk && (target == 0))    // apply holding current
        begin
            pdiv <= pdiv - 8'h01;
        end
    end

    // Assign the outputs.  See the full/half tables at the top of this file
    // Outputs are inverted to match the power-on state of the FPGA
    assign coila = ~(((target != 0) || ((target == 0) && (pdiv[6:0] < holding))) &&
                   (((full) && ((phac[2:1] == 0) || (phac[2:1] == 3))) ||
                   ((half) && ((phac[2:0] == 0) || (phac[2:0] == 6) || (phac[2:0] == 7)))));
    assign coilb = ~(((target != 0) || ((target == 0) && (pdiv[6:0] < holding))) &&
                   (((full) && ((phac[2:1] == 0) || (phac[2:1] == 1))) ||
                   ((half) && ((phac[2:0] == 0) || (phac[2:0] == 1) || (phac[2:0] == 2)))));
    assign coilc = ~(((target != 0) || ((target == 0) && (pdiv[6:0] < holding))) &&
                   (((full) && ((phac[2:1] == 1) || (phac[2:1] == 2))) ||
                   ((half) && ((phac[2:0] == 2) || (phac[2:0] == 3) || (phac[2:0] == 4)))));
    assign coild = ~(((target != 0) || ((target == 0) && (pdiv[6:0] < holding))) &&
                   (((full) && ((phac[2:1] == 2) || (phac[2:1] == 3))) ||
                   ((half) && ((phac[2:0] == 4) || (phac[2:0] == 5) || (phac[2:0] == 6)))));
 
    assign myaddr = (addr[11:8] == our_addr) && (addr[7:3] == 0);
    assign datout = (~myaddr || ~rdwr) ? datin : 
                     (addr[2:0] == 0) ? {4'h0,target[11:8]} :
                     (addr[2:0] == 1) ? target[7:0] :
                     (addr[2:0] == 2) ? 8'h00 :   // Nothing to report for the increment register
                     (addr[2:0] == 3) ? 8'h00 :
                     (addr[2:0] == 4) ? {3'h0,setup} :
                     (addr[2:0] == 5) ? period :
                     (addr[2:0] == 6) ? 8'h00 :
                     (addr[2:0] == 7) ? {1'h0,holding} :
                     8'h00;

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    assign addr_match_out = myaddr | addr_match_in;

endmodule

