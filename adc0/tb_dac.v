`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_dac : simulation for dac_ctrl + dac_spi (no clk_wiz needed)
//
//  - simple DAC128S085 receiver model : shifts MOSI on SCLK falling edge
//    while SYNC low, latches word on SYNC rising edge
//  - checks : 16 bits per frame, t_SS (SYNC fall -> 1st SCLK fall >= 10ns),
//             t_SYNC (SYNC high time >= 15ns)
//  - expected (MODE=1) : 9000, 0000, 0001, 0002, ...
//
//  Vivado : add as simulation source, set as top, Run Behavioral Simulation,
//           check Tcl console messages.
//////////////////////////////////////////////////////////////////////////////////

module tb_dac;

    localparam MODE = 1;            // 0 : expect 9000, C800   1 : sawtooth

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;           // 100MHz

    wire        start, busy, done;
    wire [15:0] data;
    wire        sync_n, sclk, mosi;

    dac_ctrl #(.MODE(MODE), .INIT_WAIT(20)) u_ctrl (
        .clk(clk), .rst_n(rst_n),
        .start(start), .data(data), .busy(busy), .done(done));

    dac_spi #(.HALF(2)) u_spi (
        .clk(clk), .rst_n(rst_n),
        .start(start), .data(data), .busy(busy), .done(done),
        .sync_n(sync_n), .sclk(sclk), .mosi(mosi));

    // ------------------------------------------------------------------
    // DAC receiver model
    // ------------------------------------------------------------------
    reg [15:0] rx;
    integer    nbits  = 0;
    integer    nframe = 0;
    integer    errors = 0;
    realtime   t_sync_fall, t_sync_rise;
    reg        first_fall;

    always @(negedge sync_n) begin
        t_sync_fall = $realtime;
        if (nframe > 0 && (t_sync_fall - t_sync_rise) < 15.0) begin
            $display("ERROR t_SYNC: SYNC high only %0.1f ns", t_sync_fall - t_sync_rise);
            errors = errors + 1;
        end
        nbits      = 0;
        first_fall = 1'b1;
    end

    always @(negedge sclk) begin
        if (!sync_n) begin
            if (first_fall && ($realtime - t_sync_fall) < 10.0) begin
                $display("ERROR t_SS: %0.1f ns", $realtime - t_sync_fall);
                errors = errors + 1;
            end
            first_fall = 1'b0;
            rx    = {rx[14:0], mosi};
            nbits = nbits + 1;
        end
    end

    // expected word for frame n
    function [15:0] expected(input integer n);
        if (n == 0)        expected = 16'h9000;
        else if (MODE == 0) expected = 16'hC800;
        else               expected = {4'h0, n[11:0] - 12'd1};
    endfunction

    always @(posedge sync_n) begin
        if (rst_n) begin
            t_sync_rise = $realtime;
            if (nbits != 16) begin
                $display("ERROR frame %0d: %0d bits (expected 16)", nframe, nbits);
                errors = errors + 1;
            end
            if (rx !== expected(nframe)) begin
                $display("ERROR frame %0d: got %h, expected %h", nframe, rx, expected(nframe));
                errors = errors + 1;
            end else if (nframe < 6) begin
                $display("frame %0d : %h  OK  (t=%0.0f ns)", nframe, rx, $realtime);
            end
            nframe = nframe + 1;
        end
    end

    // ------------------------------------------------------------------
    initial begin
        #100 rst_n = 1'b1;
        #(MODE == 0 ? 5000 : 30000);
        $display("---- %0d frames, %0d errors ----", nframe, errors);
        $finish;
    end

endmodule
