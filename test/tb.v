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
    $display("=== 5x5 Heat Solver Test ===");
    
    ena = 1; rst_n = 0; ui_in = 0; uio_in = 0;
    #50; rst_n = 1; #50;
    
    // Config alpha=2
    ui_in = 8'b11_00_0000; uio_in = 8'b00000010;
    #20;
    
    // Write hot spot at center (cell 12 = 2,2)
    $display("Writing hot spot at center...");
    ui_in = 8'b01_0_01100; uio_in = 8'b00001111; #20;  // Cell 12
    ui_in = 8'b01_0_01101; uio_in = 8'b00001111; #20;  // Cell 13
    ui_in = 8'b01_0_10001; uio_in = 8'b00001111; #20;  // Cell 17
    ui_in = 8'b01_0_10010; uio_in = 8'b00001111; #20;  // Cell 18
    
    // Run 12 iterations
    $display("Running simulation...");
    ui_in = 8'b00_00_0000;
    #(25 * 20 * 12);
    
    // Read center
    ui_in = 8'b10_0_01100;
    #40;
    $display("Center temp = %d", uio_out[3:0]);
    
    $display("Test complete!");
    #100; $finish;
  end
endmodule