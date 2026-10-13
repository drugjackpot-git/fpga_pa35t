`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_adc : simulation for adc_ctrl with a simple AD7606 behavioral model
//
//  AD7606 model
//   - CONVST rising : BUSY high after 40ns, low after t_CONV (4000ns)
//   - CS low & RD falling : DB = next channel after 20ns (t14 access time)
//                           FRSTDATA high only while V1 is on the bus
//   - CS high : DB / FRSTDATA = Z, channel pointer back to V1
//   - conversion n, channel k (0..7) returns  { k[2:0], 1'b0, n[11:0] }
//     -> easy to see channel order and conversion count in the waveform
//
//  checks : RESET width >= 50ns, CONVST period = 5us, RD low >= 24ns,
//           RD high >= 15ns, no RD while BUSY, received data == expected
//
//  Vivado : add as simulation source, Set as Top, Run Behavioral Simulation,
//           then "run all" in the Tcl console.
//////////////////////////////////////////////////////////////////////////////////

module tb_adc;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;               // 100MHz

    wire         adc_reset, adc_convst, adc_cs_n, adc_rd_n;
    wire         adc_busy, adc_frstdata;
    wire [15:0]  adc_db;
    wire [2:0]   adc_os;
    wire         adc_range, adc_par_ser;
    wire [127:0] ch_data;
    wire         data_valid, frst_err, overrun;

    adc_ctrl dut (
        .clk(clk), .rst_n(rst_n),
        .adc_reset(adc_reset), .adc_convst(adc_convst),
        .adc_cs_n(adc_cs_n), .adc_rd_n(adc_rd_n),
        .adc_busy(adc_busy), .adc_frstdata(adc_frstdata), .adc_db(adc_db),
        .adc_os(adc_os), .adc_range(adc_range), .adc_par_ser(adc_par_ser),
        .ch_data(ch_data), .data_valid(data_valid),
        .frst_err(frst_err), .overrun(overrun));

    // ==================================================================
    // AD7606 behavioral model
    // ==================================================================
    localparam real T_CONV = 4000.0;

    reg        busy_m  = 1'b0;
    reg [15:0] dout    = 16'h0000;
    reg        frst_m  = 1'b0;
    reg        drive   = 1'b0;
    integer    rd_idx  = 0;
    integer    conv_n  = -1;            // index of last conversion
    integer    errors  = 0;

    assign adc_busy     = busy_m;
    assign adc_db       = drive ? dout   : 16'hzzzz;
    assign adc_frstdata = drive ? frst_m : 1'bz;

    function [15:0] sample(input integer n, input integer k);
        sample = {k[2:0], 1'b0, n[11:0]};
    endfunction

    // RESET width
    realtime t_rst_rise;
    always @(posedge adc_reset) t_rst_rise = $realtime;
    always @(negedge adc_reset)
        if ($realtime - t_rst_rise < 50.0) begin
            $display("ERROR RESET width %0.1f ns", $realtime - t_rst_rise);
            errors = errors + 1;
        end

    // conversion
    realtime t_conv_prev = -1.0;
    always @(posedge adc_convst) begin
        if (rst_n && !adc_reset) begin
            if (t_conv_prev > 0.0 && ($realtime - t_conv_prev) != 5000.0) begin
                $display("ERROR CONVST period %0.1f ns", $realtime - t_conv_prev);
                errors = errors + 1;
            end
            t_conv_prev = $realtime;
            conv_n = conv_n + 1;
            #40      busy_m = 1'b1;
            #(T_CONV - 40.0) busy_m = 1'b0;
        end
    end

    // parallel read
    realtime t_rd_fall, t_rd_rise;
    always @(negedge adc_rd_n) begin
        t_rd_fall = $realtime;
        if (!adc_cs_n) begin
            if (busy_m) begin
                $display("ERROR RD while BUSY at %0.0f ns", $realtime);
                errors = errors + 1;
            end
            if (rd_idx > 0 && ($realtime - t_rd_rise) < 15.0) begin
                $display("ERROR RD high %0.1f ns", $realtime - t_rd_rise);
                errors = errors + 1;
            end
            #6  drive = 1'b0;                       // old data hold (t15)
            #14 begin                               // new data valid 20ns after RD fall
                drive  = 1'b1;
                dout   = sample(conv_n, rd_idx);
                frst_m = (rd_idx == 0);
                rd_idx = rd_idx + 1;
            end
        end
    end

    always @(posedge adc_rd_n) begin
        t_rd_rise = $realtime;
        if (!adc_cs_n && ($realtime - t_rd_fall) < 24.0) begin
            $display("ERROR RD low %0.1f ns", $realtime - t_rd_fall);
            errors = errors + 1;
        end
    end

    always @(posedge adc_cs_n) begin
        drive  = 1'b0;
        rd_idx = 0;
    end

    // ==================================================================
    // check results
    // ==================================================================
    integer nvalid = 0;
    integer k;
    always @(posedge clk) begin
        if (data_valid) begin
            for (k = 0; k < 8; k = k + 1)
                if (ch_data[16*k +: 16] !== sample(conv_n, k)) begin
                    $display("ERROR conv %0d V%0d : got %h expected %h",
                             conv_n, k+1, ch_data[16*k +: 16], sample(conv_n, k));
                    errors = errors + 1;
                end
            if (nvalid < 3)
                $display("conv %0d @%0.0f ns : V1=%h V2=%h V3=%h V4=%h V5=%h V6=%h V7=%h V8=%h",
                    conv_n, $realtime,
                    ch_data[15:0],   ch_data[31:16],  ch_data[47:32],  ch_data[63:48],
                    ch_data[79:64],  ch_data[95:80],  ch_data[111:96], ch_data[127:112]);
            nvalid = nvalid + 1;
        end
    end

    initial begin
        #100 rst_n = 1'b1;
        #60000;
        if (frst_err) begin $display("ERROR frst_err set"); errors = errors + 1; end
        if (overrun)  begin $display("ERROR overrun set");  errors = errors + 1; end
        $display("---- %0d conversions read, %0d errors ----", nvalid, errors);
        $finish;
    end

endmodule
