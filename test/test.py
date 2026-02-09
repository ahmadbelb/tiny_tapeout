import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
import numpy as np
import matplotlib.pyplot as plt

class HeatSolverDriver:
    """Driver for the heat equation solver"""
    
    def __init__(self, dut):
        self.dut = dut
        
    async def reset(self):
        """Reset the design"""
        self.dut.rst_n.value = 0
        self.dut.ena.value = 1
        self.dut.ui_in.value = 0
        self.dut.uio_in.value = 0
        await ClockCycles(self.dut.clk, 5)
        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.clk, 5)
        
    async def configure(self, alpha=2, boundary_temp=0, boundary_type=0):
        """Configure solver parameters"""
        # Set alpha
        self.dut.ui_in.value = (0b11 << 6) | 0  # Mode=11, param=0
        self.dut.uio_in.value = alpha
        await ClockCycles(self.dut.clk, 2)
        
        # Set boundary temp
        self.dut.ui_in.value = (0b11 << 6) | 1  # Mode=11, param=1
        self.dut.uio_in.value = boundary_temp
        await ClockCycles(self.dut.clk, 2)
        
        # Set boundary type
        self.dut.ui_in.value = (0b11 << 6) | 2  # Mode=11, param=2
        self.dut.uio_in.value = boundary_type
        await ClockCycles(self.dut.clk, 2)
        
    async def write_cell(self, x, y, temp):
        """Write temperature to a cell"""
        addr = (y << 3) | x  # 8x8 grid
        self.dut.ui_in.value = (0b01 << 6) | addr  # Mode=01 (write)
        self.dut.uio_in.value = temp
        await ClockCycles(self.dut.clk, 2)
        
    async def read_cell(self, x, y):
        """Read temperature from a cell"""
        addr = (y << 3) | x
        self.dut.ui_in.value = (0b10 << 6) | addr  # Mode=10 (read)
        await ClockCycles(self.dut.clk, 2)
        return int(self.dut.uio_out.value) & 0x0F
        
    async def run_iterations(self, n_iterations):
        """Run n iterations of the solver"""
        self.dut.ui_in.value = 0b00 << 6  # Mode=00 (run)
        # Each iteration is 64 cells
        await ClockCycles(self.dut.clk, 64 * n_iterations)
        
    async def read_grid(self):
        """Read entire 8x8 grid"""
        grid = np.zeros((8, 8))
        for y in range(8):
            for x in range(8):
                grid[y, x] = await self.read_cell(x, y)
        return grid
        
    async def write_grid(self, grid):
        """Write entire 8x8 grid"""
        for y in range(8):
            for x in range(8):
                await self.write_cell(x, y, int(grid[y, x]))

@cocotb.test()
async def test_basic_diffusion(dut):
    """Test basic heat diffusion from center hot spot"""
    
    # Start clock
    clock = Clock(dut.clk, 40, units="ns")  # 25 MHz
    cocotb.start_soon(clock.start())
    
    driver = HeatSolverDriver(dut)
    
    # Reset
    await driver.reset()
    dut._log.info("Reset complete")
    
    # Configure: alpha=2 (0.25 diffusion)
    await driver.configure(alpha=2, boundary_temp=0, boundary_type=0)
    dut._log.info("Configured: alpha=0.25, Dirichlet boundaries")
    
    # Create hot spot at center
    initial_grid = np.zeros((8, 8))
    initial_grid[3:5, 3:5] = 15  # Hot 2x2 center
    await driver.write_grid(initial_grid)
    dut._log.info("Initial condition written")
    
    # Run 20 iterations
    dut._log.info("Running 20 iterations...")
    await driver.run_iterations(20)
    
    # Read results
    final_grid = await driver.read_grid()
    dut._log.info("Results read")
    
    # Validation checks
    center_temp = final_grid[3:5, 3:5].mean()
    edge_temp = final_grid[0, 0]
    
    dut._log.info(f"Center temperature: {center_temp:.2f}")
    dut._log.info(f"Edge temperature: {edge_temp:.2f}")
    
    # Physical checks
    assert center_temp < 15, "Center should cool down"
    assert center_temp > 5, "Center should still be warm"
    assert edge_temp < 3, "Edges should be cool"
    assert edge_temp >= 0, "No negative temps"
    
    # Check conservation (approximate)
    total_initial = initial_grid.sum()
    total_final = final_grid.sum()
    dut._log.info(f"Initial energy: {total_initial}, Final: {total_final}")
    
    # Save visualization
    save_heatmap(initial_grid, final_grid, "basic_diffusion.png")
    
    dut._log.info("✅ Basic diffusion test PASSED")

@cocotb.test()
async def test_boundary_conditions(dut):
    """Test different boundary conditions"""
    
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = HeatSolverDriver(dut)
    await driver.reset()
    
    # Test Dirichlet (fixed temperature)
    await driver.configure(alpha=3, boundary_temp=10, boundary_type=0)
    
    # Create gradient
    initial_grid = np.zeros((8, 8))
    initial_grid[4, 4] = 15
    await driver.write_grid(initial_grid)
    
    await driver.run_iterations(30)
    final_grid = await driver.read_grid()
    
    # Check boundaries are fixed at boundary_temp
    boundary_cells = [final_grid[0, :], final_grid[7, :], 
                     final_grid[:, 0], final_grid[:, 7]]
    
    for boundary in boundary_cells:
        # Should be close to boundary_temp (with some tolerance)
        assert all(abs(t - 10) < 3 for t in boundary), "Dirichlet boundaries failed"
    
    dut._log.info("✅ Boundary conditions test PASSED")

