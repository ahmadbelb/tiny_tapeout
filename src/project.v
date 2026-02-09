/*
 * 5-Point Stencil Heat Equation Solver for Tiny Tapeout
 * Optimized for 99% utilization
 * 8x8 grid, 4-bit temperatures, enhanced features
 * Copyright (c) 2024 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none
module tt_um_ahmadbelb_TUMVGA(
  input  wire [7:0] ui_in,
  output wire [7:0] uo_out,
  input  wire [7:0] uio_in,
  output wire [7:0] uio_out,
  output wire [7:0] uio_oe,
  input  wire       ena,
  input  wire       clk,
  input  wire       rst_n
);

  // ========== CONTROL INTERFACE ==========
  // ui_in[7:6] - Mode: 00=Run, 01=Write, 10=Read, 11=Config
  // ui_in[5:0] - Address (0-63 for cells)
  
  wire [1:0] mode = ui_in[7:6];
  wire [5:0] addr = ui_in[5:0];
  
  assign uio_oe = (mode == 2'b10) ? 8'hFF : 8'h00;
  
  // ========== 8x8 GRID WITH 4-BIT TEMPS ==========
  // 64 cells × 4 bits = 256 flip-flops
  reg [3:0] temp [0:63];
  
  // Simulation state
  reg [5:0] cell_idx;           // Current cell being computed (0-63)
  reg [15:0] iteration_count;   // Iteration counter
  reg solver_active;            // Solver running flag
  
  // Configuration registers
  reg [2:0] alpha;              // Diffusion coefficient (0-7 scale)
  reg [3:0] boundary_temp;      // Boundary temperature (0-15)
  reg boundary_type;            // 0=Dirichlet (fixed), 1=Neumann (insulated)
  
  // Heat sources (can be programmed)
  reg [5:0] heat_source_addr;   // Location of heat source
  reg [3:0] heat_source_temp;   // Heat source temperature
  reg heat_source_enable;       // Enable heat source
  
  // Statistics
  reg [3:0] max_temp;           // Maximum temperature in grid
  reg [5:0] max_temp_cell;      // Cell with max temperature
  
  // ========== COORDINATE CALCULATION ==========
  wire [2:0] cx = cell_idx[2:0];  // x coordinate (0-7)
  wire [2:0] cy = cell_idx[5:3];  // y coordinate (0-7)
  
  wire at_left   = (cx == 0);
  wire at_right  = (cx == 7);
  wire at_top    = (cy == 0);
  wire at_bottom = (cy == 7);
  wire at_edge   = at_left | at_right | at_top | at_bottom;
  
  // ========== NEIGHBOR CALCULATION ==========
  // Boundary handling based on boundary_type
  wire [2:0] left_x  = at_left  ? (boundary_type ? cx : cx) : (cx - 1);
  wire [2:0] right_x = at_right ? (boundary_type ? cx : cx) : (cx + 1);
  wire [2:0] up_y    = at_top   ? (boundary_type ? cy : cy) : (cy - 1);
  wire [2:0] down_y  = at_bottom? (boundary_type ? cy : cy) : (cy + 1);
  
  wire [5:0] addr_center = cell_idx;
  wire [5:0] addr_left   = {cy, left_x};
  wire [5:0] addr_right  = {cy, right_x};
  wire [5:0] addr_up     = {up_y, cx};
  wire [5:0] addr_down   = {down_y, cx};
  
  // ========== 5-POINT STENCIL COMPUTATION ==========
  wire [3:0] T_c = temp[addr_center];
  wire [3:0] T_l = temp[addr_left];
  wire [3:0] T_r = temp[addr_right];
  wire [3:0] T_u = temp[addr_up];
  wire [3:0] T_d = temp[addr_down];
  
  // Sum of 4 neighbors
  wire [5:0] sum_neighbors = {2'b0, T_l} + {2'b0, T_r} + {2'b0, T_u} + {2'b0, T_d};
  wire [3:0] avg_neighbors = sum_neighbors[5:2];  // Divide by 4
  
  // Laplacian approximation: avg_neighbors - T_c
  wire signed [4:0] laplacian = $signed({1'b0, avg_neighbors}) - $signed({1'b0, T_c});
  
  // Apply diffusion: T_new = T_c + (alpha/8) * laplacian
  wire signed [7:0] delta = (laplacian * $signed({5'b0, alpha})) >>> 3;
  wire signed [4:0] T_new_signed = $signed({1'b0, T_c}) + delta[4:0];
  
  // Clamp to [0, 15]
  wire [3:0] T_diffused = T_new_signed[4] ? 4'd0 :       // Negative
                          (T_new_signed > 15) ? 4'd15 :  // Overflow
                          T_new_signed[3:0];
  
  // Apply boundary condition
  wire [3:0] T_boundary = (boundary_type == 0) ? boundary_temp : T_diffused;
  
  // Apply heat source
  wire is_heat_source = heat_source_enable && (cell_idx == heat_source_addr);
  wire [3:0] T_final = is_heat_source ? heat_source_temp :
                       at_edge ? T_boundary : T_diffused;
  
  // ========== OUTPUT SELECTION ==========
  reg [7:0] status_out;
  
  assign uo_out = status_out;
  assign uio_out = {4'b0, temp[addr]};
  
  // ========== MAIN CONTROL LOGIC ==========
  integer i;
  
  always @(posedge clk) begin
    if (~rst_n) begin
      // Reset all state
      cell_idx <= 0;
      iteration_count <= 0;
      solver_active <= 0;
      max_temp <= 0;
      max_temp_cell <= 0;
      
      // Default configuration
      alpha <= 3'd2;              // α = 0.25
      boundary_temp <= 4'd0;      // Cold boundaries
      boundary_type <= 0;         // Dirichlet
      heat_source_addr <= 6'd27;  // Center (3,3)
      heat_source_temp <= 4'd15;  // Max heat
      heat_source_enable <= 0;
      
      status_out <= 0;
      
      // Initialize grid
      for (i = 0; i < 64; i = i + 1) begin
        temp[i] <= 4'd0;
      end
      
    end else begin
      
      case (mode)
        
        // MODE 00: Run simulation
        2'b00: begin
          solver_active <= 1;
          
          // Update current cell
          temp[addr_center] <= T_final;
          
          // Track maximum temperature
          if (T_final > max_temp) begin
            max_temp <= T_final;
            max_temp_cell <= cell_idx;
          end
          
          // Advance to next cell
          if (cell_idx == 63) begin
            cell_idx <= 0;
            iteration_count <= iteration_count + 1;
            max_temp <= 0;  // Reset for next iteration
          end else begin
            cell_idx <= cell_idx + 1;
          end
          
          // Status output: [running, iteration_count[13:8]]
          status_out <= {1'b1, 1'b0, iteration_count[13:8]};
        end
        
        // MODE 01: Write temperature data
        2'b01: begin
          solver_active <= 0;
          temp[addr] <= uio_in[3:0];
          status_out <= {2'b01, addr};
        end
        
        // MODE 10: Read temperature data
        2'b10: begin
          solver_active <= 0;
          // Output on uio_out (assigned above)
          status_out <= {2'b10, max_temp_cell};
        end
        
        // MODE 11: Configure parameters
        2'b11: begin
          solver_active <= 0;
          case (addr[2:0])
            3'd0: alpha <= uio_in[2:0];                    // Diffusion coeff
            3'd1: boundary_temp <= uio_in[3:0];            // Boundary temp
            3'd2: boundary_type <= uio_in[0];              // Boundary type
            3'd3: heat_source_addr <= uio_in[5:0];         // Heat source location
            3'd4: heat_source_temp <= uio_in[3:0];         // Heat source temp
            3'd5: heat_source_enable <= uio_in[0];         // Enable heat source
            3'd6: begin
              iteration_count <= 0;                         // Reset iteration count
              max_temp <= 0;
            end
            3'd7: begin
              // Initialize with pattern
              for (i = 0; i < 64; i = i + 1) begin
                temp[i] <= (i == 27 || i == 28 || i == 35 || i == 36) ? 4'd15 : 4'd0;
              end
            end
          endcase
          status_out <= {2'b11, 6'b0};
        end
        
      endcase
      
    end
  end
  
  wire _unused = &{ena, addr[5:3]};
  
endmodule