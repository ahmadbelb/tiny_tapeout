import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_basic_operation(dut):
    """Test basic solver operation without numpy"""
    
    # Start clock
    clock = Clock(dut.clk, 40, units="ns")  # 25 MHz
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    
    dut._log.info("✓ Reset complete")
    
    # Configure: alpha = 2
    dut.ui_in.value = (0b11 << 6) | 0  # Mode=11, config alpha
    dut.uio_in.value = 2
    await ClockCycles(dut.clk, 2)
    
    dut._log.info("✓ Configured alpha=2")
    
    # Write hot spot at center cells (14, 15, 20, 21 for 6x6 grid)
    hot_cells = [14, 15, 20, 21]
    for cell in hot_cells:
        dut.ui_in.value = (0b01 << 6) | cell  # Mode=01, write
        dut.uio_in.value = 15  # Max temperature
        await ClockCycles(dut.clk, 2)
    
    dut._log.info("✓ Hot spot written to center")
    
    # Run simulation for 10 iterations (36 cells × 10 = 360 cycles)
    dut.ui_in.value = 0b00 << 6  # Mode=00, run
    await ClockCycles(dut.clk, 36 * 10)
    
    dut._log.info("✓ Simulation ran for 10 iterations")
    
    # Read center cell temperature
    dut.ui_in.value = (0b10 << 6) | 14  # Mode=10, read cell 14
    await ClockCycles(dut.clk, 2)
    center_temp = int(dut.uio_out.value) & 0x0F
    
    dut._log.info(f"✓ Center temperature after diffusion: {center_temp}")
    
    # Basic validation checks
    assert center_temp < 15, "Center should have cooled down"
    assert center_temp > 0, "Center should still be warm"
    
    # Read edge cell (should be cold)
    dut.ui_in.value = (0b10 << 6) | 0  # Mode=10, read cell 0 (corner)
    await ClockCycles(dut.clk, 2)
    edge_temp = int(dut.uio_out.value) & 0x0F
    
    dut._log.info(f"✓ Edge temperature: {edge_temp}")
    assert edge_temp < 5, "Edge should be cool"
    
    dut._log.info("✅ All tests PASSED!")

@cocotb.test()
async def test_boundary_conditions(dut):
    """Test boundary temperature setting"""
    
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.ena.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    
    # Set boundary temperature to 5
    dut.ui_in.value = (0b11 << 6) | 1  # Mode=11, config boundary
    dut.uio_in.value = 5
    await ClockCycles(dut.clk, 2)
    
    dut._log.info("✓ Set boundary temp to 5")
    
    # Write hot spot in middle
    dut.ui_in.value = (0b01 << 6) | 14
    dut.uio_in.value = 15
    await ClockCycles(dut.clk, 2)
    
    # Run simulation
    dut.ui_in.value = 0b00 << 6
    await ClockCycles(dut.clk, 36 * 20)
    
    # Read edge cell
    dut.ui_in.value = (0b10 << 6) | 0
    await ClockCycles(dut.clk, 2)
    edge_temp = int(dut.uio_out.value) & 0x0F
    
    dut._log.info(f"✓ Edge temp with boundary=5: {edge_temp}")
    
    # Should be close to boundary temperature
    assert edge_temp >= 3 and edge_temp <= 7, f"Edge temp {edge_temp} not near boundary temp 5"
    
    dut._log.info("✅ Boundary conditions test PASSED!")

@cocotb.test()
async def test_diffusion_rate(dut):
    """Test different diffusion coefficients"""
    
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())
    
    for alpha in [1, 2, 4]:  # Test different alpha values
        # Reset
        dut.rst_n.value = 0
        await ClockCycles(dut.clk, 5)
        dut.rst_n.value = 1
        await ClockCycles(dut.clk, 5)
        
        # Configure alpha
        dut.ui_in.value = (0b11 << 6) | 0
        dut.uio_in.value = alpha
        await ClockCycles(dut.clk, 2)
        
        # Write hot spot
        dut.ui_in.value = (0b01 << 6) | 14
        dut.uio_in.value = 15
        await ClockCycles(dut.clk, 2)
        
        # Run
        dut.ui_in.value = 0b00 << 6
        await ClockCycles(dut.clk, 36 * 10)
        
        # Read result
        dut.ui_in.value = (0b10 << 6) | 14
        await ClockCycles(dut.clk, 2)
        temp = int(dut.uio_out.value) & 0x0F
        
        dut._log.info(f"✓ Alpha={alpha}, center temp after 10 iter: {temp}")
        
        # Higher alpha should diffuse faster (lower temp)
        assert temp < 15, f"Should have diffused with alpha={alpha}"
    
    dut._log.info("✅ Diffusion rate test PASSED!")

@cocotb.test()
async def test_read_write(dut):
    """Test basic read/write functionality"""
    
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.ena.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    
    # Write and read back several cells
    test_data = [(0, 7), (5, 12), (14, 15), (35, 3)]
    
    for addr, value in test_data:
        # Write
        dut.ui_in.value = (0b01 << 6) | addr
        dut.uio_in.value = value
        await ClockCycles(dut.clk, 2)
        
        # Read back
        dut.ui_in.value = (0b10 << 6) | addr
        await ClockCycles(dut.clk, 2)
        readback = int(dut.uio_out.value) & 0x0F
        
        dut._log.info(f"✓ Cell {addr}: wrote {value}, read {readback}")
        assert readback == value, f"Read/write mismatch at cell {addr}"
    
    dut._log.info("✅ Read/write test PASSED!")