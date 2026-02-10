import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_basic_operation(dut):
    """Test basic solver operation"""
    
    clock = Clock(dut.clk, 40, unit="ns")
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
    
    # Configure alpha=4 (faster diffusion for testing)
    dut.ui_in.value = (0b11 << 6) | 0
    dut.uio_in.value = 4
    await ClockCycles(dut.clk, 2)
    
    # Write hot spot at center (cells 12, 13)
    for cell in [12, 13]:
        dut.ui_in.value = (0b01 << 6) | cell
        dut.uio_in.value = 15
        await ClockCycles(dut.clk, 2)
    
    dut._log.info("✓ Hot spot written")
    
    # Run 20 iterations
    dut.ui_in.value = 0b00 << 6
    await ClockCycles(dut.clk, 25 * 20)
    
    # Read center
    dut.ui_in.value = (0b10 << 6) | 12
    await ClockCycles(dut.clk, 2)
    center_temp = int(dut.uio_out.value) & 0x0F
    
    dut._log.info(f"✓ Center temp: {center_temp}")
    
    # Should have cooled significantly
    assert center_temp < 15, f"Should cool: got {center_temp}"
    assert center_temp > 2, f"Should still be warm: got {center_temp}"
    
    # Read neighbor (should be warmer than edge)
    dut.ui_in.value = (0b10 << 6) | 11
    await ClockCycles(dut.clk, 2)
    neighbor_temp = int(dut.uio_out.value) & 0x0F
    
    dut._log.info(f"✓ Neighbor temp: {neighbor_temp}")
    assert neighbor_temp > 0, "Neighbor should have some heat"
    
    # Read edge (should be cold)
    dut.ui_in.value = (0b10 << 6) | 0
    await ClockCycles(dut.clk, 2)
    edge_temp = int(dut.uio_out.value) & 0x0F
    
    dut._log.info(f"✓ Edge temp: {edge_temp}")
    assert edge_temp == 0, f"Edge should be 0: got {edge_temp}"
    
    dut._log.info("✅ TEST PASSED!")

@cocotb.test()
async def test_read_write(dut):
    """Test read/write"""
    
    clock = Clock(dut.clk, 40, unit="ns")
    cocotb.start_soon(clock.start())
    
    dut.rst_n.value = 0
    dut.ena.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    
    # Write and readback
    for addr in [0, 5, 12, 24]:
        value = (addr * 3) % 16
        
        # Write
        dut.ui_in.value = (0b01 << 6) | addr
        dut.uio_in.value = value
        await ClockCycles(dut.clk, 2)
        
        # Read
        dut.ui_in.value = (0b10 << 6) | addr
        await ClockCycles(dut.clk, 2)
        readback = int(dut.uio_out.value) & 0x0F
        
        assert readback == value, f"Addr {addr}: wrote {value}, read {readback}"
        dut._log.info(f"✓ Cell {addr}: {value}")
    
    dut._log.info("✅ Read/Write PASSED!")