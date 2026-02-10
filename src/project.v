/*
 * 5-Point Stencil Heat Equation Solver for Tiny Tapeout
 * Fixed: Proper signed arithmetic for heat diffusion
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

  wire [1:0] mode = ui_in[7:6];
  wire [4:0] addr = ui_in[4:0];
  
  assign uio_oe = (mode == 2'b10) ? 8'hFF : 8'h00;
  
  // 5x5 grid = 100 FFs
  reg [3:0] temp [0:24];
  reg [4:0] cell_idx;
  reg [2:0] alpha;
  reg [3:0] boundary_temp;
  
  // Coordinates
  wire [2:0] cx = (cell_idx < 5)  ? cell_idx[2:0] :
                  (cell_idx < 10) ? (cell_idx - 5) :
                  (cell_idx < 15) ? (cell_idx - 10) :
                  (cell_idx < 20) ? (cell_idx - 15) :
                                    (cell_idx - 20);
  
  wire [2:0] cy = (cell_idx < 5)  ? 3'd0 :
                  (cell_idx < 10) ? 3'd1 :
                  (cell_idx < 15) ? 3'd2 :
                  (cell_idx < 20) ? 3'd3 : 3'd4;
  
  wire at_edge = (cx == 0) | (cx == 4) | (cy == 0) | (cy == 4);
  
  // Neighbor addresses
  wire [4:0] addr_c = cell_idx;
  wire [4:0] addr_l = (cx == 0) ? cell_idx : (cell_idx - 1);
  wire [4:0] addr_r = (cx == 4) ? cell_idx : (cell_idx + 1);
  wire [4:0] addr_u = (cy == 0) ? cell_idx : (cell_idx - 5);
  wire [4:0] addr_d = (cy == 4) ? cell_idx : (cell_idx + 5);
  
  wire [3:0] T_c = temp[addr_c];
  wire [3:0] T_l = temp[addr_l];
  wire [3:0] T_r = temp[addr_r];
  wire [3:0] T_u = temp[addr_u];
  wire [3:0] T_d = temp[addr_d];
  
  // ========== PROPER 5-POINT STENCIL ==========
  // Average of 4 neighbors
  wire [5:0] sum_neighbors = {2'b0, T_l} + {2'b0, T_r} + {2'b0, T_u} + {2'b0, T_d};
  wire [3:0] avg_neighbors = sum_neighbors[5:2];  // Divide by 4
  
  // Laplacian: diff = avg - T_c (SIGNED)
  wire signed [4:0] laplacian = $signed({1'b0, avg_neighbors}) - $signed({1'b0, T_c});
  
  // Scale by alpha and divide by 8: delta = alpha * laplacian / 8
  wire signed [7:0] delta_scaled = laplacian * $signed({5'b0, alpha});
  wire signed [4:0] delta = delta_scaled[7:3];  // Arithmetic right shift by 3 (divide by 8)
  
  // Update: T_new = T_c + delta
  wire signed [5:0] T_new_signed = $signed({2'b0, T_c}) + delta;
  
  // Clamp to [0, 15]
  wire [3:0] T_clamped = (T_new_signed < 0) ? 4'd0 :
                         (T_new_signed > 15) ? 4'd15 :
                         T_new_signed[3:0];
  
  // Apply boundary condition
  wire [3:0] T_final = at_edge ? boundary_temp : T_clamped;
  
  // Outputs
  assign uo_out = {mode, 2'b0, temp[addr]};
  assign uio_out = {4'b0, temp[addr]};
  
  // Control
  integer i;
  
  always @(posedge clk) begin
    if (~rst_n) begin
      cell_idx <= 0;
      alpha <= 3'd2;
      boundary_temp <= 4'd0;
      
      for (i = 0; i < 25; i = i + 1) begin
        temp[i] <= 4'd0;
      end
      
    end else begin
      
      case (mode)
        2'b00: begin  // Run simulation
          temp[addr_c] <= T_final;
          cell_idx <= (cell_idx == 24) ? 0 : (cell_idx + 1);
        end
        
        2'b01: begin  // Write
          if (addr < 25) begin
            temp[addr] <= uio_in[3:0];
          end
        end
        
        2'b10: begin  // Read
          // Data output happens via assign
        end
        
        2'b11: begin  // Config
          if (addr[0] == 0) begin
            alpha <= uio_in[2:0];
          end else begin
            boundary_temp <= uio_in[3:0];
          end
        end
      endcase
      
    end
  end
  
  wire _unused = &{ena, ui_in[6:5], uio_in[7:4], sum_neighbors[1:0]};
  
endmodule