import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

@cocotb.test()
async def test_basic_operation(dut):
    """Test with detailed logging"""
    
    clock = Clock(dut.clk, 40, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)
    
    dut._log.info("=== RESET COMPLETE ===")
    
    # Configure alpha=4
    dut.ui_in.value = (0b11 << 6) | 0
    dut.uio_in.value = 4
    await ClockCycles(dut.clk, 5)
    
    dut._log.info("=== CONFIGURED ALPHA=4 ===")
    
    # Write cell 12 = 15
    dut._log.info(f"Writing cell 12 with value 15...")
    dut.ui_in.value = (0b01 << 6) | 12  # Mode=01, addr=12
    dut.uio_in.value = 15
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await ClockCycles(dut.clk, 3)
    
    # Immediately read back
    dut._log.info(f"Reading back cell 12...")
    dut.ui_in.value = (0b10 << 6) | 12  # Mode=10, addr=12
    await ClockCycles(dut.clk, 3)
    
    try:
        readback = int(dut.uio_out.value) & 0x0F
        dut._log.info(f"Readback immediately after write: {readback}")
    except:
        dut._log.error(f"Could not read uio_out, value: {dut.uio_out.value}")
        readback = 0
    
    # Should read back 15
    assert readback == 15, f"Write/read failed: expected 15, got {readback}"
    
    dut._log.info("✅ Write/Read works!")
    
    # Now write cell 13 too
    dut.ui_in.value = (0b01 << 6) | 13
    dut.uio_in.value = 15
    await ClockCycles(dut.clk, 5)
    
    # Run 5 iterations (short test)
    dut._log.info("Running 5 iterations...")
    dut.ui_in.value = 0b00 << 6
    await ClockCycles(dut.clk, 25 * 5)  # 5 full sweeps
    
    # Read cell 12 again
    dut.ui_in.value = (0b10 << 6) | 12
    await ClockCycles(dut.clk, 3)
    
    try:
        final_temp = int(dut.uio_out.value) & 0x0F
        dut._log.info(f"Cell 12 after 5 iterations: {final_temp}")
    except:
        dut._log.error(f"Could not read uio_out")
        final_temp = 0
    
    # Should have diffused
    assert final_temp > 0, f"Should still have heat: got {final_temp}"
    assert final_temp < 15, f"Should have cooled: got {final_temp}"
    
    # Read a neighbor
    dut.ui_in.value = (0b10 << 6) | 7  # Cell above
    await ClockCycles(dut.clk, 3)
    neighbor = int(dut.uio_out.value) & 0x0F
    dut._log.info(f"Neighbor cell 7: {neighbor}")
    
    # Read edge
    dut.ui_in.value = (0b10 << 6) | 0
    await ClockCycles(dut.clk, 3)
    edge = int(dut.uio_out.value) & 0x0F
    dut._log.info(f"Edge cell 0: {edge}")
    
    assert edge == 0, f"Edge should be 0: got {edge}"
    
    dut._log.info("✅✅✅ ALL TESTS PASSED! ✅✅✅")

@cocotb.test()  
async def test_simple_write_read(dut):
    """Minimal write/read test"""
    
    clock = Clock(dut.clk, 40, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.ena.value = 1
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)
    
    # Test each cell
    for cell in [0, 6, 12, 18, 24]:
        value = (cell % 15) + 1
        
        # Write
        dut.ui_in.value = (0b01 << 6) | cell
        dut.uio_in.value = value
        await ClockCycles(dut.clk, 5)
        
        # Read
        dut.ui_in.value = (0b10 << 6) | cell  
        await ClockCycles(dut.clk, 5)
        
        readback = int(dut.uio_out.value) & 0x0F
        dut._log.info(f"Cell {cell}: wrote {value}, read {readback}")
        
        assert readback == value, f"Cell {cell} mismatch!"
    
    dut._log.info("✅ Simple write/read PASSED!")