`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// top : M5 - ADC -> DAC loop (follow test)
//
//   DAC OUT1 (ch A) : sawtooth 0~4.1V  (test signal)
//   wire  DAC OUT1  -> ADC IN2
//   ADC V2 (+-5V, 16bit signed) -> DAC code (0~4095, 1mV/LSB) -> DAC OUT2 (ch B)
//   scope : CH1 = OUT1, CH2 = OUT2  -> OUT2 should follow OUT1
//           (5us staircase, delayed by ~5-7us)
//////////////////////////////////////////////////////////////////////////////////

module top(
    input         clkin_p,
    input         clkin_n,

    // DAC128S085 (PZ7606 on JM2)
    output        sync,           // DAC_nSYNC (active low)
    output        sck,
    output        mosi,
    input         miso,           // unused (daisy-chain only)

    // AD7606 (PZ7606 on JM2)
    output        adc_convst,
    output        adc_reset,
    output        adc_cs_n,
    output        adc_rd_n,
    input         adc_busy,
    input         adc_frstdata,
    input  [15:0] adc_db,
    output [2:0]  adc_os,
    output        adc_range,
    output        adc_par_ser,

    output        led
    );

    localparam DAC_TEST_MODE = 2;     // OUT1 sawtooth, OUT2 = ADC V2

    // ------------------------------------------------------------------
    // clock / reset
    // ------------------------------------------------------------------
    wire clk;
    wire locked;

    clk_wiz_0 clkgen (
        .clk_out1 (clk),        // 100MHz
        .locked   (locked),
        .clk_in1_p(clkin_p),
        .clk_in1_n(clkin_n));

    reg [1:0] rst_sync;
    always @(posedge clk or negedge locked)
        if (!locked) rst_sync <= 2'b00;
        else         rst_sync <= {rst_sync[0], 1'b1};

    wire rst_n = rst_sync[1];

    // ------------------------------------------------------------------
    // LED heartbeat
    // ------------------------------------------------------------------
    reg [25:0] cnt;
    always @(posedge clk)
        if (!rst_n) cnt <= 26'd0;
        else        cnt <= cnt + 26'd1;

    assign led = cnt[25];

    // ------------------------------------------------------------------
    // DAC (test signal source)
    // ------------------------------------------------------------------
    wire        dac_start, dac_busy, dac_done;
    wire [15:0] dac_data;
    reg  [11:0] dac_code_b;             // ADC V2 converted to DAC code (see below)

    dac_ctrl #(.MODE(DAC_TEST_MODE), .INIT_WAIT(1000)) u_dac_ctrl (
        .clk(clk), .rst_n(rst_n),
        .in_code(dac_code_b),
        .start(dac_start), .data(dac_data), .busy(dac_busy), .done(dac_done));

    dac_spi #(.HALF(2)) u_dac_spi (
        .clk(clk), .rst_n(rst_n),
        .start(dac_start), .data(dac_data), .busy(dac_busy), .done(dac_done),
        .sync_n(sync), .sclk(sck), .mosi(mosi));

    // ------------------------------------------------------------------
    // ADC
    // ------------------------------------------------------------------
    wire [127:0] adc_ch_data;
    wire         adc_valid, adc_frst_err, adc_overrun;

    adc_ctrl u_adc_ctrl (
        .clk(clk), .rst_n(rst_n),
        .adc_reset(adc_reset), .adc_convst(adc_convst),
        .adc_cs_n(adc_cs_n), .adc_rd_n(adc_rd_n),
        .adc_busy(adc_busy), .adc_frstdata(adc_frstdata), .adc_db(adc_db),
        .adc_os(adc_os), .adc_range(adc_range), .adc_par_ser(adc_par_ser),
        .ch_data(adc_ch_data), .data_valid(adc_valid),
        .frst_err(adc_frst_err), .overrun(adc_overrun));

    // ------------------------------------------------------------------
    // ADC code -> DAC code
    //   ADC (+-5V)   : code = V / 5     * 32768
    //   DAC (4.096V) : code = V / 4.096 * 4096   (= V in mV)
    //   DAC = ADC * 5000 / 32768 = ADC * 625 / 4096   -> (ADC * 625) >>> 12
    //   clamp to 0..4095 (DAC cannot output negative voltage)
    // ------------------------------------------------------------------
    wire signed [15:0] adc_v2_s = adc_ch_data[31:16];
    wire signed [26:0] prod     = adc_v2_s * $signed(11'd625);
    wire signed [14:0] scaled   = prod >>> 12;              // -5000 .. +5000

    always @(posedge clk) begin
        if (!rst_n)
            dac_code_b <= 12'd0;
        else if (adc_valid) begin
            if (scaled < 0)
                dac_code_b <= 12'd0;
            else if (scaled > 15'sd4095)
                dac_code_b <= 12'd4095;
            else
                dac_code_b <= scaled[11:0];
        end
    end

    // ------------------------------------------------------------------
    // debug taps for ILA
    // ------------------------------------------------------------------
    (* mark_debug = "true" *) wire [15:0] adc_v1 = adc_ch_data[15:0];
    (* mark_debug = "true" *) wire [15:0] adc_v2 = adc_ch_data[31:16];
    (* mark_debug = "true" *) wire [11:0] dbg_dac_b    = dac_code_b;
    (* mark_debug = "true" *) wire        dbg_valid    = adc_valid;
    (* mark_debug = "true" *) wire        dbg_frst_err = adc_frst_err;
    (* mark_debug = "true" *) wire        dbg_overrun  = adc_overrun;

endmodule