`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// iCE40 SB_IO model (simulation only; synthesis uses the real primitive)
// -----------------------------------------------------------------------------
module SB_IO #(
    parameter [5:0] PIN_TYPE = 6'b000000,
    parameter       PULLUP   = 1'b0
)(
    inout  PACKAGE_PIN,
    input  OUTPUT_ENABLE,
    output D_IN_0,
    input  D_OUT_0
);
    assign PACKAGE_PIN = OUTPUT_ENABLE ? D_OUT_0 : 1'bz;
    assign D_IN_0      = PACKAGE_PIN;
endmodule


// -----------------------------------------------------------------------------
// Testbench
//   - behavioral TM1638 on tm_cs / tm_clk / tm_dio (display RAM + key scan)
//   - "presses" the module buttons S1..S8 to build an 8-bit switch value
//   - checks that the display RAM holds hex (left) and decimal (right)
// -----------------------------------------------------------------------------
module top_tm1638_demo_tb;
    reg  clock = 1'b0;
    wire tm_cs, tm_clk;
    tri1 tm_dio;                       // pulled up like the real module

    // short button sampling period so that the simulation stays fast
    top_tm1638_demo #(
        .TOGGLE_MODE(1),
        .DEB_BITS(6)
    ) dut (
        .clock(clock),
        .tm_cs(tm_cs),
        .tm_clk(tm_clk),
        .tm_dio(tm_dio)
    );

    always #41.667 clock = ~clock;     // ~12 MHz

    // ---------------------------------------------------------------------
    // Behavioral TM1638
    // ---------------------------------------------------------------------
    reg [7:0] btn;                     // btn[7] = S1 ... btn[0] = S8, 1 = pressed
    reg [7:0] mem [0:15];              // display RAM: even = digit, odd = LED
    reg [7:0] rx_shift;
    reg [7:0] cmd;
    reg [7:0] kb;
    reg       reading;
    reg       dio_drv, dio_en;
    integer   rx_bits, rd_idx, wr_addr, frames;

    assign tm_dio = dio_en ? dio_drv : 1'bz;

    // byte k of the key scan data, as decoded by top_tm1638_demo:
    //   bit0 = keys[7-k], bit4 = keys[3-k]
    function [7:0] key_byte;
        input [1:0] k;
        reg [7:0] r;
        begin
            r = 8'h00;
            r[0] = btn[7-k];
            r[4] = btn[3-k];
            key_byte = r;
        end
    endfunction

    integer init_i;
    initial begin
        btn = 8'h00; rx_shift = 8'h00; cmd = 8'h00; kb = 8'h00;
        reading = 1'b0; dio_drv = 1'b0; dio_en = 1'b0;
        rx_bits = 0; rd_idx = 0; wr_addr = 0; frames = 0;
        for (init_i = 0; init_i < 16; init_i = init_i + 1) mem[init_i] = 8'h00;
    end

    always @(negedge tm_cs) begin       // new command/transaction
        rx_bits = 0;
        rd_idx  = 0;
        reading = 1'b0;
        rx_shift = 8'h00;
    end

    always @(posedge tm_cs) begin       // end of transaction, release DIO
        dio_en  = 1'b0;
        reading = 1'b0;
    end

    // data from host is sampled on the rising edge of CLK, LSB first
    always @(posedge tm_clk) begin
        if (tm_cs === 1'b0) begin
            rx_shift = {tm_dio, rx_shift[7:1]};
            rx_bits  = rx_bits + 1;
            if (!reading && (rx_bits % 8 == 0)) begin
                if (rx_bits == 8) begin
                    cmd = rx_shift;
                    if (cmd == 8'h42)              reading = 1'b1;           // read keys
                    else if (cmd[7:6] == 2'b11)    wr_addr = cmd[3:0];       // set address
                    else if (cmd[7:3] == 5'b10001) frames  = frames + 1;     // display on = end of frame
                end else if (cmd[7:6] == 2'b11) begin
                    mem[wr_addr] = rx_shift;                                 // auto increment write
                    wr_addr = (wr_addr + 1) % 16;
                end
            end
        end
    end

    // data to host is driven after the falling edge of CLK, LSB first
    always @(negedge tm_clk) begin
        if (tm_cs === 1'b0 && reading && rd_idx < 32) begin
            kb      = key_byte(rd_idx / 8);
            dio_drv = kb[rd_idx % 8];
            dio_en  = 1'b1;
            rd_idx  = rd_idx + 1;
        end
    end

    // ---------------------------------------------------------------------
    // Helpers (independent of the DUT code)
    // ---------------------------------------------------------------------
    function [6:0] hex7;
        input [3:0] v;
        begin
            case (v)
                4'h0: hex7 = 7'h3F;  4'h1: hex7 = 7'h06;
                4'h2: hex7 = 7'h5B;  4'h3: hex7 = 7'h4F;
                4'h4: hex7 = 7'h66;  4'h5: hex7 = 7'h6D;
                4'h6: hex7 = 7'h7D;  4'h7: hex7 = 7'h07;
                4'h8: hex7 = 7'h7F;  4'h9: hex7 = 7'h6F;
                4'hA: hex7 = 7'h77;  4'hB: hex7 = 7'h7C;
                4'hC: hex7 = 7'h39;  4'hD: hex7 = 7'h5E;
                4'hE: hex7 = 7'h79;  default: hex7 = 7'h71;
            endcase
        end
    endfunction

    function [7:0] seg2chr;
        input [7:0] s;                  // bit 7 (dp) ignored
        begin
            case (s[6:0])
                7'h00: seg2chr = " ";  7'h3F: seg2chr = "0";
                7'h06: seg2chr = "1";  7'h5B: seg2chr = "2";
                7'h4F: seg2chr = "3";  7'h66: seg2chr = "4";
                7'h6D: seg2chr = "5";  7'h7D: seg2chr = "6";
                7'h07: seg2chr = "7";  7'h7F: seg2chr = "8";
                7'h6F: seg2chr = "9";  7'h77: seg2chr = "A";
                7'h7C: seg2chr = "b";  7'h39: seg2chr = "C";
                7'h5E: seg2chr = "d";  7'h79: seg2chr = "E";
                7'h71: seg2chr = "F";  default: seg2chr = "?";
            endcase
        end
    endfunction

    reg [6:0] exp_seg [0:7];
    integer   errors;
    reg [7:0] cur_sw;

    task wait_frames;
        input [15:0] n;
        integer target;
        begin
            target = frames + n;
            wait (frames >= target);
        end
    endtask

    // press and release the button that drives switch bit b (7 = S1 ... 0 = S8)
    task toggle_bit;
        input [3:0] b;
        begin
            btn[b] = 1'b1;
            wait_frames(3);
            btn[b] = 1'b0;
            wait_frames(3);
        end
    endtask

    task set_switch;
        input [7:0] target;
        reg [7:0] diff;
        integer i;
        begin
            diff = cur_sw ^ target;
            for (i = 7; i >= 0; i = i - 1)
                if (diff[i]) toggle_bit(i);
            cur_sw = target;
        end
    endtask

    task check;
        input [7:0] val;
        integer h, t, o, p, e;
        begin
            h = val / 100;
            t = (val % 100) / 10;
            o = val % 10;

            exp_seg[0] = 7'h00;
            exp_seg[1] = 7'h00;
            exp_seg[2] = hex7(val[7:4]);
            exp_seg[3] = hex7(val[3:0]);
            exp_seg[4] = 7'h00;
            exp_seg[5] = (h == 0)             ? 7'h00 : hex7(h);
            exp_seg[6] = (h == 0 && t == 0)   ? 7'h00 : hex7(t);
            exp_seg[7] = hex7(o);

            e = 0;
            for (p = 0; p < 8; p = p + 1) begin
                if (mem[2*p] !== {1'b0, exp_seg[p]}) begin
                    e = e + 1;
                    $display("  digit %0d: got %h expected %h", p+1, mem[2*p], {1'b0, exp_seg[p]});
                end
                if (mem[2*p+1] !== {7'b0, val[7-p]}) begin
                    e = e + 1;
                    $display("  LED   %0d: got %h expected %h", p+1, mem[2*p+1], {7'b0, val[7-p]});
                end
            end

            $display("switch=%b  display: [%c%c%c%c] [%c%c%c%c]  LEDs=%b%b%b%b%b%b%b%b  %s",
                val,
                seg2chr(mem[0]),  seg2chr(mem[2]),  seg2chr(mem[4]),  seg2chr(mem[6]),
                seg2chr(mem[8]),  seg2chr(mem[10]), seg2chr(mem[12]), seg2chr(mem[14]),
                mem[1][0], mem[3][0], mem[5][0], mem[7][0],
                mem[9][0], mem[11][0], mem[13][0], mem[15][0],
                (e == 0) ? "PASS" : "FAIL");
            errors = errors + e;
        end
    endtask

    // ---------------------------------------------------------------------
    // Test sequence
    // ---------------------------------------------------------------------
    initial begin
        $dumpfile("build/top_tm1638_demo_tb.vcd");
        $dumpvars(0, top_tm1638_demo_tb);

        errors = 0;
        cur_sw = 8'h00;

        wait_frames(3);                       // power-on frames
        check(8'h00);

        set_switch(8'b10101010); check(8'b10101010);   // AA / 170 (from the task sheet)
        set_switch(8'b11111111); check(8'b11111111);   // FF / 255 (from the task sheet)
        set_switch(8'h00);       check(8'h00);         // 00 /   0
        set_switch(8'h05);       check(8'h05);         // 05 /   5
        set_switch(8'h0A);       check(8'h0A);         // 0A /  10
        set_switch(8'h63);       check(8'h63);         // 63 /  99
        set_switch(8'h64);       check(8'h64);         // 64 / 100
        set_switch(8'hC8);       check(8'hC8);         // C8 / 200

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED: %0d mismatches", errors);
        $finish;
    end

    // watchdog
    initial begin
        #200_000_000;
        $display("TIMEOUT - simulation did not finish");
        $finish;
    end

endmodule
