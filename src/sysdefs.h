/////////////////////////////////////////////////////////////////////////
//  File: sysdefs.h     The globally visible definitions and default
//         values used in DPCore.
//
/////////////////////////////////////////////////////////////////////////

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
// *********************************************************

/////////////////////////////////////////////////////////////////////////
//
//  The protocol to the host consists of a command byte, two bytes of
//  register address, a word transfer count, and, if applicable, write
//  data.
//     The command has an operation (read, write, write-read), a word
//  length, the same/increment flag, the register/FIFO flag, and a bit
//  that is echoed back to the host.  Two bits in the command are
//  reserved for future use.
//
`define CMD_OP_FIELD      8'h0C
`define CMD_OP_READ       8'h04
`define CMD_OP_WRITE      8'h08
`define CMD_OP_WRRD       8'h30 
`define CMD_SAME_FIELD    8'h02
`define CMD_SAME_REG      8'h00
`define CMD_SUCC_REG      8'h02
`define CMD_LEN_FIELD     8'h01
`define CMD_WORD8         8'h00
`define CMD_WORD16        8'h01


/////////////////////////////////////////////////////////////////////////
//
//  The power states of the FPGA.  The Doze state turns off all peripherals
//  that have or require precise timing.  This include PWM inputs and
//  outputs, servo and H-bridge controllers, and all serial ports.  Doze
//  mode lowers the system clock down to 1000 Hertz.  This is high enough
//  to still accept read and write commands from the host computer.
//  The Sleep state has a 1000 Hz clock and turns off all peripherals
//  except the bus interface controllers which are required to bring it
//  out of the sleep state.  Reset forces all peripherals to reload their
//  default values and states.
`define SYS_FULLON        2'b11
`define SYS_DOZE          2'b10
`define SYS_SLEEP         2'b01
`define SYS_RESET         2'b00


// Force error when implicit net has no type.
//`default_nettype none
