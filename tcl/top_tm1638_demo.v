// top_tm1638_demo.v -- iCESugar V1.5 + TM1638 LED/Key module
// Pushbuttons are momentary: pressed bits appear on display while held,
// and return to zero after release. Hex is shown on digits 3-4; decimal on 6-8.
module top_tm1638_demo(
    input  wire clock,
    output reg  tm_cs,
    output wire tm_clk,
    inout  wire tm_dio
);
    localparam [3:0] IDLE=0, READ_CMD=1, READ_B0=2, READ_B1=3,
        READ_B2=4, READ_B3=5, WRITE_CMD=6, WRITE_ADDR=7,
        WRITE_DATA=8, DISP_CMD=9;

    reg [3:0] state;
    reg rst = 1'b1;
    reg start;
    reg read_mode;
    reg [7:0] tx_data;
    wire [7:0] rx_data;
    wire busy, done, dio_out, dio_oe;
    wire dio_in;
    reg [7:0] keys;
    reg [7:0] key0, key1, key2, key3;
    reg [4:0] data_index;
    reg [7:0] sw;
    reg [7:0] display_byte;
    reg [3:0] hex_hi, hex_lo, hundreds, tens, ones;
    reg [3:0] digit_index;
    reg [7:0] led_keys;
    reg [7:0] data_mem [0:15];
    integer i;
    reg [7:0] bcd_work;

    // Open-drain style shared DIO pin. TM1638 drives during key reads.
    assign tm_dio = dio_oe ? dio_out : 1'bz;
    assign dio_in = tm_dio;

    tm1638 #(.CLK_DIV(5)) serial_byte (
        .clk(clock), .rst(rst), .start(start), .read_mode(read_mode),
        .tx_data(tx_data), .rx_data(rx_data), .busy(busy), .done(done),
        .tm_clk(tm_clk), .dio_out(dio_out), .dio_oe(dio_oe), .dio_in(dio_in)
    );

    function [7:0] seg;
        input [3:0] n;
        begin
            case (n)
                0:seg=8'h3f; 1:seg=8'h06; 2:seg=8'h5b; 3:seg=8'h4f;
                4:seg=8'h66; 5:seg=8'h6d; 6:seg=8'h7d; 7:seg=8'h07;
                8:seg=8'h7f; 9:seg=8'h6f; 10:seg=8'h77; 11:seg=8'h7c;
                12:seg=8'h39; 13:seg=8'h5e; 14:seg=8'h79; default:seg=8'h71;
            endcase
        end
    endfunction

    // Convert an 8-bit value to three decimal digits (combinational).
    always @* begin
        hundreds = sw / 100;
        tens = (sw % 100) / 10;
        ones = sw % 10;
        hex_hi = sw[7:4];
        hex_lo = sw[3:0];
        data_mem[0]  = 8'h00;             data_mem[1]  = keys[7];
        data_mem[2]  = 8'h00;             data_mem[3]  = keys[6];
        data_mem[4]  = seg(hex_hi);       data_mem[5]  = keys[5];
        data_mem[6]  = seg(hex_lo);       data_mem[7]  = keys[4];
        data_mem[8]  = 8'h00;             data_mem[9]  = keys[3];
        data_mem[10] = (hundreds==0) ? 8'h00 : seg(hundreds);
        data_mem[11] = keys[2];
        data_mem[12] = (hundreds==0 && tens==0) ? 8'h00 : seg(tens);
        data_mem[13] = keys[1];
        data_mem[14] = seg(ones);         data_mem[15] = keys[0];
    end

    // Power-on reset, held for a few clock cycles.
    reg [3:0] reset_count = 4'h0;
    always @(posedge clock) begin
        if (reset_count != 4'hf) begin
            reset_count <= reset_count + 1'b1;
            rst <= 1'b1;
        end else rst <= 1'b0;
    end

    // Transaction controller. Each byte transfer is started only after the
    // previous one completes; STB remains low for a complete command/data burst.
    reg waiting;
    reg [2:0] read_index;
    reg [4:0] write_index;
    always @(posedge clock) begin
        if (rst) begin
            state <= IDLE; tm_cs <= 1'b1; start <= 1'b0;
            read_mode <= 1'b0; tx_data <= 0; keys <= 0; sw <= 0;
            key0 <= 0; key1 <= 0; key2 <= 0; key3 <= 0;
            waiting <= 0; read_index <= 0; write_index <= 0;
        end else begin
            start <= 1'b0;
            case (state)
                IDLE: begin
                    // Read four key-scan bytes using command 0x42.
                    tm_cs <= 1'b0; read_mode <= 1'b0; tx_data <= 8'h42;
                    start <= 1'b1; waiting <= 1'b1; state <= READ_CMD;
                end
                READ_CMD: if (done) begin
                    read_mode <= 1'b1; start <= 1'b1; waiting <= 1'b1; state <= READ_B0;
                end
                READ_B0: if (done) begin key0 <= rx_data; start <= 1'b1; state <= READ_B1; end
                READ_B1: if (done) begin key1 <= rx_data; start <= 1'b1; state <= READ_B2; end
                READ_B2: if (done) begin key2 <= rx_data; start <= 1'b1; state <= READ_B3; end
                READ_B3: if (done) begin
                    key3 <= rx_data;
                    // For the standard TM1638 LED&KEY board, button bits are
                    // the K1/K2 positions in each byte; combine byte bit 0/4.
                    keys <= {key0[0], key1[0], key2[0], rx_data[0],
                             key0[4], key1[4], key2[4], rx_data[4]};
                    sw <= {key0[0], key1[0], key2[0], rx_data[0],
                           key0[4], key1[4], key2[4], rx_data[4]};
                    tm_cs <= 1'b1; read_mode <= 1'b0; state <= WRITE_CMD;
                end
                WRITE_CMD: begin
                    tm_cs <= 1'b0; tx_data <= 8'h40; read_mode <= 1'b0;
                    start <= 1'b1; state <= WRITE_ADDR;
                end
                WRITE_ADDR: if (done) begin
                    // End command transaction, then begin address+data burst.
                    tm_cs <= 1'b1; state <= WRITE_DATA; write_index <= 0;
                end
                WRITE_DATA: begin
                    if (write_index == 0) begin
                        tm_cs <= 1'b0; tx_data <= 8'hc0; start <= 1'b1;
                        write_index <= 1; waiting <= 1;
                    end else if (done) begin
                        if (write_index <= 16) begin
                            tx_data <= data_mem[write_index-1];
                            start <= 1'b1;
                            write_index <= write_index + 1'b1;
                        end else begin
                            tm_cs <= 1'b1; state <= DISP_CMD; waiting <= 1'b0;
                        end
                    end
                end
                DISP_CMD: begin
                    if (!waiting) begin
                        tm_cs <= 1'b0; tx_data <= 8'h8f; read_mode <= 1'b0;
                        start <= 1'b1; waiting <= 1'b1;
                    end else if (done) begin
                        tm_cs <= 1'b1; waiting <= 1'b0; state <= IDLE;
                    end
                end
                default: begin tm_cs <= 1'b1; state <= IDLE; end
            endcase
        end
    end
endmodule
