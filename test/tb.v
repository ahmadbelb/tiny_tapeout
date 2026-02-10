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
  
  reg [3:0] readback;
  
  initial begin
    $display("=== 5x5 Heat Solver Debug Test ===");
    
    ena = 1; rst_n = 0; ui_in = 0; uio_in = 0;
    #100; rst_n = 1; #100;
    $display("[RESET] Complete");
    
    // Write cell 12 = 10
    ui_in = {2'b01, 6'd12}; uio_in = 8'd10;
    #100;
    $display("[WRITE] Cell 12 = 10");
    
    // Read back immediately
    ui_in = {2'b10, 6'd12}; 
    #100;
    readback = uio_out[3:0];
    $display("[READ] Cell 12 = %d (expected 10)", readback);
    
    if (readback != 10) begin
      $display("ERROR: Write/Read failed!");
      $finish;
    end
    
    // Write cell 13 = 12
    ui_in = {2'b01, 6'd13}; uio_in = 8'd12;
    #100;
    
    // Run 3 iterations
    $display("[RUN] Starting 3 iterations...");
    ui_in = {2'b00, 6'd0};
    #(25 * 20 * 3);
    
    // Read results
    ui_in = {2'b10, 6'd12};
    #100;
    readback = uio_out[3:0];
    $display("[RESULT] Cell 12 after 3 iter = %d", readback);
    
    ui_in = {2'b10, 6'd7};
    #100;
    $display("[RESULT] Cell 7 (neighbor) = %d", uio_out[3:0]);
    
    ui_in = {2'b10, 6'd0};
    #100;
    $display("[RESULT] Cell 0 (edge) = %d", uio_out[3:0]);
    
    $display("=== Test Complete ===");
    #100; $finish;
  end
endmodule