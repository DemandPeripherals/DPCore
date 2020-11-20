/*
 *  buildmain.c:   A program to help generate main.v
 *  This program builds a chain of peripherals by linking the outputs of
 *  one peripheral to the inputs of the next.
 */

/* *********************************************************
 * Copyright (c) 2020 Demand Peripherals, Inc.
 * 
 * This file is licensed separately for private and commercial
 * use.  See LICENSE.txt which should have accompanied this file
 * for details.  If LICENSE.txt is not available please contact
 * support@demandperipherals.com to receive a copy.
 * 
 * In general, you may use, modify, redistribute this code, and
 * use any associated patent(s) as long as
 * 1) the above copyright is included in all redistributions,
 * 2) this notice is included in all source redistributions, and
 * 3) this code or resulting binary is not sold as part of a
 *    commercial product.  See LICENSE.txt for definitions.
 * 
 * DPI PROVIDES THE SOFTWARE "AS IS," WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING
 * WITHOUT LIMITATION ANY WARRANTIES OR CONDITIONS OF TITLE,
 * NON-INFRINGEMENT, MERCHANTABILITY, OR FITNESS FOR A PARTICULAR
 * PURPOSE.  YOU ARE SOLELY RESPONSIBLE FOR DETERMINING THE
 * APPROPRIATENESS OF USING OR REDISTRIBUTING THE SOFTWARE (WHERE
 * ALLOWED), AND ASSUME ANY RISKS ASSOCIATED WITH YOUR EXERCISE OF
 * PERMISSIONS UNDER THIS AGREEMENT.
 * 
 * This software may be covered by US patent #10,324,889. Rights
 * to use these patents is included in the license agreements.
 * See LICENSE.txt for more information.
 * *********************************************************/


#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Maximum name length for a peripheral
#define PERILEN  20

// Maximum ROM string length
#define ROMSTRLN 256

// Give forward references for the peripheral invocation functions
// Note that these are the "real" peripherals as defined in the FPGA.
int perilist(int, int, char *);
int bb4io(int, int, char *);
int servo4(int, int, char *);
int stepu(int, int, char *);
int stepb(int, int, char *);
int dc2(int, int, char *);
int pgen16(int, int, char *);
int quad2(int, int, char *);
int qtr4(int, int, char *);
int qtr8(int, int, char *);
int roten(int, int, char *);
int count4(int, int, char *);
int ping4(int, int, char *);
int irio(int, int, char *);
int rcrx(int, int, char *);
int rfob(int, int, char *);
int espi(int, int, char *);
int adc12(int, int, char *);
int out4(int, int, char *);
int out4l(int, int, char *);
int gpio4(int, int, char *);
int out32(int, int, char *);
int lcd6(int, int, char *);
int in4(int, int, char *);
int io8(int, int, char *);
int tif(int, int, char *);
int us8(int, int, char *);
int in32(int, int, char *);
int ei2c(int, int, char *);
int null(int, int, char *);
int ws2812(int, int, char *);
void printbus(int, char *);     // bus lines common to all peripherals


struct ENUMERATORS {
    char *periname;                     // DP internal name of the peripheral
    char *incname;                      // Name of the include file
    char *libname;                      // DP daemon loadable module name 
    int  (*invoke)(int, int, char *);   // function to build main.v
};

