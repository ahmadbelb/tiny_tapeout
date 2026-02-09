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
    $display("=== Tiny 5-Point Stencil Solver (8x8) ===");
    
    ena = 1; rst_n = 0; ui_in = 0; uio_in = 0;
    #50; rst_n = 1; #50;
    
    // Config: alpha = 0.25
    ui_in = 8'b11_000000; uio_in = 8'b00000001;
    #20;
    
    // Write hot spot at center (4,4) = address 36
    $display("Writing hot spot...");
    for (i = 27; i < 45; i = i + 1) begin
      ui_in = {2'b01, i[5:0]};
      uio_in = 8'b00001111;  // Max temp (15)
      #20;
    end
    
    // Run
    $display("Running...");
    ui_in = 8'b00_000000;
    #(64 * 20 * 5);  // 5 iterations
    
    // Read center
    ui_in = 8'b10_100100;  // Read addr 36
    #40;
    $display("Center = %d", uio_out[3:0]);
    
    $display("Done!");
    #100; $finish;
  end
  
endmodule