`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// dac_spi : DAC128S085 SPI 16-bit frame transmitter
//
//  - clk 100MHz, SCLK = clk / (2*HALF)  (HALF=2 -> 25MHz, max 30MHz)
//  - SCLK idles HIGH. DAC samples DIN on SCLK FALLING edge,
//    so MOSI is changed together with the SCLK RISING edge.
//  - Frame : SYNC low -> 16 falling edges -> SYNC high (command executes)
//
//  sync_n  ‾‾‾\______________________ ... ________/‾‾‾‾‾‾‾‾‾
//  sclk    ‾‾‾‾‾‾‾\___/‾‾‾\___/‾‾‾ ... ‾‾‾\___/‾‾‾‾‾‾‾‾‾‾‾‾
//  mosi    ===X D15   X D14   X   ...  X D0    X=========
//                  ^ DAC samples here (falling edge)
//
//  Usage : pulse `start` for 1 clk while busy==0, wait for `done` pulse.
//////////////////////////////////////////////////////////////////////////////////

module dac_spi #(
    parameter HALF = 2              // SCLK half period in clk cycles
)(
    input             clk,
    input             rst_n,

    input             start,        // 1-clk pulse, accepted only when busy==0
    input      [15:0] data,         // frame to send (MSB first)
    output reg        busy,
    output reg        done,         // 1-clk pulse at end of frame

    output reg        sync_n,       // DAC SYNC (active low)
    output reg        sclk,
    output reg        mosi
);

    localparam S_IDLE  = 2'd0,
               S_SHIFT = 2'd1,
               S_END   = 2'd2,
               S_GAP   = 2'd3;

    localparam GAP_CYC = 2;         // keep SYNC high >= 15ns (datasheet t_SYNC)

    reg [1:0]  state;
    reg [15:0] shreg;
    reg [3:0]  bitcnt;              // 0..15
    reg [3:0]  ph;                  // phase within one bit : 0 .. 2*HALF-1
    reg [3:0]  gapcnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            state  <= S_IDLE;
            shreg  <= 16'd0;
            bitcnt <= 4'd0;
            ph     <= 4'd0;
            gapcnt <= 4'd0;
            busy   <= 1'b0;
            done   <= 1'b0;
            sync_n <= 1'b1;
            sclk   <= 1'b1;
            mosi   <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
            // ------------------------------------------------------------
            S_IDLE: begin
                sync_n <= 1'b1;
                sclk   <= 1'b1;
                if (start) begin
                    shreg  <= data;
                    mosi   <= data[15];     // first bit ready before 1st falling edge
                    sync_n <= 1'b0;         // frame start
                    bitcnt <= 4'd0;
                    ph     <= 4'd0;
                    busy   <= 1'b1;
                    state  <= S_SHIFT;
                end
            end

            // ------------------------------------------------------------
            // per bit : ph 0..HALF-1 -> SCLK high, ph HALF..2*HALF-1 -> SCLK low
            S_SHIFT: begin
                if (ph == HALF-1)
                    sclk <= 1'b0;               // falling edge : DAC samples mosi

                if (ph == 2*HALF-1) begin
                    ph   <= 4'd0;
                    sclk <= 1'b1;               // rising edge
                    if (bitcnt == 4'd15) begin
                        state <= S_END;         // 16 falling edges done
                    end else begin
                        bitcnt <= bitcnt + 4'd1;
                        shreg  <= {shreg[14:0], 1'b0};
                        mosi   <= shreg[14];    // next bit changes on rising edge
                    end
                end else begin
                    ph <= ph + 4'd1;
                end
            end

            // ------------------------------------------------------------
            S_END: begin
                sync_n <= 1'b1;                 // SYNC rise -> command executes
                mosi   <= 1'b0;                 // DIN idle low (datasheet recommendation)
                gapcnt <= 4'd0;
                state  <= S_GAP;
            end

            // ------------------------------------------------------------
            S_GAP: begin
                if (gapcnt == GAP_CYC-1) begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end else begin
                    gapcnt <= gapcnt + 4'd1;
                end
            end
            endcase
        end
    end

endmodule
