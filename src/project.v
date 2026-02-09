/*
 * Copyright (c) 2024 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none
module tt_um_ahmadbelb_TUMVGA(
  input  wire [7:0] ui_in,    // Dedicated inputs
  output wire [7:0] uo_out,   // Dedicated outputs
  input  wire [7:0] uio_in,   // IOs: Input path
  output wire [7:0] uio_out,  // IOs: Output path
  output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
  input  wire       ena,      // always 1 when the design is powered, so you can ignore it
  input  wire       clk,      // clock
  input  wire       rst_n     // reset_n - low to reset
);
  // VGA signals
  wire hsync;
  wire vsync;
  wire [1:0] R;
  wire [1:0] G;
  wire [1:0] B;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;
  
  wire sound;
  
  // TinyVGA PMOD
  assign uo_out = {hsync, B[1], G[1], R[1], vsync, B[0], G[0], R[0]};
  
  // Audio output
  assign uio_out = {sound, 7'b0};
  assign uio_oe  = 8'hff;
  
  // Suppress unused signals warning
  wire _unused_ok = &{ena, uio_in};
  
  reg [9:0] counter;
  reg [11:0] frame_counter;
  
  // Audio wave generators
  reg [7:0] note_counter;
  reg note;
  reg [8:0] bass_counter;
  reg bass;
  
  hvsync_generator hvsync_gen(
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(video_active),
    .hpos(pix_x),
    .vpos(pix_y)
  );
  
  // ========== SPACE VISUALS ==========
  
  // STARS - brighter and more visible
  wire [9:0] star_seed = (pix_x * 13) ^ (pix_y * 17);
  wire is_star = (star_seed[7:0] < 8'd15);  // More stars!
  wire star_twinkle = (star_seed[9:8] == frame_counter[1:0]);
  
  // ROTATING NEBULA - colorful plasma
  wire [9:0] moving_x = pix_x + counter;
  wire [9:0] moving_y = pix_y - counter;
  wire [7:0] nebula_pattern = moving_x[7:0] ^ moving_y[7:0];
  
  // SPIRAL GALAXY from center
  wire [9:0] dx = (pix_x > 320) ? (pix_x - 320) : (320 - pix_x);
  wire [9:0] dy = (pix_y > 240) ? (pix_y - 240) : (240 - pix_y);
  wire [9:0] distance = dx + dy;
  wire [7:0] spiral = (distance[7:0] >> 2) ^ (pix_x[7:0] ^ pix_y[7:0]) + counter[7:0];
  
  // WORMHOLE center
  wire wormhole_core = (distance < 1000);
  
  // Combine effects - MUCH BRIGHTER
  wire [7:0] space_r = {is_star & star_twinkle, nebula_pattern[9:1]} + {7'b0, spiral[6]};
  wire [7:0] space_g = {is_star & star_twinkle, nebula_pattern[3:2]} + {6'b0, spiral[5:4]} + {7'b0, wormhole_core};
  wire [7:0] space_b = {is_star & star_twinkle, is_star & star_twinkle, nebula_pattern[5:0]} + {5'b0, spiral[7:5]};
  
  assign R = video_active ? {space_r[7], space_r[5]} : 2'b00;
  assign G = video_active ? {space_g[7], space_g[5]} : 2'b00;
  assign B = video_active ? {space_b[7], space_b[6]} : 2'b00;
  
  // ========== ORGAN SOUND ==========
  
  // Musical note frequencies (Interstellar style)
  wire [2:0] note_select = frame_counter[9:7];
  wire [7:0] note_freq = (note_select == 3'd0) ? 8'd120 :  // C
                         (note_select == 3'd1) ? 8'd107 :  // G  
                         (note_select == 3'd2) ? 8'd95  :  // E
                         (note_select == 3'd3) ? 8'd113 :  // F
                         (note_select == 3'd4) ? 8'd95  :  // E
                         (note_select == 3'd5) ? 8'd107 :  // G
                         (note_select == 3'd6) ? 8'd120 :  // C
                                                 8'd120;   // C
  
  wire [8:0] bass_freq = {1'b0, note_freq} + 9'd60;
  
  // Envelope for crescendo
  wire [4:0] envelope = 5'd0 - frame_counter[4:0];
  
  // Mix audio with spatial envelope
  wire note_on = note & (pix_x >= 2586) & (pix_x < 99996 + {envelope, 3'b0});
  wire bass_on = bass & (pix_x < {envelope, 3'b0});
  
  assign sound = note_on | bass_on;
  
  // ========== UPDATE LOGIC ==========
  always @(posedge clk) begin
    if (~rst_n) begin
      counter <= 0;
      frame_counter <= 0;
      note_counter <= 0;
      bass_counter <= 0;
      note <= 0;
      bass <= 0;
    end else begin
      
      // Update counters at start of frame
      if (pix_x == 0 && pix_y == 0) begin
        frame_counter <= frame_counter + 1;
        counter <= counter + 2;
      end
      
      // Generate audio waves at start of each line
      if (pix_x == 0) begin
        
        if (note_counter >= note_freq) begin
          note_counter <= 0;
          note <= ~note;
        end else begin
          note_counter <= note_counter + 1;
        end
        
        if (bass_counter >= bass_freq) begin
          bass_counter <= 0;
          bass <= ~bass;
        end else begin
          bass_counter <= bass_counter + 1;
        end
        
      end
    end
  end
  
endmodule