struct ENUMERATORS enumerators[] = {
    // Note that these are the peripherals as made visible to the
    // enumerator.  For example, "avr" is, in hardware, an instance
    // of an espi peripheral, but we want to load the avr.so driver
    // so we alias "avr" to "espi".  This is the table of aliases,
    // or, if you will, the table of .so files.
    {"enumerator","enumerator", "enumerator", perilist },
    {"bb4io", "bb4io", "bb4io", bb4io },
    {"servo4", "servo4", "servo4", servo4 },
    {"stepu", "stepu", "stepu", stepu },
    {"stepb", "stepb", "stepb", stepb },
    {"dc2", "dc2", "dc2", dc2 },
    {"aamp", "out4", "aamp", out4 },
    {"pgen16", "pgen16", "pgen16", pgen16 },
    {"pwmout4", "pgen16", "pwmout4", pgen16 },
    {"quad2", "quad2", "quad2", quad2 },
    {"qtr4", "qtr4", "qtr4", qtr4 },
    {"qtr8", "qtr8", "qtr8", qtr8 },
    {"roten", "roten", "roten", roten },
    {"count4", "count4", "count4", count4 },
    {"touch4", "count4", "touch4", count4 },
    {"ping4", "ping4", "ping4", ping4 },
    {"irio", "irio", "irio", irio },
    {"espi", "espi", "espi", espi },
    {"dac8", "espi", "dac8", espi },
    {"qpot", "espi", "qpot", espi },
    {"rtc", "espi", "rtc", espi },
    {"avr", "espi", "avr", espi },
    {"adc812", "adc12", "adc812", adc12 },
    {"slide4", "adc12", "slide4", adc12 },
    {"out4", "out4", "out4", out4 },
    {"out4l", "out4l", "out4l", out4l },
    {"ws2812", "ws2812", "ws2812", ws2812 },
    {"rly4", "out4l", "rly4", out4l },
    {"drv4", "out4", "drv3", out4 },
    {"hub4", "out4", "hub4", out4 },
    {"gpio4", "gpio4", "gpio4", gpio4 },
    {"out32", "out32", "out32", out32 },
    {"lcd6", "lcd6", "lcd6", lcd6 },
    {"in4", "in4", "in4", in4 },
    {"sw4", "in4", "sw4", in4 },
    {"io8", "io8", "io8", io8 },
    {"tif", "tif", "tif", tif },
    {"us8", "us8", "us8", us8 },
    {"in32", "in32", "in32", in32 },
    {"ei2c", "ei2c", "ei2c", ei2c },
    {"rcrx", "rcrx", "rcrx", rcrx },
    {"rfob", "rfob", "rfob", rfob },
    {"null", "null", "null", null },
};

#define NPERI (sizeof(enumerators) / sizeof(struct ENUMERATORS))
#define ENUMROMSZ 2048

main(int argc, char *argv[])
{
    FILE *pdescfile;        // The description file
    FILE *pincludes;        // The includes file that drives compilation
    FILE *penumlst;         // The enumerator file with the library names
    char  peri[PERILEN];    // The peripheral name
    int   ret;
    int   slot = 0;         // First peripheral is at address 0
    int   pin = 0;          // Pins are numbered from zero
    int   i;                // Peripheral loop index
    char  rom[ENUMROMSZ];   // image of what goes into the enumerator ROM
    int   romindx = 0;      // How many bytes of rom are used
    int   lnlen,j;          // Library Name LENgth, char index into lib name
    char  romstr[ROMSTRLN]; // string to be copied to the enumerator ROM


    if (argc != 2) {
        fprintf(stderr, "FATAL: %s expects a single filename argument %d\n",
                argv[0], argc);
        exit(1);
    }

    // Open the includes file and get it started
    pincludes = fopen("includes.tmp", "w");
    if (pincludes == (FILE *)0) {
        fprintf(stderr, "FATAL: %s: Unable to open 'includes.tmp' for writing\n",
                argv[0]);
        exit(1);
    }




    // Open the file with the list of peripherals
    pdescfile = fopen(argv[1], "r");
    if (pdescfile == (FILE *)0) {
        fprintf(stderr, "FATAL: %s: Unable to open %s for reading\n",
                argv[0], argv[1]);
        exit(1);
    }


    // Open the enumerator.lst file and prep the image
    penumlst = fopen("enumerator.lst", "w");
    if (penumlst == (FILE *)0) {
        fprintf(stderr, "FATAL: %s: Unable to open 'enumerator.lst'\n",
                argv[0]);
        exit(1);
    }
    for (j = romindx; j < ENUMROMSZ; j++)
        rom[j] = (char) 0;

    // the first 8 lines of the descfile are copied to the ROM image
    romindx = 0;
    for (j = 0; j < 8; j++) {
        if (0 == fgets(romstr, ROMSTRLN, pdescfile)) {
            printf("Not enough ROM strings\n");
            exit(1);
        }
        // replace the newline with a null
        romstr[strlen(romstr)-1] = (char) 0;
        romindx += sprintf(&(rom[romindx]), "%s%c", romstr, (char) 0);
    }

    // Loop through the list of peripherals
    while (1) {
        ret = fscanf(pdescfile, "%s", peri);
        if (ret == EOF) {   // no more peripherals to process
            fclose(pdescfile);
            fclose(pincludes);
            fprintf(stdout, "\nendmodule\n");
            break;
        }
        else if (ret < 0) {
            fprintf(stderr, "FATAL: %s: Read error on %s.\n", argv[0], argv[1]);
            exit(1);
        }

        // Skip lines beginning with a #
        if (peri[0] == '#')
            continue;

        for (i = 0; i < NPERI; i++) {
            if (0 == strncmp(peri, enumerators[i].periname, (PERILEN - 1)))
                break;
        }
        if (i == NPERI) {
            fprintf(stderr, "FATAL: %s: Unknown peripheral: %s\n",
                    argv[0], peri);
            exit(1);
        }
        // Found the peripheral.  Invoke it with its slot # and starting pin #
        pin = (enumerators[i].invoke)(slot, pin, peri);

        // add it to the includes file
        fprintf(pincludes, "`include \"%s.v\"\n", enumerators[i].incname);

        // Put the library name in the rom image
        romindx += sprintf(&(rom[romindx]), "%s%c", enumerators[i].libname,
                           (char) 0);
        if (romindx > ENUMROMSZ) {
            printf("Oops, Enumerator ROM overflow\n");
            exit(1);
        }

        // Go to next slot/peripheral
        slot = slot + 1;
    }

    // Copy enumerator ROM image to enumerator.lst file format
    for (i = 0; i < 16; i++) {
        fprintf(penumlst, "    .INIT_%02X(256'h", i);
        for (j = ((32 * (i + 1)) -1); j >= (32 * i); j--)
            fprintf(penumlst, "%02x", rom[j]);
        if (i != 15)
            fprintf(penumlst, "),\n");
        else
            fprintf(penumlst, ")\n");
    }

    exit(0);
}



