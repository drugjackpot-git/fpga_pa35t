`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// adc_ctrl : AD7606 parallel-mode controller (8ch simultaneous, 200kSPS)
//
//  clk = 100MHz (10ns)
//  - power-up : RESET high 100ns, then wait 1us
//  - every CYCLE clocks (500 = 5us = 200kSPS) :
//      CONVST low 40ns -> rising edge = sampling instant of all 8 ch
//      wait BUSY high->low (conversion ~4us)
//      CS low, 8 x RD pulses (low 40ns / high 20ns), read V1..V8
//      data_valid pulse, ch_data updated
//
//  CONVST ‾‾\__/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
//  BUSY   _____/‾‾‾‾‾‾‾ ~4us ‾‾‾‾‾‾‾\________________________________
//  CS_n   ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\__________________________/‾‾
//  RD_n   ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\____/‾‾\____/‾‾ ... \____/‾‾
//  DB     ===============================[ V1 ]  [ V2 ]  ...  [ V8 ]==
//
//  ch_data : {V8, V7, ... , V1}, each 16-bit two's complement
//            Vk = ch_data[16*(k-1) +: 16]
//  +-5V range : 1 LSB = 10V / 65536 = 152.6uV
//////////////////////////////////////////////////////////////////////////////////

module adc_ctrl #(
    parameter CYCLE      = 500,     // clocks per conversion (500 -> 200kSPS)
    parameter RESET_CYC  = 10,      // RESET high width  (>= 50ns)
    parameter POST_RST   = 100,     // wait after RESET  (>= 25ns)
    parameter CONVST_LOW = 4,       // CONVST low width  (>= 25ns)
    parameter BUSY_WAIT  = 10,      // ignore BUSY right after CONVST (BUSY rises within 45ns)
    parameter RD_LOW     = 4,       // RD low width      (>= 24ns, data access <= 24ns)
    parameter RD_HIGH    = 2        // RD high width     (>= 15ns)
)(
    input              clk,
    input              rst_n,

    // AD7606 pins
    output reg         adc_reset,
    output reg         adc_convst,
    output reg         adc_cs_n,
    output reg         adc_rd_n,
    input              adc_busy,
    input              adc_frstdata,
    input      [15:0]  adc_db,
    output     [2:0]   adc_os,        // oversampling : off
    output             adc_range,     // 0 : +-5V
    output             adc_par_ser,   // 0 : parallel

    // result
    output reg [127:0] ch_data,       // {V8 ... V1}
    output reg         data_valid,    // 1-clk pulse when ch_data updated
    output reg         frst_err,      // sticky : FRSTDATA was not high on V1
    output reg         overrun        // sticky : conversion slot missed
);

    assign adc_os      = 3'b000;
    assign adc_range   = 1'b0;
    assign adc_par_ser = 1'b0;

    // ------------------------------------------------------------------
    // input registers
    //  - BUSY is asynchronous to clk -> 2-FF synchronizer
    //  - DB / FRSTDATA sampled every clk (packed into IOB flip-flops)
    // ------------------------------------------------------------------
    reg [1:0] busy_sync;
    always @(posedge clk) busy_sync <= {busy_sync[0], adc_busy};
    wire busy_s = busy_sync[1];

    (* IOB = "TRUE" *) reg [15:0] db_r;
    (* IOB = "TRUE" *) reg        frst_r;
    always @(posedge clk) begin
        db_r   <= adc_db;
        frst_r <= adc_frstdata;
    end

    // ------------------------------------------------------------------
    // conversion period counter (free-running -> exact 5us sampling period)
    // ------------------------------------------------------------------
    reg [15:0] tcnt;
    reg        run;                    // set after power-up reset sequence

    always @(posedge clk) begin
        if (!rst_n || !run)
            tcnt <= 16'd0;
        else if (tcnt == CYCLE-1)
            tcnt <= 16'd0;
        else
            tcnt <= tcnt + 16'd1;
    end

    wire slot = run && (tcnt == 16'd0);    // start of each 5us slot

    // ------------------------------------------------------------------
    // main FSM
    // ------------------------------------------------------------------
    localparam S_RESET    = 3'd0,
               S_POSTRST  = 3'd1,
               S_IDLE     = 3'd2,
               S_CONVST   = 3'd3,
               S_BUSYWAIT = 3'd4,
               S_BUSY     = 3'd5,
               S_READ     = 3'd6,
               S_DONE     = 3'd7;

    reg [2:0]   state;
    reg [15:0]  cnt;
    reg [2:0]   ch;            // channel being read : 0..7 (V1..V8)
    reg [3:0]   ph;            // phase within one RD pulse
    reg [127:0] shadow;        // collects 8 channels, copied to ch_data at the end

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= S_RESET;
            cnt        <= 16'd0;
            ch         <= 3'd0;
            ph         <= 4'd0;
            run        <= 1'b0;
            adc_reset  <= 1'b1;
            adc_convst <= 1'b1;
            adc_cs_n   <= 1'b1;
            adc_rd_n   <= 1'b1;
            shadow     <= 128'd0;
            ch_data    <= 128'd0;
            data_valid <= 1'b0;
            frst_err   <= 1'b0;
            overrun    <= 1'b0;
        end else begin
            data_valid <= 1'b0;

            // a new slot arrived but we are still busy with the previous one
            if (slot && state != S_IDLE && run)
                overrun <= 1'b1;

            case (state)
            // ---------------- power-up reset ----------------
            S_RESET: begin
                adc_reset <= 1'b1;
                if (cnt == RESET_CYC-1) begin
                    adc_reset <= 1'b0;
                    cnt       <= 16'd0;
                    state     <= S_POSTRST;
                end else
                    cnt <= cnt + 16'd1;
            end

            S_POSTRST: begin
                if (cnt == POST_RST-1) begin
                    cnt   <= 16'd0;
                    run   <= 1'b1;
                    state <= S_IDLE;
                end else
                    cnt <= cnt + 16'd1;
            end

            // ---------------- wait for next 5us slot ----------------
            S_IDLE: begin
                if (slot) begin
                    adc_convst <= 1'b0;
                    cnt        <= 16'd0;
                    state      <= S_CONVST;
                end
            end

            // CONVST low pulse; rising edge starts conversion
            S_CONVST: begin
                if (cnt == CONVST_LOW-1) begin
                    adc_convst <= 1'b1;
                    cnt        <= 16'd0;
                    state      <= S_BUSYWAIT;
                end else
                    cnt <= cnt + 16'd1;
            end

            // give BUSY time to go high (and pass the synchronizer)
            S_BUSYWAIT: begin
                if (cnt == BUSY_WAIT-1) begin
                    cnt   <= 16'd0;
                    state <= S_BUSY;
                end else
                    cnt <= cnt + 16'd1;
            end

            // wait end of conversion
            S_BUSY: begin
                if (!busy_s) begin
                    adc_cs_n <= 1'b0;
                    ch       <= 3'd0;
                    ph       <= 4'd0;
                    state    <= S_READ;
                end
            end

            // ---------------- 8 x RD pulses ----------------
            //  ph 0            : RD low
            //  ph RD_LOW       : RD high  (db_r sampled the pins at this edge)
            //  ph RD_LOW+1     : store db_r (pins sampled 40ns after RD fall)
            //  ph last         : next channel
            S_READ: begin
                if (ph == 4'd0)
                    adc_rd_n <= 1'b0;

                if (ph == RD_LOW)
                    adc_rd_n <= 1'b1;

                if (ph == RD_LOW+1) begin
                    shadow[16*ch +: 16] <= db_r;
                    if (ch == 3'd0 && !frst_r)
                        frst_err <= 1'b1;
                end

                if (ph == RD_LOW+RD_HIGH-1) begin
                    ph <= 4'd0;
                    if (ch == 3'd7)
                        state <= S_DONE;
                    else
                        ch <= ch + 3'd1;
                end else
                    ph <= ph + 4'd1;
            end

            S_DONE: begin
                adc_cs_n   <= 1'b1;
                ch_data    <= shadow;
                data_valid <= 1'b1;
                state      <= S_IDLE;
            end
            endcase
        end
    end

endmodule
