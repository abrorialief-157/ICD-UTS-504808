// tm1638.v -- one-byte serial transfer engine for TM1638.
// Bits are transferred LSB first. STB is controlled by the top-level FSM,
// so several bytes can be kept inside one TM1638 transaction.
module tm1638 #(
    parameter integer CLK_DIV = 8  // half-period in 12 MHz clocks (~1 MHz CLK)
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire       read_mode,   // 0 = transmit tx_data, 1 = receive byte
    input  wire [7:0] tx_data,
    output reg  [7:0] rx_data,
    output reg        busy,
    output reg        done,
    output reg        tm_clk,
    output reg        dio_out,
    output reg        dio_oe,
    input  wire       dio_in
);
    reg [7:0] shift;
    reg [2:0] bit_count;
    reg [15:0] divider;
    reg phase; // 0: CLK low/setup, 1: CLK high/sample

    always @(posedge clk) begin
        if (rst) begin
            shift <= 8'h00;
            bit_count <= 3'd0;
            divider <= 0;
            phase <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            tm_clk <= 1'b1;
            dio_out <= 1'b1;
            dio_oe <= 1'b1;
            rx_data <= 8'h00;
        end else begin
            done <= 1'b0;
            if (!busy) begin
                tm_clk <= 1'b1;
                divider <= 0;
                if (start) begin
                    busy <= 1'b1;
                    bit_count <= 0;
                    phase <= 1'b0;
                    tm_clk <= 1'b0;
                    shift <= tx_data;
                    dio_oe <= !read_mode;
                    dio_out <= tx_data[0];
                end
            end else begin
                if (divider >= CLK_DIV-1) begin
                    divider <= 0;
                    if (!phase) begin
                        // Rising edge: TM1638 samples transmitted data; FPGA
                        // samples returned data on this edge during reads.
                        tm_clk <= 1'b1;
                        phase <= 1'b1;
                        if (read_mode) shift <= {dio_in, shift[7:1]};
                    end else begin
                        tm_clk <= 1'b0;
                        phase <= 1'b0;
                        if (bit_count == 3'd7) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            tm_clk <= 1'b1;
                            rx_data <= shift;
                            dio_oe <= 1'b1;
                        end else begin
                            bit_count <= bit_count + 1'b1;
                            if (!read_mode) begin
                                shift <= {1'b0, shift[7:1]};
                                dio_out <= shift[1];
                            end
                        end
                    end
                end else divider <= divider + 1'b1;
            end
        end
    end
endmodule
