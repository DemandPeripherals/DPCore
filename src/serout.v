//////////////////////////////////////////////////////////////////////////
//
//  File: serialout: Quad/Octal serial output port
//
//  Registers are (for quad port)
//    Addr=0    Data Out port #1
//    Addr=1    Data Out port #2
//    Addr=2    Data Out port #3
//    Addr=3    Data Out port #4
//    Addr=4    Baud rate divider
//
// NOTES:  The FIFO buffers are implemented using one dual-port
// block RAM.   The only write source is the host.  Depending on
// the activity all of the ports may try to read the RAM at the
// baud clock edge.  To resolve the conflicting read access we use
// a counter (rdsel) that sequentially gives two sysclk cycles to
// each  port.  The RAM read address is set in the first cycle and
// the character to send is read from RAM in the second cycle.  This
// counter has 3/4 bits -- two/three for the port and 1 for the
// addr/read cycle.
//
/////////////////////////////////////////////////////////////////////////

        // Log Base 2 of the buffer size for each port.  Should be betwee
        // 4 and 8.  Larger values ease the load on the USB port by sending
        // fuller USB packets.  Smaller buffers ease the FPGA resources 
        // needed.  
`define LB2BUFSZ   5


module serout(clk,rdwr,strobe,our_addr,addr,busy_in,busy_out,
       addr_match_in,addr_match_out,datin,datout,u1clk,txd);
    parameter NPORT = 8;
    parameter LOGNPORT = 3;
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
    input  u1clk;            // one sysclk pulse per microsecond
    output [NPORT-1:0] txd;  // output lines

    wire   myaddr;           // ==1 if a correct read/write on our address
    genvar  i;               // loop counter to generate code
    integer j;               // loop counter

           //   baud rate generator and divider
    reg    [1:0] nstop;      // # stop bits -1 (ie 0 means 1 stop bit)
    reg    [3:0] bauddiv;    // configured value from the host
    reg    [3:0] baudcount;  // counter to divide the 38400 clock down
    wire   baudclk;
    wire   baudreset;
    baud38400 b1(clk, u1clk, baudreset, baudclk);

           //  FIFO control lines
    reg    [LOGNPORT:0] rdsel;      // read select line
    reg    [`LB2BUFSZ-1:0] watx [NPORT-1:0]; // FIFO write address for Tx
    reg    [`LB2BUFSZ-1:0] ratx [NPORT-1:0]; // FIFO read address for Tx
wire [`LB2BUFSZ-1:0] ratx0; assign ratx0 = ratx[0];
wire [`LB2BUFSZ-1:0] watx0; assign watx0 = watx[0];
    wire   [NPORT-1:0] buffull;    // ==1 if FIFO can not take more characters
    wire   [NPORT-1:0] bufempty;   // ==1 if there are no characters to send
    for (i = 0; i < NPORT; i=i+1)
    begin : gen_fifo_wires
        assign buffull[i] = ((watx[i] + `LB2BUFSZ'h01) == ratx[i]);
        assign bufempty[i] = (watx[i] == ratx[i]);
    end
           // latch the buff empty status at start of each Tx byte
    reg    [NPORT-1:0] emptylatch;

           // RAM control lines
    wire   we;                    // RAM write strobe for Tx
    wire   [`LB2BUFSZ+LOGNPORT-1:0] wa;     // bit write address (`LB2BUFSZ bytes per port)
    wire   [`LB2BUFSZ+LOGNPORT-1:0] ra;     // bit read address
    wire   [7:0] rd;              // registered read data from RAM
    dpram   #(.LOGNPORT(LOGNPORT)) memtx(clk, we, wa, datin, ra, rd);
           // write when (our address) and (not config register) and (selected 
           // port is not full)
    assign we = ((strobe & myaddr & ~rdwr) & (addr[LOGNPORT] ==0) & (buffull[addr[LOGNPORT-1:0]] == 0));
           // write address is port number in high two bits and port's FIFO
           // write address in the lower bits
    assign wa = {addr[LOGNPORT-1:0], watx[addr[LOGNPORT-1:0]]};
           // read address is port number from rdsel and the FIFO read address
    assign ra = {rdsel[LOGNPORT:1],ratx[rdsel[LOGNPORT:1]]};

           // Serial bit shifting
           // baudflag is set on each baudclk.  It starts the port counter rdsel
    reg    baudflag;
           // Bit multiplexer to select start bit, stop bits, or data bits
    reg    [3:0] bitreg;     // shift counters to set which bit is on output Tx line
           // state of the Tx lines
    reg    [NPORT-1:0] sendbit;
    assign txd = sendbit;


    initial
    begin
        nstop = 2'h0;
        bauddiv = 4'h0;
        baudcount = 4'h0;
        rdsel = 4'h0;
        baudflag = 1'b0;
        for (j = 0; j < NPORT; j = j+1)
        begin : initfifo
            watx[j]   = `LB2BUFSZ'h000;
            ratx[j]   = `LB2BUFSZ'h000;
            bitreg[j] = 4'h0;
        end
    end

    always @(posedge clk)
    begin
        if (strobe & myaddr & ~rdwr)  // latch data on a write
        begin
            if ((addr[LOGNPORT] == 1'b0) & (~buffull[addr[LOGNPORT-1:0]]))
            begin
                // store new character
                watx[addr[LOGNPORT-1:0]] <= watx[addr[LOGNPORT-1:0]] + `LB2BUFSZ'h01;
            end
            else if (addr[LOGNPORT] == 1'b1)
            begin
                bauddiv <= datin[3:0];
                nstop <= datin[5:4];
            end
        end

        if (baudclk)
        begin
            // divide baudclk by bauddiv and set flag to start new bit output
            if (baudcount == 0)
            begin
                baudflag <= 1'b1;
                baudcount <= bauddiv;
                // Increment bitreg if not the last bit.
                // 10 bits (0-9) if 1 stop bit.  More if more stop bits
                if (bitreg == (4'd9 + {2'h0, nstop[1:0]}))
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
        else if (baudflag)
        begin
            // reset baudflag when we are done looking at all ports
            //if (~rdsel == 0)        // inverse == 0 when all bits set
            if (rdsel == NPORT-1)
                baudflag <= 1'b0;

            // increment to the next state to control sequential RAM access
            rdsel <= rdsel + 4'h1;

            // Latch the serial bit from RAM on the second (of two) 
            // states of rdsel.
            if ((rdsel[0] == 1'b1) & (~emptylatch[rdsel[LOGNPORT:1]]))
            begin
                sendbit[rdsel[LOGNPORT:1]] <= 
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
                if (bitreg == (4'd9 + {2'h0, nstop[1:0]}))
                begin
                    ratx[rdsel[LOGNPORT:1]] <= ratx[rdsel[LOGNPORT:1]] + `LB2BUFSZ'h01;
                end
            end
        end
    end

    // Assign the outputs.
    assign baudreset = 1'b0;

    assign myaddr = (addr[11:8] == our_addr) && (addr[7:LOGNPORT+1] == 5'h00);
    assign datout = (~myaddr) ? datin : 
                     (strobe && (addr[LOGNPORT:0] == NPORT)) ? {4'h0,bauddiv} : 1'b0;

    // Loop in-to-out where appropriate
    assign busy_out = busy_in;
    // Accept write byte if our address and the config register or a FIFO that is not full
    assign addr_match_out = addr_match_in | (myaddr & addr[LOGNPORT]) |
                            (myaddr & ~buffull[addr[LOGNPORT-1:0]]);

endmodule


// baud38400
// This module generates a 38461 Hertz clock.  The error is less
// 0.2 percent.  
module baud38400(clk, u1clk, reset, baudout);
    input  clk;              // system clock
    input  u1clk;            // a pulse every 1 microseconds
    input  reset;            // reset the counters to zero, active high
    output baudout;          // a clk wide pulse 38461 times per second

    //  38400 Hz is has a period of almost exactly 26 microseconds
    reg    [4:0] u1count;    // counts from zero to 25
    reg    baudreg;

    initial
    begin
        u1count = 0;
    end

    always @(posedge clk)
    begin
        if (u1clk)
        begin
            if (u1count == 5'd25)
                u1count <= 5'd0;
            else
                u1count <= u1count + 1;
        end
        baudreg <= ((u1count == 0) && (u1clk == 1));
    end

    assign baudout = baudreg;

endmodule


`ifdef notyet
// baud921k
// This module generates a 921600 Hertz clock.  The error is less
// 0.2 percent.  
module baud921k(clk, reset, baudout);
    input  clk;              // system clock (20 MHz)
    input  reset;            // reset the counters to zero, active high
    output baudout;          // a clk wide pulse 38461 times per second

    //  921600 is between 21 and 22 50ns clocks.  We use a phase accumulator
    //  delay 21 or 22 clocks depending on the accumulated phase.  We accumulate
    //  50 ns of phase on each 20 MHz clock.  The period jumps between 1050ns and
    //  1100ns with an average of 1085ns, or about 921660 Hertz

    reg    [11:0] phacc;     // phase accumulator
    reg    baudreg;

    initial
    begin
        phacc = 0;
    end

    always @(posedge clk)
    begin
        if (phacc[11] == 1)
        begin
            phacc <= phacc + 12'd1035;
            baudreg <= 1;
        end
        else
        begin
            phacc <= phacc - 50;
            baudreg <= 0;
        end
    end

    assign baudout = baudreg;

endmodule
`endif


//
// Dual-Port RAM with Asynchronous Read
//
module
dpram(clk,we,wa,wd,ra,rd);
    parameter LOGNPORT = 3;
    input    clk;                           // system clock
    input    we;                            // write strobe
    input    [`LB2BUFSZ+LOGNPORT-1:0] wa;   // write address
    input    [7:0] wd;                      // write data
    input    [`LB2BUFSZ+LOGNPORT-1:0] ra;   // read address
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

