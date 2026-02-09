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
    $display("=== Enhanced 8x8 Heat Solver ===");
    
    ena = 1; rst_n = 0; ui_in = 0; uio_in = 0;
    #50; rst_n = 1; #50;
    
    // Configure alpha = 0.25
    ui_in = 8'b11_000000; uio_in = 8'b00000010;
    #20;
    
    // Enable heat source at center
    ui_in = 8'b11_000101; uio_in = 8'b00000001;
    #20;
    
    // Initialize with pattern
    ui_in = 8'b11_000111; uio_in = 8'b00000001;
    #20;
    
    // Run simulation
    $display("Running...");
    ui_in = 8'b00_000000;
    #(64 * 20 * 20);  // 20 iterations
    
    // Read max temp location
    ui_in = 8'b10_000000;
    #40;
    $display("Max temp at cell: %d", uo_out[5:0]);
    
    $display("Complete!");
    #100; $finish;
  end
endmodule