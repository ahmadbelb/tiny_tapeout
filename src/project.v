/*
 * 5-Point Stencil Heat Equation Solver for Tiny Tapeout
 * Optimized: 5x5 grid, 4-bit temps, simplified logic
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

  // Control
  wire [1:0] mode = ui_in[7:6];
  wire [4:0] addr = ui_in[4:0];  // 0-24 for 5x5 grid
  
  assign uio_oe = (mode == 2'b10) ? 8'hFF : 8'h00;
  
  // 5x5 grid = 25 cells × 4 bits = 100 flip-flops
  reg [3:0] temp [0:24];
  
  reg [4:0] cell_idx;
  reg [2:0] alpha;
  reg [3:0] boundary_temp;
  
  // Simple coordinate calculation: cell_idx = y*5 + x
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
  
  // Neighbor addresses (with clamping)
  wire [4:0] addr_c = cell_idx;
  wire [4:0] addr_l = (cx == 0) ? cell_idx : (cell_idx - 1);
  wire [4:0] addr_r = (cx == 4) ? cell_idx : (cell_idx + 1);
  wire [4:0] addr_u = (cy == 0) ? cell_idx : (cell_idx - 5);
  wire [4:0] addr_d = (cy == 4) ? cell_idx : (cell_idx + 5);
  
  // Read temperatures
  wire [3:0] T_c = temp[addr_c];
  wire [3:0] T_l = temp[addr_l];
  wire [3:0] T_r = temp[addr_r];
  wire [3:0] T_u = temp[addr_u];
  wire [3:0] T_d = temp[addr_d];
  
  // 5-point stencil computation
  wire [5:0] sum = {2'b0, T_l} + {2'b0, T_r} + {2'b0, T_u} + {2'b0, T_d};
  wire [3:0] avg = sum[5:2];
  
  // Simple diffusion: T_new = (T_c + avg) / 2 when alpha=4
  // Scale by alpha/8
  wire [4:0] diff = {1'b0, avg} - {1'b0, T_c};
  wire [7:0] scaled_diff = diff * alpha;
  wire [3:0] delta = scaled_diff[6:3];  // Divide by 8
  
  wire [4:0] T_sum = {1'b0, T_c} + {1'b0, delta};
  wire [3:0] T_new = T_sum[4] ? 4'd15 : T_sum[3:0];
  
  wire [3:0] T_final = at_edge ? boundary_temp : T_new;
  
  // Outputs
  assign uo_out = {mode, 2'b0, temp[addr]};
  assign uio_out = {4'b0, temp[addr]};
  
  // Control logic
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
        2'b00: begin  // Run
          temp[addr_c] <= T_final;
          cell_idx <= (cell_idx == 24) ? 0 : (cell_idx + 1);
        end
        
        2'b01: begin  // Write
          if (addr < 25) begin
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
  
  wire _unused = &{ena, ui_in[6:5], uio_in[7:4], sum[1:0]};
  
endmodule