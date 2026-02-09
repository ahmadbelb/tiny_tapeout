/*
 * 5-Point Stencil Heat Equation Solver for Tiny Tapeout
 * Ultra-minimal: 4x4 grid, 3-bit temperatures
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

  // Control: ui_in[7:6]=mode, ui_in[3:0]=address
  wire [1:0] mode = ui_in[7:6];
  wire [3:0] addr = ui_in[3:0];
  
  assign uio_oe = (mode == 2'b10) ? 8'hFF : 8'h00;
  
  // 4x4 grid, 3-bit temperatures (0-7) = 48 flip-flops total
  reg [2:0] temp [0:15];
  reg [3:0] cell_idx;
  reg [1:0] alpha;
  reg [2:0] boundary;
  
  // Current cell coords
  wire [1:0] cx = cell_idx[1:0];
  wire [1:0] cy = cell_idx[3:2];
  
  wire at_edge = (cx == 0) | (cx == 3) | (cy == 0) | (cy == 3);
  
  // Neighbors (clamped at boundaries)
  wire [1:0] left_x  = (cx == 0) ? cx : (cx - 1);
  wire [1:0] right_x = (cx == 3) ? cx : (cx + 1);
  wire [1:0] up_y    = (cy == 0) ? cy : (cy - 1);
  wire [1:0] down_y  = (cy == 3) ? cy : (cy + 1);
  
  wire [3:0] addr_c = cell_idx;
  wire [3:0] addr_l = {cy, left_x};
  wire [3:0] addr_r = {cy, right_x};
  wire [3:0] addr_u = {up_y, cx};
  wire [3:0] addr_d = {down_y, cx};
  
  wire [2:0] T_c = temp[addr_c];
  wire [2:0] T_l = temp[addr_l];
  wire [2:0] T_r = temp[addr_r];
  wire [2:0] T_u = temp[addr_u];
  wire [2:0] T_d = temp[addr_d];
  
  // Average of 4 neighbors
  wire [4:0] sum = {2'b0, T_l} + {2'b0, T_r} + {2'b0, T_u} + {2'b0, T_d};
  wire [2:0] avg = sum[4:2];  // Divide by 4
  
  // Weighted average based on alpha
  wire [2:0] T_new = (alpha == 2'b00) ? T_c :                    // α=0 (no diffusion)
                     (alpha == 2'b01) ? ((T_c + avg) >> 1) :     // α=0.5
                     (alpha == 2'b10) ? (({1'b0, T_c} + {avg, 1'b0}) >> 2) : // α=0.75
                                        avg;                      // α=1.0 (full diffusion)
  
  wire [2:0] T_final = at_edge ? boundary : T_new;
  
  // Output
  assign uo_out = {mode, 3'b0, temp[addr][2:0]};
  assign uio_out = {5'b0, temp[addr]};
  
  // Control logic
  integer i;
  
  always @(posedge clk) begin
    if (~rst_n) begin
      cell_idx <= 0;
      alpha <= 2'b01;
      boundary <= 3'd0;
      
      for (i = 0; i < 16; i = i + 1) begin
        temp[i] <= 3'd0;
      end
      
    end else begin
      
      case (mode)
        2'b00: begin  // Run
          temp[addr_c] <= T_final;
          cell_idx <= (cell_idx == 15) ? 0 : (cell_idx + 1);
        end
        
        2'b01: begin  // Write
          temp[addr] <= uio_in[2:0];
        end
        
        2'b10: begin  // Read (output on uio_out)
        end
        
        2'b11: begin  // Config
          if (ui_in[4]) begin
            boundary <= uio_in[2:0];
          end else begin
            alpha <= uio_in[1:0];
          end
        end
      endcase
      
    end
  end
  
  wire _unused = &{ena, ui_in[6:4], uio_in[7:3]};
  
endmodule