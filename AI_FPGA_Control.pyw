from pathlib import Path
import runpy

runpy.run_path(
    str(Path(__file__).resolve().parent / "In_FPGA" / "RISCV_CNN_AI_Accelerator"
        / "tools" / "ai_fpga_gui.py"),
    run_name="__main__",
)
