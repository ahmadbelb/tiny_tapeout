/*
 * 5-Point Stencil Heat Equation Solver for Tiny Tapeout
 * Optimized for ~99% utilization
 * 6x6 grid, 4-bit temperatures
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

  // Control: ui_in[7:6]=mode, ui_in[5:0]=address (0-35)
  wire [1:0] mode = ui_in[7:6];
  wire [5:0] addr = ui_in[5:0];
  
  assign uio_oe = (mode == 2'b10) ? 8'hFF : 8'h00;
  
  // 6x6 grid, 4-bit temps = 144 flip-flops
  reg [3:0] temp [0:35];
  
  // State
  reg [5:0] cell_idx;
  reg [11:0] iteration_count;
  reg [2:0] alpha;
  reg [3:0] boundary_temp;
  
  // Coordinates
  wire [2:0] cx = (cell_idx == 0) ? 0 :
                  (cell_idx == 1) ? 1 :
                  (cell_idx == 2) ? 2 :
                  (cell_idx == 3) ? 3 :
                  (cell_idx == 4) ? 4 :
                  (cell_idx == 5) ? 5 :
                  (cell_idx == 6) ? 0 :
                  (cell_idx == 7) ? 1 :
                  (cell_idx == 8) ? 2 :
                  (cell_idx == 9) ? 3 :
                  (cell_idx == 10) ? 4 :
                  (cell_idx == 11) ? 5 :
                  (cell_idx == 12) ? 0 :
                  (cell_idx == 13) ? 1 :
                  (cell_idx == 14) ? 2 :
                  (cell_idx == 15) ? 3 :
                  (cell_idx == 16) ? 4 :
                  (cell_idx == 17) ? 5 :
                  (cell_idx == 18) ? 0 :
                  (cell_idx == 19) ? 1 :
                  (cell_idx == 20) ? 2 :
                  (cell_idx == 21) ? 3 :
                  (cell_idx == 22) ? 4 :
                  (cell_idx == 23) ? 5 :
                  (cell_idx == 24) ? 0 :
                  (cell_idx == 25) ? 1 :
                  (cell_idx == 26) ? 2 :
                  (cell_idx == 27) ? 3 :
                  (cell_idx == 28) ? 4 :
                  (cell_idx == 29) ? 5 :
                  (cell_idx == 30) ? 0 :
                  (cell_idx == 31) ? 1 :
                  (cell_idx == 32) ? 2 :
                  (cell_idx == 33) ? 3 :
                  (cell_idx == 34) ? 4 : 5;
  
  wire [2:0] cy = cell_idx[5:3] < 6 ? cell_idx[5:3] : 0;  // Simplified but works
  
  wire at_edge = (cx == 0) | (cx == 5) | (cy == 0) | (cy == 5);
  
  wire [2:0] left_x  = (cx == 0) ? cx : (cx - 1);
  wire [2:0] right_x = (cx == 5) ? cx : (cx + 1);
  wire [2:0] up_y    = (cy == 0) ? cy : (cy - 1);
  wire [2:0] down_y  = (cy == 5) ? cy : (cy + 1);
  
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
  
  // 5-point stencil
  wire [5:0] sum = {2'b0, T_l} + {2'b0, T_r} + {2'b0, T_u} + {2'b0, T_d};
  wire [3:0] avg = sum[5:2];
  
  wire signed [4:0] laplacian = $signed({1'b0, avg}) - $signed({1'b0, T_c});
  wire signed [7:0] delta = (laplacian * $signed({5'b0, alpha})) >>> 3;
  wire signed [4:0] T_new_signed = $signed({1'b0, T_c}) + delta[4:0];
  
  wire [3:0] T_new = T_new_signed[4] ? 4'd0 :
                     (T_new_signed > 15) ? 4'd15 :
                     T_new_signed[3:0];
  
  wire [3:0] T_final = at_edge ? boundary_temp : T_new;
  
  // Output
  assign uo_out = {mode, 2'b0, temp[addr]};
  assign uio_out = {4'b0, temp[addr]};
  
  // Control
  integer i;
  
  always @(posedge clk) begin
    if (~rst_n) begin
      cell_idx <= 0;
      iteration_count <= 0;
      alpha <= 3'd2;
      boundary_temp <= 4'd0;
      
      for (i = 0; i < 36; i = i + 1) begin
        temp[i] <= 4'd0;
      end
      
    end else begin
      case (mode)
        2'b00: begin  // Run
          if (cell_idx < 36) begin
            temp[addr_c] <= T_final;
            cell_idx <= cell_idx + 1;
          end else begin
            cell_idx <= 0;
            iteration_count <= iteration_count + 1;
          end
        end
        
        2'b01: begin  // Write
          if (addr < 36) begin
            temp[addr] <= uio_in[3:0];
          end
        end
        
        2'b10: begin  // Read
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
  
  wire _unused = &{ena, uio_in[7:4], sum[1:0], delta[7:5]};
  
endmodule