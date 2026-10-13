`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/13/2026 10:53:16 AM
// Design Name: 
// Module Name: top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module top(
    input clkin_p,
    input clkin_n,
    
    output led
    );


    wire clk;
    wire rst_n;
    
    clk_wiz_0 clkgen (
        .clk_out1(clk),     // output clk_out1
        .locked(rst_n),       // output locked
        .clk_in1_p(clkin_p),    // input clk_in1_p
        .clk_in1_n(clkin_n));    // input clk_in1_n

    reg [25:0] cnt;
    always @(posedge clk)
        if (~rst_n)
            cnt <= 20'd0;
        else
            cnt <= cnt + 20'd1;
    
    assign led = cnt[25];



endmodule
