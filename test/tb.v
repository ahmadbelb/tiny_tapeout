`default_nettype none
`timescale 1ns / 1ps

module tb ();
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end
  
  reg clk, rst_n, ena;
  reg [7:0] ui_in, uio_in;
  wire [7:0] uo_out, uio_out, uio_oe;
  
  tt_um_ahmadbelb_TUMVGA solver (
      .ui_in(ui_in), .uo_out(uo_out),
      .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
      .ena(ena), .clk(clk), .rst_n(rst_n)
  );
  
  initial clk = 0;
  always #10 clk = ~clk;
  
  integer i;
  
  initial begin
    $display("=== 6x6 Heat Solver Test ===");
    
    ena = 1; rst_n = 0; ui_in = 0; uio_in = 0;
    #50; rst_n = 1; #50;
    
    // Config
    ui_in = 8'b11_000000; uio_in = 8'b00000010;  // alpha=2
    #20;
    
    // Write hot spot at center (cells 14,15,20,21)
    $display("Writing hot spot...");
    ui_in = 8'b01_001110; uio_in = 8'b00001111; #20;  // Cell 14
    ui_in = 8'b01_001111; uio_in = 8'b00001111; #20;  // Cell 15
    ui_in = 8'b01_010100; uio_in = 8'b00001111; #20;  // Cell 20
    ui_in = 8'b01_010101; uio_in = 8'b00001111; #20;  // Cell 21
    
    // Run
    $display("Running 15 iterations...");
    ui_in = 8'b00_000000;
    #(36 * 20 * 15);  // 15 iterations
    
    // Read center
    ui_in = 8'b10_001110;
    #40;
    $display("Center temp = %d", uio_out[3:0]);
    
    $display("Complete!");
    #100; $finish;
  end
endmodule