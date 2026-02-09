/*
 * 5-Point Stencil Heat Equation Solver for Tiny Tapeout
 * Minimal version that fits on silicon
 * 8x8 grid = 64 cells, 4-bit temperatures
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
  // ui_in[7:6] - Mode: 00=Run, 01=Write, 10=Read, 11=Config
  // ui_in[5:0] - Address/Control
  
  wire [1:0] mode = ui_in[7:6];
  wire [5:0] addr = ui_in[5:0];
  
  assign uio_oe = (mode == 2'b10) ? 8'hFF : 8'h00;
  
  // ========== MINIMAL GRID (8x8, 4-bit temps) ==========
  parameter GRID_SIZE = 64;  // 8x8 grid
  
  reg [5:0] cell_idx;
  reg [3:0] temp [0:63];  // 64 cells × 4 bits = 256 flip-flops
  reg [1:0] alpha;        // Diffusion: 00=0.125, 01=0.25, 10=0.5, 11=0.75
  reg [3:0] boundary;     // Boundary temperature
  reg [11:0] iterations;
  
  // ========== COMPUTATION ==========
  
  wire [2:0] cx = cell_idx[2:0];  // x: 0-7
  wire [2:0] cy = cell_idx[5:3];  // y: 0-7
  
  wire at_edge = (cx == 0) | (cx == 7) | (cy == 0) | (cy == 7);
  
  wire [2:0] left_x  = (cx == 0) ? cx : (cx - 1);
  wire [2:0] right_x = (cx == 7) ? cx : (cx + 1);
  wire [2:0] up_y    = (cy == 0) ? cy : (cy - 1);
  wire [2:0] down_y  = (cy == 7) ? cy : (cy + 1);
  
  wire [5:0] addr_c = cell_idx;
  wire [5:0] addr_l = {cy, left_x};
  wire [5:0] addr_r = {cy, right_x};
  wire [5:0] addr_u = {up_y, cx};
  wire [5:0] addr_d = {down_y, cx};
  
  wire [3:0] T_c = temp[addr_c];
  wire [3:0] T_l = temp[addr_l];
  wire [3:0] T_r = temp[addr_r];
  wire [3:0] T_u = temp[addr_u];
  wire [3:0] T_d = temp[addr_d];
  
  // Simple averaging: (T_l + T_r + T_u + T_d) / 4
  wire [5:0] sum = {2'b0, T_l} + {2'b0, T_r} + {2'b0, T_u} + {2'b0, T_d};
  wire [3:0] avg = sum[5:2];  // Divide by 4
  
  // Mix with center based on alpha
  wire [3:0] T_new = (alpha == 2'b00) ? ((T_c * 7 + avg) >> 3) :      // 0.125
                     (alpha == 2'b01) ? ((T_c * 3 + avg) >> 2) :      // 0.25
                     (alpha == 2'b10) ? ((T_c + avg) >> 1) :          // 0.5
                                        ((T_c + avg * 3) >> 2);       // 0.75
  
  wire [3:0] T_final = at_edge ? boundary : T_new;
  
  // ========== OUTPUT ==========
  reg [7:0] out_data;
  
  assign uo_out = out_data;
  assign uio_out = {4'b0, temp[addr]};
  
  // ========== CONTROL ==========
  
  integer i;
  
  always @(posedge clk) begin
    if (~rst_n) begin
      cell_idx <= 0;
      iterations <= 0;
      alpha <= 2'b01;      // Default α = 0.25
      boundary <= 4'd0;    // Cold boundary
      out_data <= 0;
      
      for (i = 0; i < 64; i = i + 1) begin
        temp[i] <= 4'd0;
      end
      
    end else begin
      
      case (mode)
        
        // Run simulation
        2'b00: begin
          temp[addr_c] <= T_final;
          
          if (cell_idx < 63) begin
            cell_idx <= cell_idx + 1;
          end else begin
            cell_idx <= 0;
            iterations <= iterations + 1;
          end
          
          out_data <= {2'b00, iterations[11:6]};
        end
        
        // Write
        2'b01: begin
          temp[addr] <= uio_in[3:0];
          out_data <= {2'b01, addr};
        end
        
        // Read
        2'b10: begin
          out_data <= {2'b10, 2'b0, temp[addr]};
        end
        
        // Config
        2'b11: begin
          if (addr[0] == 0) begin
            alpha <= uio_in[1:0];
          end else begin
            boundary <= uio_in[3:0];
          end
          out_data <= {2'b11, 6'b0};
        end
        
      endcase
      
    end
  end
  
  wire _unused = &{ena, uio_in[7:4], addr[5:1]};
  
endmodule