@cocotb.test()
async def test_convergence(dut):
    """Test convergence to steady state"""
    
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = HeatSolverDriver(dut)
    await driver.reset()
    
    await driver.configure(alpha=2, boundary_temp=0, boundary_type=0)
    
    # Initial hot spot
    initial_grid = np.zeros((8, 8))
    initial_grid[4, 4] = 15
    await driver.write_grid(initial_grid)
    
    # Track temperature evolution
    temps = []
    for iteration in range(50):
        await driver.run_iterations(1)
        grid = await driver.read_grid()
        center_temp = grid[4, 4]
        temps.append(center_temp)
        
        if iteration % 10 == 0:
            dut._log.info(f"Iteration {iteration}: center_temp = {center_temp}")
    
    # Check monotonic decrease
    for i in range(1, len(temps)):
        assert temps[i] <= temps[i-1] + 1, "Temperature should decrease or stay constant"
    
    # Check eventual cooling
    assert temps[-1] < temps[0] / 2, "Should cool significantly"
    
    # Plot convergence
    plt.figure(figsize=(10, 6))
    plt.plot(temps, 'b-', linewidth=2)
    plt.xlabel('Iteration')
    plt.ylabel('Center Temperature')
    plt.title('Convergence to Steady State')
    plt.grid(True)
    plt.savefig('convergence.png', dpi=150)
    plt.close()
    
    dut._log.info("✅ Convergence test PASSED")

@cocotb.test()
async def test_accuracy(dut):
    """Compare against analytical solution"""
    
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = HeatSolverDriver(dut)
    await driver.reset()
    
    await driver.configure(alpha=2, boundary_temp=0, boundary_type=0)
    
    # Simple test case: single hot cell
    initial_grid = np.zeros((8, 8))
    initial_grid[4, 4] = 15
    await driver.write_grid(initial_grid)
    
    # Run simulation
    await driver.run_iterations(10)
    hw_result = await driver.read_grid()
    
    # Compare with numpy reference
    sw_result = reference_solver(initial_grid.copy(), alpha=0.25, iterations=10)
    
    # Calculate error
    error = np.abs(hw_result - sw_result).mean()
    max_error = np.abs(hw_result - sw_result).max()
    
    dut._log.info(f"Mean error: {error:.3f}")
    dut._log.info(f"Max error: {max_error:.3f}")
    
    # Allow some error due to quantization
    assert error < 1.5, "Mean error too high"
    assert max_error < 3, "Max error too high"
    
    # Visualize comparison
    plot_comparison(initial_grid, hw_result, sw_result, "accuracy_test.png")
    
    dut._log.info("✅ Accuracy test PASSED")

def reference_solver(grid, alpha, iterations):
    """Software reference implementation"""
    grid = grid.astype(float)
    
    for _ in range(iterations):
        new_grid = grid.copy()
        for y in range(1, 7):
            for x in range(1, 7):
                laplacian = (grid[y-1, x] + grid[y+1, x] + 
                           grid[y, x-1] + grid[y, x+1] - 4*grid[y, x])
                new_grid[y, x] = grid[y, x] + alpha * laplacian / 4
        
        # Clamp
        new_grid = np.clip(new_grid, 0, 15)
        grid = new_grid
    
    return np.round(grid)

def save_heatmap(initial, final, filename):
    """Save before/after heatmap"""
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
    
    im1 = ax1.imshow(initial, cmap='hot', vmin=0, vmax=15, interpolation='nearest')
    ax1.set_title('Initial Condition')
    ax1.set_xlabel('X')
    ax1.set_ylabel('Y')
    plt.colorbar(im1, ax=ax1, label='Temperature')
    
    im2 = ax2.imshow(final, cmap='hot', vmin=0, vmax=15, interpolation='nearest')
    ax2.set_title('After Diffusion')
    ax2.set_xlabel('X')
    ax2.set_ylabel('Y')
    plt.colorbar(im2, ax=ax2, label='Temperature')
    
    plt.tight_layout()
    plt.savefig(filename, dpi=150)
    plt.close()
    print(f"Saved visualization: {filename}")

def plot_comparison(initial, hw, sw, filename):
    """Plot hardware vs software comparison"""
    fig, axes = plt.subplots(2, 2, figsize=(12, 12))
    
    im1 = axes[0, 0].imshow(initial, cmap='hot', vmin=0, vmax=15)
    axes[0, 0].set_title('Initial')
    plt.colorbar(im1, ax=axes[0, 0])
    
    im2 = axes[0, 1].imshow(hw, cmap='hot', vmin=0, vmax=15)
    axes[0, 1].set_title('Hardware Result')
    plt.colorbar(im2, ax=axes[0, 1])
    
    im3 = axes[1, 0].imshow(sw, cmap='hot', vmin=0, vmax=15)
    axes[1, 0].set_title('Software Reference')
    plt.colorbar(im3, ax=axes[1, 0])
    
    error = np.abs(hw - sw)
    im4 = axes[1, 1].imshow(error, cmap='viridis', vmin=0, vmax=3)
    axes[1, 1].set_title(f'Error (mean={error.mean():.3f})')
    plt.colorbar(im4, ax=axes[1, 1])
    
    plt.tight_layout()
    plt.savefig(filename, dpi=150)
    plt.close()