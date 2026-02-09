
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
  //   01: Write initial condition
  //   10: Read result
  //   11: Configure parameters
  // ui_in[5:0] - Address/Data depending on mode
  
  wire [1:0] mode = ui_in[7:6];
  wire [5:0] addr_data = ui_in[5:0];
  
  // Bidirectional I/O for data transfer
  assign uio_oe = (mode == 2'b10) ? 8'hFF : 8'h00;  // Output when reading
  
  // ========== SOLVER PARAMETERS ==========
  parameter GRID_SIZE = 32;  // 32x32 grid = 1024 cells (fits in FPGA)
  parameter ADDR_BITS = 10;  // 2^10 = 1024 addresses
  
  // Simulation control
  reg [9:0] sim_step_counter;
  reg [9:0] current_cell;
  reg solver_running;
  
  // Temperature storage - dual port for read/write
  reg [7:0] temp_current [0:1023];
  reg [7:0] temp_next [0:1023];
  
  // Configuration registers
  reg [7:0] diffusion_coeff;  // α parameter (0-255 scale)
  reg [7:0] boundary_temp;     // Boundary temperature
  reg [1:0] boundary_type;     // 00: Dirichlet, 01: Neumann, 10: Periodic
  
  // Data I/O registers
  reg [9:0] io_address;
  reg [7:0] io_data;
  reg io_write_enable;
  
  // ========== VGA OUTPUT (for monitoring) ==========
  wire hsync, vsync, video_active;
  wire [9:0] pix_x, pix_y;
  
  hvsync_generator hvsync_gen(
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(video_active),
    .hpos(pix_x),
    .vpos(pix_y)
  );
  
  // Map pixels to grid (20x20 pixels per cell for 32x32 grid)
  wire [4:0] grid_x = pix_x[9:5];  // Divide by 32
  wire [4:0] grid_y = pix_y[9:5];
  wire [9:0] display_addr = {grid_y, grid_x};
  wire [7:0] display_temp = temp_current[display_addr];
  
  // Heat map visualization
  wire [1:0] R_vis = video_active ? display_temp[7:6] : 2'b00;
  wire [1:0] G_vis = video_active ? (display_temp[6:5] ^ 2'b11) : 2'b00;
  wire [1:0] B_vis = video_active ? ~display_temp[7:6] : 2'b00;
  
  // VGA output
  assign uo_out = {hsync, B_vis[1], G_vis[1], R_vis[1], 
                   vsync, B_vis[0], G_vis[0], R_vis[0]};
  
  // Data output on bidirectional pins
  assign uio_out = (mode == 2'b10) ? temp_current[io_address] : 8'h00;
  
  // ========== 5-POINT STENCIL COMPUTATION ==========
  
  // Current cell coordinates
  wire [4:0] cx = current_cell[4:0];   // x coordinate (0-31)
  wire [4:0] cy = current_cell[9:5];   // y coordinate (0-31)
  
  // Neighbor indices with boundary handling
  wire [4:0] left_x  = (cx == 0) ? (boundary_type[1] ? 5'd31 : cx) : (cx - 1);
  wire [4:0] right_x = (cx == 31) ? (boundary_type[1] ? 5'd0 : cx) : (cx + 1);
  wire [4:0] up_y    = (cy == 0) ? (boundary_type[1] ? 5'd31 : cy) : (cy - 1);
  wire [4:0] down_y  = (cy == 31) ? (boundary_type[1] ? 5'd0 : cy) : (cy + 1);
  
  // Neighbor addresses
  wire [9:0] addr_center = current_cell;
  wire [9:0] addr_left   = {cy, left_x};
  wire [9:0] addr_right  = {cy, right_x};
  wire [9:0] addr_up     = {up_y, cx};
  wire [9:0] addr_down   = {down_y, cx};
  
  // Read neighbors
  wire [7:0] T_c = temp_current[addr_center];
  wire [7:0] T_l = temp_current[addr_left];
  wire [7:0] T_r = temp_current[addr_right];
  wire [7:0] T_u = temp_current[addr_up];
  wire [7:0] T_d = temp_current[addr_down];
  
  // Boundary condition override
  wire at_boundary = (cx == 0) || (cx == 31) || (cy == 0) || (cy == 31);
  wire is_dirichlet = (boundary_type == 2'b00) && at_boundary;
  
  // Compute Laplacian: ∇²T = T_l + T_r + T_u + T_d - 4*T_c
  wire [9:0] sum_neighbors = {2'b0, T_l} + {2'b0, T_r} + {2'b0, T_u} + {2'b0, T_d};
  wire [9:0] four_T_c = {T_c, 2'b0};
  
  wire signed [10:0] laplacian = $signed({1'b0, sum_neighbors}) - $signed({1'b0, four_T_c});
  
  // Apply diffusion: T_new = T_c + α * ∇²T / 4
  // diffusion_coeff is scaled 0-255 representing 0.0 to 1.0
  wire signed [18:0] delta = ($signed(laplacian) * $signed({1'b0, diffusion_coeff})) >>> 10;
  wire signed [9:0] T_new_signed = $signed({2'b0, T_c}) + delta[9:0];
  
  // Clamp to [0, 255]
  wire [7:0] T_new = T_new_signed[9] ? 8'd0 :           // Negative -> 0
                     T_new_signed[8] ? 8'd255 :         // Overflow -> 255
                     T_new_signed[7:0];
  
  // ========== MAIN CONTROL LOGIC ==========
  
  integer i;
  
  always @(posedge clk) begin
    if (~rst_n) begin
      // Reset state
      solver_running <= 0;
      current_cell <= 0;
      sim_step_counter <= 0;
      io_address <= 0;
      io_data <= 0;
      io_write_enable <= 0;
      diffusion_coeff <= 8'd64;  // Default α ≈ 0.25
      boundary_temp <= 8'd0;
      boundary_type <= 2'b00;    // Dirichlet by default
      
      // Initialize grid to zero
      for (i = 0; i < 1024; i = i + 1) begin
        temp_current[i] <= 8'd0;
        temp_next[i] <= 8'd0;
      end
      
    end else begin
      
      // ========== MODE HANDLING ==========
      case (mode)
        
        // MODE 00: Run simulation
        2'b00: begin
          solver_running <= 1;
          
          // Compute one cell per clock cycle
          if (current_cell < 1024) begin
            // Apply boundary condition or compute stencil
            temp_next[addr_center] <= is_dirichlet ? boundary_temp : T_new;
            current_cell <= current_cell + 1;
          end else begin
            // Completed one full sweep - swap buffers
            current_cell <= 0;
            sim_step_counter <= sim_step_counter + 1;
            
            // Copy temp_next to temp_current
            for (i = 0; i < 1024; i = i + 1) begin
              temp_current[i] <= temp_next[i];
            end
          end
        end
        
        // MODE 01: Write initial condition
        2'b01: begin
          solver_running <= 0;
          // Address comes from previous cycle's addr_data
          // Data comes from uio_in
          if (io_write_enable) begin
            temp_current[io_address] <= uio_in;
          end
          io_address <= {4'b0, addr_data};  // Set address for next write
          io_write_enable <= 1;
        end
        
        // MODE 10: Read result
        2'b10: begin
          solver_running <= 0;
          io_address <= {4'b0, addr_data};
          io_write_enable <= 0;
          // Output appears on uio_out automatically
        end
        
        // MODE 11: Configure parameters
        2'b11: begin
          solver_running <= 0;
          io_write_enable <= 0;
          case (addr_data[5:4])
            2'b00: diffusion_coeff <= uio_in;
            2'b01: boundary_temp <= uio_in;
            2'b10: boundary_type <= uio_in[1:0];
            default: ;
          endcase
        end
        
      endcase
      
    end
  end
  
  // Suppress warnings
  wire _unused = &{ena, uio_in[7:2]};
  
endmodule