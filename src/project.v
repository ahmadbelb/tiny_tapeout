/*
 * 5-Point Stencil Heat Equation Solver for Tiny Tapeout
 * Pure computational engine without VGA dependency
 * Copyright (c) 2024 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none
module tt_um_ahmadbelb_TUMVGA(
  input  wire [7:0] ui_in,    // Control/Data inputs
  output wire [7:0] uo_out,   // Data outputs
  input  wire [7:0] uio_in,   // Bidirectional inputs
  output wire [7:0] uio_out,  // Bidirectional outputs
  output wire [7:0] uio_oe,   // Bidirectional enable
  input  wire       ena,      
  input  wire       clk,      
  input  wire       rst_n     
);

  // ========== CONTROL INTERFACE ==========
  // ui_in[7:6] - Mode selection
  //   00: Run simulation
  //   01: Write data (address in ui_in[5:0], data in uio_in)
  //   10: Read data (address in ui_in[5:0], data out on uo_out)
  //   11: Configure parameters
  // ui_in[5:0] - Address/Control bits
  
  wire [1:0] mode = ui_in[7:6];
  wire [5:0] control_bits = ui_in[5:0];
  
  // Output enable: enable outputs when reading
  assign uio_oe = (mode == 2'b10) ? 8'hFF : 8'h00;
  
  // ========== SOLVER PARAMETERS ==========
  parameter GRID_WIDTH = 16;   // 16x16 grid = 256 cells
  parameter GRID_HEIGHT = 16;
  parameter GRID_SIZE = 256;
  parameter ADDR_BITS = 8;
  
  // Simulation state
  reg [7:0] current_cell;
  reg solver_running;
  reg [15:0] iteration_count;
  
  // Temperature storage
  reg [7:0] temperature [0:255];
  
  // Configuration registers
  reg [7:0] alpha;             // Diffusion coefficient (scaled 0-255)
  reg [7:0] boundary_temp;     // Boundary temperature
  reg [1:0] boundary_type;     // 00: Dirichlet, 01: Neumann, 10: Periodic
  
  // I/O state
  reg [7:0] read_address;
  reg [7:0] write_address;
  reg [7:0] data_out_reg;
  
  // ========== 5-POINT STENCIL COMPUTATION ==========
  
  // Current cell coordinates (x, y)
  wire [3:0] cx = current_cell[3:0];   // x: 0-15
  wire [3:0] cy = current_cell[7:4];   // y: 0-15
  
  // Check boundaries
  wire at_left   = (cx == 0);
  wire at_right  = (cx == 15);
  wire at_top    = (cy == 0);
  wire at_bottom = (cy == 15);
  wire at_boundary = at_left | at_right | at_top | at_bottom;
  
  // Neighbor coordinates with boundary handling
  wire [3:0] left_x  = at_left  ? (boundary_type[1] ? 4'd15 : cx) : (cx - 1);
  wire [3:0] right_x = at_right ? (boundary_type[1] ? 4'd0  : cx) : (cx + 1);
  wire [3:0] up_y    = at_top   ? (boundary_type[1] ? 4'd15 : cy) : (cy - 1);
  wire [3:0] down_y  = at_bottom? (boundary_type[1] ? 4'd0  : cy) : (cy + 1);
  
  // Neighbor addresses
  wire [7:0] addr_center = current_cell;
  wire [7:0] addr_left   = {cy, left_x};
  wire [7:0] addr_right  = {cy, right_x};
  wire [7:0] addr_up     = {up_y, cx};
  wire [7:0] addr_down   = {down_y, cx};
  
  // Read temperatures
  wire [7:0] T_c = temperature[addr_center];
  wire [7:0] T_l = temperature[addr_left];
  wire [7:0] T_r = temperature[addr_right];
  wire [7:0] T_u = temperature[addr_up];
  wire [7:0] T_d = temperature[addr_down];
  
  // Laplacian: ∇²T = (T_l + T_r + T_u + T_d - 4*T_c)
  wire [9:0] sum_neighbors = {2'b0, T_l} + {2'b0, T_r} + {2'b0, T_u} + {2'b0, T_d};
  wire [9:0] four_T_c = {T_c, 2'b0};
  
  // Signed laplacian
  wire signed [10:0] laplacian_signed = $signed({1'b0, sum_neighbors}) - $signed({1'b0, four_T_c});
  
  // Apply diffusion: T_new = T_c + (alpha/256) * laplacian / 4
  wire signed [18:0] scaled_laplacian = (laplacian_signed * $signed({1'b0, alpha})) >>> 10;
  wire signed [9:0] T_new_signed = $signed({2'b0, T_c}) + scaled_laplacian[9:0];
  
  // Clamp to [0, 255]
  wire [7:0] T_computed = T_new_signed[9] ? 8'd0 :
                          T_new_signed[8] ? 8'd255 :
                          T_new_signed[7:0];
  
  // Apply boundary condition
  wire is_dirichlet = (boundary_type == 2'b00) && at_boundary;
  wire [7:0] T_new = is_dirichlet ? boundary_temp : T_computed;
  
  // ========== OUTPUT ASSIGNMENTS ==========
  
  // Status output on uo_out when not reading
  assign uo_out = (mode == 2'b10) ? data_out_reg : 
                  {solver_running, mode, 1'b0, iteration_count[11:8]};
  
  // Data output on bidirectional pins
  assign uio_out = data_out_reg;
  
  // ========== MAIN CONTROL LOGIC ==========
  
  integer i;
  
  always @(posedge clk) begin
    if (~rst_n) begin
      // Reset
      solver_running <= 0;
      current_cell <= 0;
      iteration_count <= 0;
      read_address <= 0;
      write_address <= 0;
      data_out_reg <= 0;
      
      // Default configuration
      alpha <= 8'd64;           // α = 0.25
      boundary_temp <= 8'd0;    // Cold boundaries
      boundary_type <= 2'b00;   // Dirichlet
      
      // Initialize grid to zero
      for (i = 0; i < GRID_SIZE; i = i + 1) begin
        temperature[i] <= 8'd0;
      end
      
    end else begin
      
      case (mode)
        
        // MODE 00: Run simulation
        2'b00: begin
          solver_running <= 1;
          
          // Update one cell per clock cycle
          temperature[addr_center] <= T_new;
          
          if (current_cell < GRID_SIZE - 1) begin
            current_cell <= current_cell + 1;
          end else begin
            // Completed one full iteration
            current_cell <= 0;
            iteration_count <= iteration_count + 1;
          end
        end
        
        // MODE 01: Write data
        2'b01: begin
          solver_running <= 0;
          write_address <= {2'b0, control_bits};
          temperature[write_address] <= uio_in;
        end
        
        // MODE 10: Read data
        2'b10: begin
          solver_running <= 0;
          read_address <= {2'b0, control_bits};
          data_out_reg <= temperature[read_address];
        end
        
        // MODE 11: Configure
        2'b11: begin
          solver_running <= 0;
          case (control_bits[1:0])
            2'b00: alpha <= uio_in;
            2'b01: boundary_temp <= uio_in;
            2'b10: boundary_type <= uio_in[1:0];
            2'b11: begin
              // Reset iteration counter
              iteration_count <= 0;
              current_cell <= 0;
            end
          endcase
        end
        
      endcase
      
    end
  end
  
  // Suppress warnings
  wire _unused = &{ena, control_bits[5:2]};
  
endmodule