// The peripheral invocation functions.
// They take in the peripheral address and current PIN
// number, and return the PIN number of the next available PIN. 

int perilist(int addr, int startpin, char * peri)
{
    fprintf(stdout, "\n    // %s\n", peri);
    fprintf(stdout, "    %s p%02d(p%02dclk,p%02drdwr,", peri,addr,addr,addr);
    fprintf(stdout, "p%02dstrobe,p%02dour_addr,p%02daddr,\n", addr,addr,addr);
    fprintf(stdout, "        p%02dbusy_in,p%02dbusy_out,p%02daddr_match_in,", addr,addr,addr);
    fprintf(stdout, "p%02daddr_match_out,p%02ddatin,p%02ddatout);\n", addr,addr,addr);
    return(startpin + 0);    // enumerator does not use any connector pins
}


int bb4io(int addr, int startpin, char * peri)
{
    fprintf(stdout,"\n    wire [7:0] p%02dleds;", addr);
    fprintf(stdout,"\n    wire p%02dbntn1;", addr);
    fprintf(stdout,"\n    wire p%02dbntn2;", addr);
    fprintf(stdout,"\n    wire p%02dbntn3;", addr);
    printbus(addr, peri);
    fprintf(stdout, "        p%02dleds,p%02dbntn1,p%02dbntn2,p%02dbntn3);\n", addr,addr,addr,addr);
    fprintf(stdout, "    assign p%02dbntn1 = BNTN1;\n", addr);
    fprintf(stdout, "    assign p%02dbntn2 = BNTN2;\n", addr);
    fprintf(stdout, "    assign p%02dbntn3 = BNTN3;\n", addr);
    fprintf(stdout, "    assign LED = p%02dleds;\n", addr);
    return(startpin + 0);    // bb4io does not use any connector pins
}


