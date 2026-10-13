`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// top : M3/M4 - AD7606 read + DAC test signal
//
//   DAC  : DAC_TEST_MODE 1 -> sawtooth 0~4.1V on OUT1 (DAC ch A)
//   ADC  : 8ch @ 200kSPS, +-5V range, results in adc_ch_data
//   M4   : wire DAC OUT1 -> ADC IN1, watch adc_v1 ramp in ILA
//          (signals with mark_debug are picked up by "Set Up Debug")
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

    localparam DAC_TEST_MODE = 1;     // sawtooth on OUT1

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

    dac_ctrl #(.MODE(DAC_TEST_MODE), .INIT_WAIT(1000)) u_dac_ctrl (
        .clk(clk), .rst_n(rst_n),
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
    // debug taps for ILA (M4)
    // ------------------------------------------------------------------
    (* mark_debug = "true" *) wire [15:0] adc_v1 = adc_ch_data[15:0];
    (* mark_debug = "true" *) wire [15:0] adc_v2 = adc_ch_data[31:16];
    (* mark_debug = "true" *) wire        dbg_valid    = adc_valid;
    (* mark_debug = "true" *) wire        dbg_frst_err = adc_frst_err;
    (* mark_debug = "true" *) wire        dbg_overrun  = adc_overrun;

endmodule
