`default_nettype none
`timescale 1ns / 1ps

module tb ();
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end
  
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  
  tt_um_ahmadbelb_TUMVGA solver (
      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );
  
  // Clock generation
  initial begin
    clk = 0;
    forever #10 clk = ~clk;
  end
  
  integer i;
  
  initial begin
    $display("=== 5-Point Stencil Heat Solver Test ===");
    
    ena = 1;
    rst_n = 0;
    ui_in = 0;
    uio_in = 0;
    #50;
    rst_n = 1;
    #50;
    
    // Configure: alpha = 64 (0.25)
    $display("Configuring solver...");
    ui_in = 8'b11_000000;
    uio_in = 8'd64;
    #20;
    
    // Write hot spot at center (8,8) = address 136
    $display("Writing initial condition...");
    ui_in = 8'b01_000000;  // Write mode
    
    for (i = 120; i < 152; i = i + 1) begin
      ui_in = {2'b01, i[5:0]};
      uio_in = 8'd255;
      #20;
    end
    
    // Run simulation
    $display("Running simulation...");
    ui_in = 8'b00_000000;
    #(256 * 20 * 10);  // 10 iterations
    
    // Read center
    $display("Reading results...");
    ui_in = 8'b10_001000;  // Read address 136
    #40;
    $display("Center temp = %d", uio_out);
    
    $display("Test complete!");
    #100;
    $finish;
  end
  
endmodule