int stepu(int addr, int startpin, char * peri)
{
    printbus(addr, peri);
    fprintf(stdout, "        p%02dm1clk,p%02du100clk,p%02du10clk,p%02du1clk,",addr,addr,addr,addr);
    fprintf(stdout, "        p%02dcoila,p%02dcoilb,p%02dcoilc,p%02dcoild);\n", addr,addr,addr,addr);
    fprintf(stdout, "    assign p%02dm1clk = bc0m1clk;\n", addr);
    fprintf(stdout, "    assign p%02du100clk = bc0u100clk;\n", addr);
    fprintf(stdout, "    assign p%02du10clk = bc0u10clk;\n", addr);
    fprintf(stdout, "    assign p%02du1clk = bc0u1clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dcoila;\n", startpin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dcoilb;\n", startpin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dcoilc;\n", startpin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dcoild;\n", startpin+3, addr);
    return(startpin +4);
}

int stepb(int addr, int startpin, char * peri)
{
    printbus(addr, peri);
    fprintf(stdout, "        p%02dm1clk,p%02du100clk,p%02du10clk,p%02du1clk,\n",addr,addr,addr,addr);
    fprintf(stdout, "        p%02dain1,p%02dain2,p%02dbin1,p%02dbin2);\n", addr,addr,addr,addr);
    fprintf(stdout, "    assign p%02dm1clk = bc0m1clk;\n", addr);
    fprintf(stdout, "    assign p%02du100clk = bc0u100clk;\n", addr);
    fprintf(stdout, "    assign p%02du10clk = bc0u10clk;\n", addr);
    fprintf(stdout, "    assign p%02du1clk = bc0u1clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dain1;\n", startpin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dain2;\n", startpin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dbin1;\n", startpin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dbin2;\n", startpin+3, addr);
    return(startpin +4);
}

int dc2(int addr, int startpin, char * peri)
{
    printbus(addr, "dc2");
    fprintf(stdout, "   p%02dm100clk,p%02du100clk,\n",addr,addr);
    fprintf(stdout, "   p%02du10clk,p%02du1clk,p%02dn100clk,\n",addr,addr,addr);
    fprintf(stdout, "   p%02dain1,p%02dain2,p%02dbin1,p%02dbin2);\n", addr,addr,addr,addr);
    fprintf(stdout, "    assign p%02dm100clk = bc0m100clk;\n", addr);
		fprintf(stdout, "    assign p%02dm10clk = bc0m10clk;\n", addr);
    fprintf(stdout, "    assign p%02dm1clk = bc0m1clk;\n", addr);
    fprintf(stdout, "    assign p%02du100clk = bc0u100clk;\n", addr);
    fprintf(stdout, "    assign p%02du10clk = bc0u10clk;\n", addr);
    fprintf(stdout, "    assign p%02du1clk = bc0u1clk;\n", addr);
    fprintf(stdout, "    assign p%02dn100clk = bc0n100clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dain1;\n", startpin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dain2;\n", startpin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dbin1;\n", startpin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dbin2;\n", startpin+3, addr);
    return(startpin +4);
}


int pgen16(int addr, int startpin, char * peri)
{
    fprintf(stdout,"\n    wire [3:0] p%02dpattern;", addr);
    printbus(addr, "pgen16");
    fprintf(stdout, "        p%02dm100clk,p%02dm10clk,p%02dm1clk,",addr,addr,addr);
    fprintf(stdout, "        p%02du100clk,p%02du10clk,p%02du1clk,p%02dn100clk,",addr,addr,addr,addr);
    fprintf(stdout, "        p%02dpattern);\n", addr);
    fprintf(stdout, "    assign p%02dm100clk = bc0m100clk;\n", addr);
		fprintf(stdout, "    assign p%02dm10clk = bc0m10clk;\n", addr);
    fprintf(stdout, "    assign p%02dm1clk = bc0m1clk;\n", addr);
    fprintf(stdout, "    assign p%02du100clk = bc0u100clk;\n", addr);
    fprintf(stdout, "    assign p%02du10clk = bc0u10clk;\n", addr);
    fprintf(stdout, "    assign p%02du1clk = bc0u1clk;\n", addr);
    fprintf(stdout, "    assign p%02dn100clk = bc0n100clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpattern[0];\n", startpin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpattern[1];\n", startpin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpattern[2];\n", startpin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpattern[3];\n", startpin+3, addr);
    return(startpin +4);
}

int quad2(int addr, int startpin, char * peri)
{
    fprintf(stdout,"\n    wire p%02dm10clk;", addr);
    fprintf(stdout,"\n    wire p%02du1clk;", addr);
    fprintf(stdout,"\n    wire p%02da1;", addr);
    fprintf(stdout,"\n    wire p%02da2;", addr);
    fprintf(stdout,"\n    wire p%02db1;", addr);
    fprintf(stdout,"\n    wire p%02db2;", addr);
    printbus(addr, peri);
    fprintf(stdout, "    p%02dm10clk,p%02du1clk,p%02da1,p%02da2,\
           p%02db1,p%02db2);\n", addr,addr,addr,addr,addr,addr);
    fprintf(stdout, "    assign p%02dm10clk = bc0m10clk;\n", addr);
    fprintf(stdout, "    assign p%02du1clk = bc0u1clk;\n", addr);
    fprintf(stdout, "    assign p%02da1 = `PIN_%02d;\n", addr, startpin);
    fprintf(stdout, "    assign p%02da2 = `PIN_%02d;\n", addr, startpin+1);
    fprintf(stdout, "    assign p%02db1 = `PIN_%02d;\n", addr, startpin+2);
    fprintf(stdout, "    assign p%02db2 = `PIN_%02d;\n", addr, startpin+3);
    return(startpin +4);
}

int qtr4(int addr, int startpin, char * peri)
{
    fprintf(stdout,"\n    wire p%02dm10clk;", addr);
    fprintf(stdout,"\n    wire p%02du10clk;", addr);
    fprintf(stdout,"\n    tri [3:0] p%02dq;", addr);
    printbus(addr, peri);
    fprintf(stdout, "    p%02dm10clk,p%02du10clk,p%02dq);\n", addr, addr, addr);
    fprintf(stdout, "    assign p%02dm10clk = bc0m10clk;\n", addr);
    fprintf(stdout, "    assign p%02du10clk = bc0u10clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dq[0];\n", startpin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dq[1];\n", startpin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dq[2];\n", startpin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dq[3];\n", startpin+3, addr);
    return(startpin +4);
}

int qtr8(int addr, int startpin, char * peri)
{
    fprintf(stdout,"\n    wire p%02dm10clk;", addr);
    fprintf(stdout,"\n    wire p%02du10clk;", addr);
    fprintf(stdout,"\n    tri [7:0] p%02dq;", addr);
    printbus(addr, peri);
    fprintf(stdout, "    p%02dm10clk,p%02du10clk,p%02dq);\n", addr, addr, addr);
    fprintf(stdout, "    assign p%02dm10clk = bc0m10clk;\n", addr);
    fprintf(stdout, "    assign p%02du10clk = bc0u10clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dq[0];\n", startpin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dq[1];\n", startpin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dq[2];\n", startpin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dq[3];\n", startpin+3, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dq[4];\n", startpin+4, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dq[5];\n", startpin+5, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dq[6];\n", startpin+6, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dq[7];\n", startpin+7, addr);
    return(startpin +8);
}

int roten(int addr, int startpin, char * peri)
{
    printbus(addr, peri);
    fprintf(stdout, "    p%02dbtn,p%02dq1,p%02dq2,p%02dled);\n",
           addr,addr,addr,addr);
    fprintf(stdout, "    assign p%02dpollevt = bc0pollevt;\n", addr);
    fprintf(stdout, "    assign p%02dbtn = `PIN_%02d;\n", addr, startpin);
    fprintf(stdout, "    assign p%02dq1 = `PIN_%02d;\n", addr, startpin+1);
    fprintf(stdout, "    assign p%02dq2 = `PIN_%02d;\n", addr, startpin+2);
    fprintf(stdout, "    assign `PIN_%02d = p%02dled;\n", startpin+3, addr);
    return(startpin +4);
}

int count4(int addr, int startpin, char * peri)
{
    printbus(addr, "count4");
    fprintf(stdout, "    p%02dm10clk,p%02du1clk,p%02da,p%02db,p%02dc,p%02dd);\n",
           addr,addr,addr,addr,addr,addr);
    fprintf(stdout, "    assign p%02dm10clk = bc0m10clk;\n", addr);
    fprintf(stdout, "    assign p%02du1clk = bc0u1clk;\n", addr);
    fprintf(stdout, "    assign p%02da = `PIN_%02d;\n", addr, startpin);
    fprintf(stdout, "    assign p%02db = `PIN_%02d;\n", addr, startpin+1);
    fprintf(stdout, "    assign p%02dc = `PIN_%02d;\n", addr, startpin+2);
    fprintf(stdout, "    assign p%02dd = `PIN_%02d;\n", addr, startpin+3);
    return(startpin +4);
}


int servo4(int addr, int pin, char * peri)
{
    fprintf(stdout,"\n    wire [3:0] p%02dservo;", addr);
    printbus(addr, peri);
    fprintf(stdout, "        p%02dservo);\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dservo[0];\n", pin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dservo[1];\n", pin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dservo[2];\n", pin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dservo[3];\n", pin+3, addr);
    return(pin +4);
}


int ping4(int addr, int pin, char * peri)
{
    fprintf(stdout,"\n    tri [3:0] p%02dpng;", addr);
    printbus(addr, peri);
    fprintf(stdout, "    p%02du1clk, p%02dm10clk, p%02dpng);\n", addr, addr, addr);
    fprintf(stdout, "    assign p%02du1clk = bc0u1clk;\n", addr);
    fprintf(stdout, "    assign p%02dm10clk = bc0m10clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpng[0];\n", pin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpng[1];\n", pin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpng[2];\n", pin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpng[3];\n", pin+3, addr);
    return(pin +4);
}


int irio(int addr, int pin, char * peri)
{
    fprintf(stdout,"\n    tri p%02dspare0;", addr);
    fprintf(stdout,"\n    tri p%02dspare1;", addr);
    printbus(addr, peri);
    fprintf(stdout, " p%02du100clk, p%02du1clk, p%02drxled, ", addr, addr, addr);
    fprintf(stdout, "p%02dtxled, p%02dirout, p%02dirin);\n", addr, addr, addr);
    fprintf(stdout, "    assign p%02du100clk = bc0u100clk;\n", addr);
    fprintf(stdout, "    assign p%02du1clk = bc0u1clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02drxled;\n", pin+0, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dtxled;\n", pin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dirout;\n", pin+2, addr);
    fprintf(stdout, "    assign p%02dirin = `PIN_%02d;\n", addr, pin+3);
    return(pin +4);
}


int rcrx(int addr, int pin, char * peri)
{
    fprintf(stdout,"\n    tri p%02dspare0;", addr);
    fprintf(stdout,"\n    tri p%02dspare1;", addr);
    printbus(addr, peri);
    fprintf(stdout, "        p%02dn100clk, p%02drcin, p%02dpktled, ", addr, addr, addr);
    fprintf(stdout, "p%02dspare0, p%02dspare1);\n", addr, addr);
    fprintf(stdout, "    assign p%02dn100clk = bc0n100clk;\n", addr);
    fprintf(stdout, "    assign p%02drcin = `PIN_%02d;\n", addr, pin);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpktled;\n", pin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dspare0;\n", pin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dspare1;\n", pin+3, addr);
    return(pin +4);
}


int rfob(int addr, int pin, char * peri)
{
    printbus(addr, peri);
    fprintf(stdout, "        p%02du10clk, p%02dm1clk, p%02drfdin, ", addr, addr, addr);
    fprintf(stdout, "p%02drssi, p%02dpwml, p%02dpwmh);\n", addr, addr, addr);
    fprintf(stdout, "    assign p%02du10clk = bc0u10clk;\n", addr);
    fprintf(stdout, "    assign p%02dm1clk = bc0m1clk;\n", addr);
    fprintf(stdout, "    assign p%02drfdin = `PIN_%02d;\n", addr, pin);
    fprintf(stdout, "    assign p%02drssi = `PIN_%02d;\n", addr, pin+1);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpwml;\n", pin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpwmh;\n", pin+3, addr);
    return(pin +4);
}


int espi(int addr, int pin, char * peri)
{
    printbus(addr, "espi");
    fprintf(stdout, "        p%02du100clk, p%02du10clk, ", addr, addr);
    fprintf(stdout, "        p%02du1clk, p%02dn100clk, ", addr, addr);
    fprintf(stdout, "        p%02dmosi, p%02da, p%02db, p%02dmiso);\n", addr, addr, addr, addr);
    fprintf(stdout, "    assign p%02du100clk = bc0u100clk;\n", addr);
    fprintf(stdout, "    assign p%02du10clk = bc0u10clk;\n", addr);
    fprintf(stdout, "    assign p%02du1clk = bc0u1clk;\n", addr);
    fprintf(stdout, "    assign p%02dn100clk = bc0n100clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dmosi;\n", pin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02da;\n", pin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02db;\n", pin+2, addr);
    fprintf(stdout, "    assign p%02dmiso = `PIN_%02d;\n", addr, pin+3);
    return(pin +4);
}


int adc12(int addr, int pin, char * peri)
{
    fprintf(stdout, "\n    wire p%02dn100clk;\n", addr);
    fprintf(stdout, "    wire p%02dm1clk;\n", addr);
    fprintf(stdout, "    wire p%02dmosi;\n", addr);
    fprintf(stdout, "    wire p%02da;\n", addr);
    fprintf(stdout, "    wire p%02db;\n", addr);
    fprintf(stdout, "    wire p%02dmiso;", addr);
    printbus(addr, "adc12");
    fprintf(stdout, "    p%02dn100clk, p%02dm1clk, p%02dmosi, ", addr, addr, addr);
    fprintf(stdout, "    p%02da, p%02db, p%02dmiso);\n", addr, addr, addr);
    fprintf(stdout, "    assign p%02dn100clk = bc0n100clk;\n", addr);
    fprintf(stdout, "    assign p%02dm1clk = bc0m1clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dmosi;\n", pin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02da;\n", pin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02db;\n", pin+2, addr);
    fprintf(stdout, "    assign p%02dmiso = `PIN_%02d;\n", addr, pin+3);
    return(pin +4);
}


int ws2812(int addr, int pin, char * peri)
{
    printbus(addr, "ws2812");
    fprintf(stdout, "    p%02dled1,p%02dled2,", addr,addr);
    fprintf(stdout, "    p%02dled3,p%02dled4);\n", addr,addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dled1;\n", pin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dled2;\n", pin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dled3;\n", pin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dled4;\n", pin+3, addr);
    return(pin +4);
}


int out4(int addr, int pin, char * peri)
{
    fprintf(stdout,"\n    wire [3:0] p%02dbitout;", addr);
    printbus(addr, "out4");
    fprintf(stdout, "        p%02dbitout);\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dbitout[0];\n", pin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dbitout[1];\n", pin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dbitout[2];\n", pin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dbitout[3];\n", pin+3, addr);
    return(pin +4);
}


int out4l(int addr, int pin, char * peri)
{
    fprintf(stdout,"\n    wire [3:0] p%02dbitout;", addr);
    printbus(addr, "out4l");
    fprintf(stdout, "        p%02dbitout);\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dbitout[0];\n", pin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dbitout[1];\n", pin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dbitout[2];\n", pin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dbitout[3];\n", pin+3, addr);
    return(pin +4);
}


int gpio4(int addr, int pin, char * peri)
{
    fprintf(stdout,"\n    tri [3:0] p%02dsbio;", addr);
    printbus(addr, peri);
    fprintf(stdout, "        p%02dsbio);\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dsbio[0];\n", pin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dsbio[1];\n", pin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dsbio[2];\n", pin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dsbio[3];\n", pin+3, addr);
    return(pin +4);
}


int in4(int addr, int startpin, char * peri)
{
    fprintf(stdout,"\n    wire [3:0] p%02din;", addr);
    printbus(addr, "in4");
    fprintf(stdout, "        p%02din);\n", addr);
    fprintf(stdout, "    assign p%02dpollevt = bc0pollevt;\n", addr);
    fprintf(stdout, "    assign p%02din[0] = `PIN_%02d;\n", addr, startpin);
    fprintf(stdout, "    assign p%02din[1] = `PIN_%02d;\n", addr, startpin+1);
    fprintf(stdout, "    assign p%02din[2] = `PIN_%02d;\n", addr, startpin+2);
    fprintf(stdout, "    assign p%02din[3] = `PIN_%02d;\n", addr, startpin+3);
    return(startpin +4);
}


int watchdog2(int addr, int pin, char * peri)
{
    printbus(addr, peri);
    fprintf(stdout, "        p%02ds1clk, p%02dwd0in, p%02dwd0out,", addr,addr,addr);
    fprintf(stdout, "p%02dwd1in, p%02dwd1out);\n", addr,addr);
    fprintf(stdout, "    assign p%02ds1clk = bc0s1clk;\n", addr);
    fprintf(stdout, "    assign p%02dwd0in = `PIN_%02d;\n", addr, pin);
    fprintf(stdout, "    assign `PIN_%02d = p%02dwd0out;\n", pin+1, addr);
    fprintf(stdout, "    assign p%02dwd1in = `PIN_%02d;\n", addr, pin+2);
    fprintf(stdout, "    assign `PIN_%02d = p%02dwd1out;\n", pin+3, addr);
    return(pin +4);
}


int out32(int addr, int startpin, char * peri)
{
    printbus(addr, peri);
    fprintf(stdout, "    p%02du10clk, ", addr);
    fprintf(stdout, "    p%02dpin2,p%02dpin4,p%02dpin6,p%02dpin8);\n", addr,addr,addr,addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin2;\n", startpin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin4;\n", startpin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin6;\n", startpin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin8;\n", startpin+3, addr);
    return(startpin +4);
}


int lcd6(int addr, int startpin, char * peri)
{
    fprintf(stdout,"\n    wire p%02du100clk;", addr);
    fprintf(stdout,"\n    wire p%02dpin2;", addr);
    fprintf(stdout,"\n    wire p%02dpin4;", addr);
    fprintf(stdout,"\n    wire p%02dpin6;", addr);
    fprintf(stdout,"\n    wire p%02dpin8;", addr);
    printbus(addr, peri);
    fprintf(stdout, "    p%02du100clk, ", addr);
    fprintf(stdout, "    p%02dpin2,p%02dpin4,p%02dpin6,p%02dpin8);\n", addr,addr,addr,addr);
    fprintf(stdout, "    assign p%02du100clk = bc0u100clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin2;\n", startpin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin4;\n", startpin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin6;\n", startpin+2, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin8;\n", startpin+3, addr);
    return(startpin +4);
}


int io8(int addr, int startpin, char * peri)
{
    fprintf(stdout,"\n    wire p%02du10clk;", addr);
    fprintf(stdout,"\n    wire p%02dpin2;", addr);
    fprintf(stdout,"\n    wire p%02dpin4;", addr);
    fprintf(stdout,"\n    wire p%02dpin6;", addr);
    fprintf(stdout,"\n    wire p%02dpin8;", addr);
    printbus(addr, peri);
    fprintf(stdout, "    p%02du10clk, ", addr);
    fprintf(stdout, "    p%02dpin2,p%02dpin4,p%02dpin6,p%02dpin8);\n", addr,addr,addr,addr);
    fprintf(stdout, "    assign p%02du10clk = bc0u10clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin2;\n", startpin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin4;\n", startpin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin6;\n", startpin+2, addr);
    fprintf(stdout, "    assign p%02dpin8 = `PIN_%02d;\n", addr, startpin+3);
    return(startpin +4);
}


int tif(int addr, int startpin, char * peri)
{
    printbus(addr, peri);
    fprintf(stdout, "    p%02du1clk, p%02dm10clk, ", addr, addr);
    fprintf(stdout, "    p%02dpin2,p%02dpin4,p%02dpin6,p%02dpin8);\n", addr,addr,addr,addr);
    fprintf(stdout, "    assign p%02du1clk = bc0u1clk;\n", addr);
    fprintf(stdout, "    assign p%02dm10clk = bc0m10clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin2;\n", startpin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin4;\n", startpin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin6;\n", startpin+2, addr);
    fprintf(stdout, "    assign p%02dpin8 = `PIN_%02d;\n", addr, startpin+3);
    return(startpin +4);
}


int us8(int addr, int startpin, char * peri)
{
    printbus(addr, peri);
    fprintf(stdout, "    p%02dn100clk,p%02du10clk,p%02dm10clk, ",addr, addr, addr);
    fprintf(stdout, "    p%02dpin2,p%02dpin4,p%02dpin6,p%02dpin8);\n", addr,addr,addr,addr);
    fprintf(stdout, "    assign p%02dn100clk = bc0n100clk;\n", addr);
    fprintf(stdout, "    assign p%02du10clk = bc0u10clk;\n", addr);
    fprintf(stdout, "    assign p%02dm10clk = bc0m10clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin2;\n", startpin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin4;\n", startpin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin6;\n", startpin+2, addr);
    fprintf(stdout, "    assign p%02dpin8 = `PIN_%02d;\n", addr, startpin+3);
    return(startpin +4);
}


int in32(int addr, int startpin, char * peri)
{
    fprintf(stdout,"\n    wire p%02du10clk;", addr);
    fprintf(stdout,"\n    wire p%02dpin2;", addr);
    fprintf(stdout,"\n    wire p%02dpin4;", addr);
    fprintf(stdout,"\n    wire p%02dpin6;", addr);
    fprintf(stdout,"\n    wire p%02dpin8;", addr);
    printbus(addr, peri);
    fprintf(stdout, "    p%02du10clk, ", addr);
    fprintf(stdout, "    p%02dpin2,p%02dpin4,p%02dpin6,p%02dpin8);\n", addr,addr,addr,addr);
    fprintf(stdout, "    assign p%02du10clk = bc0u10clk;\n", addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin2;\n", startpin, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin4;\n", startpin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin6;\n", startpin+2, addr);
    fprintf(stdout, "    assign p%02dpin8 = `PIN_%02d;\n", addr, startpin+3);
    return(startpin +4);
}



int ei2c(int addr, int pin, char * peri)
{
    fprintf(stdout,"\n    wire p%02dpin2;", addr);
    fprintf(stdout,"\n    wire p%02dpin4;", addr);
    fprintf(stdout,"\n    wire p%02dpin6;", addr);
    fprintf(stdout,"\n    wire p%02dpin8;", addr);
    printbus(addr, "ei2c");
    fprintf(stdout, "    p%02dpin2,p%02dpin4,p%02dpin6,p%02dpin8);\n", addr,addr,addr,addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin2;\n", pin+0, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin4;\n", pin+1, addr);
    fprintf(stdout, "    assign `PIN_%02d = p%02dpin6;\n", pin+2, addr);
    fprintf(stdout, "    assign p%02dpin8 = `PIN_%02d;\n", addr, pin+3);
    return(pin +4);
}



int null(int addr, int pin, char * peri)
{
    // A null peripheral
    fprintf(stdout,"\n    wire p%02ddummy;", addr);
    printbus(addr, "null");
    fprintf(stdout, "        p%02ddummy);\n", addr);
    return(pin);
}


void printbus(int slot, char * peri)
{
    fprintf(stdout, "\n    // %s\n", peri);
    fprintf(stdout, "    %s p%02d(p%02dclk,p%02drdwr,", peri,slot,slot,slot);
    fprintf(stdout, "p%02dstrobe,p%02dour_addr,p%02daddr,\n", slot,slot,slot);
    fprintf(stdout, "        p%02dbusy_in,p%02dbusy_out,p%02daddr_match_in,", slot,slot,slot);
    fprintf(stdout, "p%02daddr_match_out,p%02ddatin,p%02ddatout,\n", slot,slot,slot);
}

