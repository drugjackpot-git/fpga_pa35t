`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// dac_ctrl : decides WHAT to send to the DAC
//
//  1) wait INIT_WAIT clocks after reset
//  2) send 0x9000  -> switch DAC to WTM (power-up default is WRM:
//                     register writes would NOT update the outputs!)
//  3) MODE 0 : send 0xC800 once  -> broadcast 2048 : all 8 ch ~2.048V (multimeter)
//     MODE 1 : sawtooth on ch A  -> 0x0000, 0x0001, ... 0x0FFF, 0x0000 ... (scope)
//     MODE 2 : alternate frames
//                ch A <- sawtooth          (test signal source)
//                ch B <- in_code[11:0]     (e.g. ADC value converted to DAC code)
//////////////////////////////////////////////////////////////////////////////////

module dac_ctrl #(
    parameter MODE      = 0,
    parameter INIT_WAIT = 1000          // 10us @100MHz
)(
    input             clk,
    input             rst_n,

    input      [11:0] in_code,          // MODE 2 : value for ch B

    // to dac_spi
    output reg        start,
    output reg [15:0] data,
    input             busy,
    input             done
);

    localparam CMD_WTM       = 16'h9000;
    localparam CMD_BROADCAST = 16'hC800;    // 0xC = broadcast, data = 0x800 (2048)

    localparam C_INIT     = 3'd0,
               C_WTM      = 3'd1,
               C_WTM_WAIT = 3'd2,
               C_SEND     = 3'd3,
               C_WAIT     = 3'd4,
               C_STOP     = 3'd5;

    reg [2:0]  state;
    reg [15:0] waitcnt;
    reg [11:0] saw;
    reg        sel_b;                   // MODE 2 : 0 -> ch A frame, 1 -> ch B frame

    always @(posedge clk) begin
        if (!rst_n) begin
            state   <= C_INIT;
            waitcnt <= 16'd0;
            saw     <= 12'd0;
            sel_b   <= 1'b0;
            start   <= 1'b0;
            data    <= 16'd0;
        end else begin
            start <= 1'b0;

            case (state)
            C_INIT: begin
                if (waitcnt == INIT_WAIT-1)
                    state <= C_WTM;
                else
                    waitcnt <= waitcnt + 16'd1;
            end

            C_WTM: begin
                if (!busy) begin
                    data  <= CMD_WTM;
                    start <= 1'b1;
                    state <= C_WTM_WAIT;
                end
            end

            C_WTM_WAIT: begin
                if (done)
                    state <= C_SEND;
            end

            C_SEND: begin
                if (!busy) begin
                    case (MODE)
                        0:       data <= CMD_BROADCAST;
                        1:       data <= {4'h0, saw};                 // ch A
                        default: data <= sel_b ? {4'h1, in_code}      // ch B
                                               : {4'h0, saw};         // ch A
                    endcase
                    start <= 1'b1;
                    state <= C_WAIT;
                end
            end

            C_WAIT: begin
                if (done) begin
                    case (MODE)
                        0: state <= C_STOP;
                        1: begin
                            saw   <= saw + 12'd1;
                            state <= C_SEND;
                        end
                        default: begin
                            if (sel_b)                  // advance sawtooth after each A+B pair
                                saw <= saw + 12'd1;
                            sel_b <= ~sel_b;
                            state <= C_SEND;
                        end
                    endcase
                end
            end

            C_STOP: ;   // nothing more to do

            default: state <= C_INIT;
            endcase
        end
    end

endmodule
