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
  
  initial begin
    clk = 0;
    forever #10 clk = ~clk;
  end
  
  integer i;
  
  initial begin
    $display("=== Mini 5-Point Stencil (4x4) ===");
    
    ena = 1; rst_n = 0; ui_in = 0; uio_in = 0;
    #50; rst_n = 1; #50;
    
    // Config: alpha = 0.5
    ui_in = 8'b11_000000; uio_in = 8'b00000001;
    #20;
    
    // Write hot spots at center cells (5,6,9,10)
    $display("Writing hot spot...");
    ui_in = 8'b01_000101; uio_in = 8'b00000111;  // Cell 5 = 7
    #20;
    ui_in = 8'b01_000110; uio_in = 8'b00000111;  // Cell 6 = 7
    #20;
    ui_in = 8'b01_001001; uio_in = 8'b00000111;  // Cell 9 = 7
    #20;
    ui_in = 8'b01_001010; uio_in = 8'b00000111;  // Cell 10 = 7
    #20;
    
    // Run for 100 iterations
    $display("Running simulation...");
    ui_in = 8'b00_000000;
    #(16 * 20 * 10);  // 10 full sweeps
    
    // Read center
    ui_in = 8'b10_000101;  // Read cell 5
    #40;
    $display("Cell 5 temp = %d", uio_out[2:0]);
    
    $display("Test complete!");
    #100; $finish;
  end
  
endmodule