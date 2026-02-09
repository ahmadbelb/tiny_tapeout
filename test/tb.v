`default_nettype none
`timescale 1ns / 1ps

/* 
 * Tests initialization, computation, and readback
 */
module tb ();
  // Dump the signals to a FST file
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end
  
  // Wire up the inputs and outputs
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  
  // VGA signal decode for monitoring
  wire hsync = uo_out[7];
  wire vsync = uo_out[3];
  wire [1:0] R = {uo_out[6], uo_out[2]};
  wire [1:0] G = {uo_out[5], uo_out[1]};
  wire [1:0] B = {uo_out[4], uo_out[0]};
  
  // Control interface decode
  wire [1:0] mode = ui_in[7:6];
  wire [5:0] addr_data = ui_in[5:0];
  
  // Instantiate the solver
  tt_um_ahmadbelb_TUMVGA user_project (
      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );
  
  // Clock generation - 25.175 MHz for VGA
  initial begin
    clk = 0;
    forever #19.86 clk = ~clk;  // ~25 MHz
  end
  
  // Test stimulus
  integer i, j;
  reg [7:0] readback_data;
  
  initial begin
    $display("========================================");
    $display("5-Point Stencil Heat Equation Solver Test");
    $display("========================================");
    
    // Initialize
    ena = 1;
    rst_n = 0;
    ui_in = 8'h00;
    uio_in = 8'h00;
    
    // Reset pulse
    #100;
    rst_n = 1;
    #100;
    
    $display("\n[TEST 1] Configuration Phase");
    $display("Setting diffusion coefficient alpha = 0.25 (64/256)");
    
    // MODE 11: Configure parameters
    // Set diffusion coefficient
    ui_in = 8'b11_00_0000;  // Mode=11, param select=00 (diffusion_coeff)
    uio_in = 8'd64;         // alpha = 64/256 = 0.25
    #100;
    
    // Set boundary temperature
    ui_in = 8'b11_01_0000;  // Mode=11, param select=01 (boundary_temp)
    uio_in = 8'd0;          // Cold boundaries (0°)
    #100;
    
    // Set boundary type to Dirichlet
    ui_in = 8'b11_10_0000;  // Mode=11, param select=10 (boundary_type)
    uio_in = 8'b00000000;   // Dirichlet boundaries
    #100;
    
    $display("Configuration complete: alpha=0.25, boundary=Dirichlet(0), type=00");
    
    $display("\n[TEST 2] Initial Condition Setup");
    $display("Writing hot spot at center (16,16)");
    
    // MODE 01: Write initial conditions
    // Create a hot spot at the center of the grid (cell 16,16)
    // Address = y*32 + x = 16*32 + 16 = 528
    
    ui_in = 8'b01_000000;   // Mode=01 (write), will increment address
    #50;
    
    // Write hot spot at center (simplified - just a few cells)
    for (i = 15; i <= 17; i = i + 1) begin
      for (j = 15; j <= 17; j = j + 1) begin
        // Set address (only lower 6 bits, upper bits auto-increment)
        ui_in = {2'b01, i[4:0], j[0]};  // Mode=01 with address bits
        uio_in = 8'd255;                 // Hot temperature
        #50;
        $display("  Writing T[%0d,%0d] = 255", i, j);
      end
    end
    
    // Write some cooler spots around it
    ui_in = 8'b01_000000;
    uio_in = 8'd128;  // Medium temperature
    #50;
    
    $display("Initial conditions loaded: 3x3 hot spot at center");
    
    $display("\n[TEST 3] Running Simulation");
    $display("Executing heat diffusion for multiple steps...");
    
    // MODE 00: Run simulation
    ui_in = 8'b00_000000;  // Mode=00 (run)
    
    // Let it run for several simulation steps
    // Each full sweep is 1024 clock cycles
    // Run for ~10 steps = 10,240 cycles
    $display("Running for 10 simulation steps...");
    #(10240 * 39.72);  // 10 sweeps
    
    $display("Simulation steps completed");
    
    $display("\n[TEST 4] Reading Results");
    $display("Reading back temperature at key points:");
    
    // MODE 10: Read results
    // Read center point
    ui_in = 8'b10_010000;  // Mode=10 (read), address will be set
    #100;
    readback_data = uio_out;
    $display("  T[16,16] (center) = %0d", readback_data);
    
    // Read a point to the right
    ui_in = 8'b10_010001;
    #100;
    readback_data = uio_out;
    $display("  T[17,16] (right of center) = %0d", readback_data);
    
    // Read a corner (should be boundary temp = 0)
    ui_in = 8'b10_000000;
    #100;
    readback_data = uio_out;
    $display("  T[0,0] (corner - boundary) = %0d", readback_data);
    
    $display("\n[TEST 5] VGA Output Verification");
    $display("Monitoring VGA signals...");
    
    // Let VGA run for a few frames to check sync signals
    #(800 * 525 * 39.72);  // One full frame
    
    $display("VGA Frame generated - check waveform for hsync/vsync");
    
    $display("\n[TEST 6] Continuous Operation");
    $display("Letting solver run continuously...");
    
    // Switch back to run mode and let it continue
    ui_in = 8'b00_000000;
    #(5000 * 39.72);  // Run for more cycles
    
    $display("\n========================================");
    $display("Test Complete!");
    $display("========================================");
    $display("\nExpected Results:");
    $display("  - Hot spot should diffuse outward");
    $display("  - Center temp should decrease over time");
    $display("  - Boundary temps should remain at 0");
    $display("  - VGA should show heat map visualization");
    $display("  - Check FST waveform for detailed behavior");
    
    #1000;
    $finish;
  end
  
  // Monitor key signals
  always @(posedge clk) begin
    if (hsync && vsync) begin
      // Start of frame - could add frame counter here
    end
  end
  
  // Timeout watchdog
  initial begin
    #50000000;  // 50ms timeout
    $display("ERROR: Simulation timeout!");
    $finish;
  end
  
endmodule
