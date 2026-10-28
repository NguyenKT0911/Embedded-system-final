import html
import xml.etree.ElementTree as ET
from pathlib import Path

def generate_drawio():
    cells = []
    cell_id = 2

    def add_cell_raw(xml_str):
        nonlocal cell_id
        cells.append(xml_str)
        cell_id += 1
        return cell_id - 1

    def make_node(cid, parent, style, html_value, x, y, w, h):
        escaped_val = html.escape(html_value, quote=True)
        if "html=1" not in style:
            style = "html=1;" + style
        return f'''<mxCell id="{cid}" parent="{parent}" style="{style}" value="{escaped_val}" vertex="1">
      <mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry" />
    </mxCell>'''

    def make_edge(cid, parent, style, html_value, src, dst, waypoints=None):
        escaped_val = html.escape(html_value, quote=True)
        if "html=1" not in style:
            style = "html=1;" + style
        pts_xml = ""
        if waypoints and len(waypoints) > 0:
            pts_str = "".join([f'<mxPoint x="{pt[0]}" y="{pt[1]}" />' for pt in waypoints])
            pts_xml = f'<Array as="points">{pts_str}</Array>'
        return f'''<mxCell id="{cid}" parent="{parent}" style="{style}" value="{escaped_val}" edge="1">
      <mxGeometry relative="1" as="geometry">
        <mxPoint x="{src[0]}" y="{src[1]}" as="sourcePoint" />
        <mxPoint x="{dst[0]}" y="{dst[1]}" as="targetPoint" />
        {pts_xml}
      </mxGeometry>
    </mxCell>'''

    def add_node(cid, style, html_value, x, y, w, h):
        add_cell_raw(make_node(cid, "1", style, html_value, x, y, w, h))

    def add_edge(cid, style, html_value, src, dst, waypoints=None):
        add_cell_raw(make_edge(cid, "1", style, html_value, src, dst, waypoints=waypoints))

    # ==========================================
    # 0. Title Banner
    # ==========================================
    add_node("title_bg", "rounded=1;whiteSpace=wrap;fillColor=#1E293B;strokeColor=#0F172A;shadow=1;arcSize=6;", "", 60, 40, 3620, 75)
    add_node("title_text", "text;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;", 
             '<font color="#FFFFFF" style="font-size: 26px; font-weight: bold; font-family: \'Segoe UI\', Helvetica, Arial, sans-serif;">RISC-V Controlled INT8 CNN Inference System on Tang Nano 20K</font><div><font color="#94A3B8" style="font-size: 14px;">End-to-End Architecture: PC Preprocessing • UART &amp; SD-SPI Ingestion • RV32I Firmware Control • INT8 Hardware Accelerator (Conv1/Conv2) • HDMI Display</font></div>',
             80, 45, 3580, 65)

    # ==========================================
    # 1. PC HOST BLOCK (Left side)
    # ==========================================
    add_node("pc_container", "rounded=1;whiteSpace=wrap;fillColor=#F8FAFC;strokeColor=#0284C7;strokeWidth=2;dashed=1;dashPattern=6 6;arcSize=3;", "", 60, 140, 520, 930)
    add_node("pc_header", "rounded=1;whiteSpace=wrap;fillColor=#0284C7;strokeColor=#0369A1;arcSize=8;align=center;",
             '<font color="#FFFFFF" style="font-size: 18px; font-weight: bold;">💻 PC Host (Python Environment)</font><div><font color="#E0F2FE" style="font-size: 12px;">Image Preprocessing &amp; INT8 Quantization Pipeline</font></div>',
             80, 160, 480, 55)

    add_node("pc_step1", "rounded=1;whiteSpace=wrap;fillColor=#FFFFFF;strokeColor=#CBD5E1;strokeWidth=1.5;align=left;spacingLeft=15;",
             '<b style="color: #0F172A; font-size: 14px;">1. Real Handwritten Digits Source</b><div style="font-size: 12px; color: #475569;">• Camera capture / raw image dataset (50 samples)<br>• Classes 0 to 9 in raw directories (<i>raw/0..raw/9</i>)</div>',
             90, 235, 460, 60)

    add_node("pc_step2", "rounded=1;whiteSpace=wrap;fillColor=#FFFFFF;strokeColor=#CBD5E1;strokeWidth=1.5;align=left;spacingLeft=15;",
             '<b style="color: #0F172A; font-size: 14px;">2. Margin Cleaning &amp; Illumination Leveling</b><div style="font-size: 12px; color: #475569;">• Margin clamp: Filter extreme border pixels (avoid scanner spikes)<br>• Gaussian background division: Remove shadows &amp; lighting gradients</div>',
             90, 315, 460, 60)

    add_node("pc_step3", "rounded=1;whiteSpace=wrap;fillColor=#FFFFFF;strokeColor=#CBD5E1;strokeWidth=1.5;align=left;spacingLeft=15;",
             '<b style="color: #0F172A; font-size: 14px;">3. Otsu Threshold &amp; Stroke Normalization</b><div style="font-size: 12px; color: #475569;">• Otsu binarization + Morphological closing (heal micro-gaps)<br>• Distance Transform: Adaptive dilation for thin ballpoint pen strokes</div>',
             90, 395, 460, 60)

    add_node("pc_step4", "rounded=1;whiteSpace=wrap;fillColor=#FFFFFF;strokeColor=#CBD5E1;strokeWidth=1.5;align=left;spacingLeft=15;",
             '<b style="color: #0F172A; font-size: 14px;">4. Crop &amp; Proportional Resize (20×20 in 28×28)</b><div style="font-size: 12px; color: #475569;">• Tight bounding box crop around connected components<br>• Proportional resize to 20×20 box on 28×28 black canvas<br>• Bounded Center-of-Mass alignment (MNIST convention)</div>',
             90, 475, 460, 70)

    add_node("pc_step5", "rounded=1;whiteSpace=wrap;fillColor=#FFFFFF;strokeColor=#CBD5E1;strokeWidth=1.5;align=left;spacingLeft=15;",
             '<b style="color: #0F172A; font-size: 14px;">5. Normalization &amp; INT8 Quantization</b><div style="font-size: 12px; color: #475569;">• Float standard: <i>x_float = (img/255.0 - 0.1307) / 0.3081</i><br>• Symmetric signed INT8: <i>x_int8 = clip(round(x_float / 0.022216), -128, 127)</i><br>• Output format: <b>1×28×28 signed INT8 array (784 bytes)</b></div>',
             90, 565, 460, 75)

    add_node("pc_step6", "rounded=1;whiteSpace=wrap;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=1.5;align=left;spacingLeft=15;",
             '<b style="color: #1D4ED8; font-size: 14px;">6. UART Packet Packaging (protocol.py)</b><div style="font-size: 12px; color: #1E40AF;">• Header: MAGIC <code>0xA5 0x5A</code> | CMD: <code>0x01 (LOAD_INPUT)</code><br>• Length: 784 bytes (uint32 LE) | Payload: INT8 bytes<br>• Checksum: 32-bit CRC32 (Ethernet polynomial)</div>',
             90, 660, 460, 70)

    add_node("pc_host_ctrl", "rounded=1;whiteSpace=wrap;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=1.5;align=left;spacingLeft=15;",
             '<b style="color: #047857; font-size: 14px;">7. UART Host Client (client.py / full_inference.py)</b><div style="font-size: 12px; color: #065F46;">• PySerial COM port communication (115200 / 921600 baud)<br>• Streaming packets to FPGA &amp; receiving prediction / debug log<br>• Host-side FC layer inference &amp; accuracy verification (96.0%)</div>',
             90, 750, 460, 70)

    # PC internal flow arrows
    for y_top in [295, 375, 455, 545, 640, 730]:
        add_edge(f"pc_arrow_{y_top}", "edgeStyle=straight;strokeColor=#64748B;strokeWidth=2;endArrow=block;endFill=1;", "", (320, y_top), (320, y_top + 20))

    # ==========================================
    # 2. INTERMEDIATE INTERFACES (onboard BL616 UART & SD Card)
    # ==========================================
    # Onboard UART bridge (Top-mid, aligned with UART MMIO at y=330)
    add_node("onboard_uart_box", "rounded=1;whiteSpace=wrap;fillColor=#FEF3C7;strokeColor=#D97706;strokeWidth=2;arcSize=8;align=center;",
             '<font color="#92400E" style="font-size: 16px; font-weight: bold;">🔌 Onboard BL616</font><div><b style="font-size: 12px; color: #B45309;">USB-to-UART Bridge</b></div><div style="font-size: 11px; color: #78350F; margin-top: 4px;">FPGA RX pin 70 / TX pin 69<br>Baud: 115200</div>',
             640, 330, 190, 120)

    # MicroSD Card Box (Bottom-mid, aligned with SD-SPI MMIO at y=550)
    add_node("sdcard_box", "rounded=1;whiteSpace=wrap;fillColor=#EDE9FE;strokeColor=#7C3AED;strokeWidth=2;arcSize=8;align=center;",
             '<font color="#5B21B6" style="font-size: 15px; font-weight: bold;">💾 External MicroSD</font><div><b style="font-size: 12px; color: #6D28D9;">SPI Interface</b></div><div style="font-size: 11px; color: #4C1D95; text-align: left; padding-left: 10px; margin-top: 4px;">• Model Weights (INT8)<br>• Quantization Params<br>• Offline Test Dataset<br>• Flash Non-volatile</div>',
             640, 545, 190, 130)

    # Clean USB Routing: PC Client -> onboard BL616 -> UART Loader
    add_edge("usb_edge", "edgeStyle=orthogonalEdgeStyle;rounded=0;strokeColor=#D97706;strokeWidth=2.5;endArrow=classic;endFill=1;",
             '<b style="color: #D97706; font-size: 11px;">USB Cable (D+/D-)</b>', (550, 785), (640, 390), waypoints=[(605, 785), (605, 390)])

    # ==========================================
    # 3. TANG NANO 20K FPGA BOUNDARY
    # ==========================================
    add_node("fpga_container", "rounded=1;whiteSpace=wrap;fillColor=#FAFAFA;strokeColor=#DC2626;strokeWidth=3;arcSize=2;", "", 890, 140, 2060, 1380)
    add_node("fpga_header", "rounded=1;whiteSpace=wrap;fillColor=#DC2626;strokeColor=#B91C1C;arcSize=6;align=center;",
             '<font color="#FFFFFF" style="font-size: 20px; font-weight: bold;">⚡ Tang Nano 20K FPGA (Gowin GW2AR-LV18QN88C8/I7 — 20,736 LUTs, 48 B-SRAMs, Embedded 64Mb PSRAM)</font>',
             910, 160, 2020, 45)

    # 3.1 Controller & Memory Row
    # UART MMIO (horizontally aligned with onboard bridge at y=330)
    add_node("uart_mmio_box", "rounded=1;whiteSpace=wrap;fillColor=#FFFBEB;strokeColor=#F59E0B;strokeWidth=2;align=center;",
             '<b style="font-size: 15px; color: #92400E;">UART RX/TX &amp; MMIO</b><div><code style="color: #B45309; font-size: 11px;">Base: 0x2000_0000</code></div><div style="font-size: 11px; color: #78350F; text-align: left; padding-left: 8px; margin-top: 4px;">• Baud Gen &amp; 8N1 Framing<br>• RX FIFO &amp; TX FIFO<br>• Overrun/Framing Error</div>',
             920, 330, 220, 120)

    # SD-SPI MMIO (Horizontally aligned with SD Card at y=550)
    add_node("sd_spi_mmio_box", "rounded=1;whiteSpace=wrap;fillColor=#F5F3FF;strokeColor=#8B5CF6;strokeWidth=2;align=center;",
             '<b style="font-size: 15px; color: #5B21B6;">SD-SPI Controller MMIO</b><div><code style="color: #6D28D9; font-size: 11px;">Base: 0x3000_0000</code></div><div style="font-size: 11px; color: #4C1D95; text-align: left; padding-left: 8px; margin-top: 4px;">• SPI Master (SCLK, CS, MOSI, MISO)<br>• Command / Response FSM<br>• Block Transfer (512B sectors)</div>',
             920, 545, 220, 120)

    # Central RV32I CPU
    add_node("rv32i_cpu_box", "rounded=1;whiteSpace=wrap;fillColor=#EFF6FF;strokeColor=#2563EB;strokeWidth=3;arcSize=6;shadow=1;align=center;",
             '<font color="#1E3A8A" style="font-size: 18px; font-weight: bold;">🧠 Central RISC-V CPU (RV32I Core)</font><div><b style="color: #1D4ED8; font-size: 13px;">Running Bare-Metal Firmware C (<i>uart_accel_firmware.hex</i>)</b></div><hr style="border: 0.5px solid #93C5FD;">'
             '<div style="text-align: left; font-size: 11.5px; color: #1E40AF; padding-left: 10px;">'
             '<b>Master Controller &amp; Inference Coordinator Tasks:</b><br>'
             '• <b>UART Ingestion:</b> Receives PING, CONFIG, LOAD_INPUT, START; checks CRC32 &amp; returns ACK/NACK.<br>'
             '• <b>SD-SPI Loader:</b> Reads model weights, quantization scale params &amp; offline dataset images into BRAM.<br>'
             '• <b>Working BRAM Management:</b> Allocates input activations, kernel weights &amp; intermediate buffers.<br>'
             '• <b>Hardware Accelerator Control:</b> Configures layer parameters, triggers START, polls DONE status.<br>'
             '• <b>Layer Post-Processing:</b> Executes MaxPool 2×2, Requantization INT32→INT8, FC1 (128), FC2 (10), Argmax.<br>'
             '• <b>Result Handoff:</b> Writes prediction[3:0], valid, sample_id to Result MMIO; streams logs back to PC.</div>',
             1190, 240, 580, 225)

    # Working BRAM (DMEM)
    add_node("bram_dmem_box", "rounded=1;whiteSpace=wrap;fillColor=#ECFDF5;strokeColor=#059669;strokeWidth=2;arcSize=6;align=center;",
             '<font color="#065F46" style="font-size: 16px; font-weight: bold;">🗄️ Working Data BRAM (DMEM / Scratchpad)</font><div><code style="color: #047857; font-size: 11px;">Base: 0x0000_0000 | 4096 Words (16 KB) Dual-Port BRAM</code></div>'
             '<div style="text-align: left; font-size: 11.5px; color: #064E3B; padding-left: 10px; margin-top: 4px;">'
             '• <b>0x0000 - 0x0FFF:</b> Input Activations Buffer (784B for 28×28, 3136B for 14×14×16)<br>'
             '• <b>0x1000 - 0x2FFF:</b> Kernel Weights Buffer (144B for Conv1, 4608B for Conv2)<br>'
             '• <b>0x3000 - 0x3FFF:</b> Intermediate Layer Data, Requantization &amp; FC Feature Vectors<br>'
             '<i style="color: #059669;">* High-speed working memory; SD Card reads into BRAM; SD does not connect directly to PE Array.</i></div>',
             1190, 490, 580, 150)

    # Result MMIO
    add_node("result_mmio_box", "rounded=1;whiteSpace=wrap;fillColor=#FFF1F2;strokeColor=#E11D48;strokeWidth=2;arcSize=6;align=center;",
             '<font color="#9F1239" style="font-size: 16px; font-weight: bold;">🎯 Result MMIO Register</font><div><code style="color: #BE123C; font-size: 11px;">Base: 0x1000_0000</code></div>'
             '<div style="text-align: left; font-size: 11.5px; color: #881337; padding-left: 10px; margin-top: 4px;">'
             '• <b>prediction[3:0]</b>: Classified digit (0-9)<br>'
             '• <b>prediction_valid</b>: Pulse on completion<br>'
             '• <b>sample_id[31:0]</b>: Image index tag<br>'
             '• <b>status_flags[31:0]</b>: Error &amp; cycle stats</div>',
             1830, 240, 290, 135)

    # HDMI Display Subsystem
    add_node("hdmi_box", "rounded=1;whiteSpace=wrap;fillColor=#FEF2F2;strokeColor=#DC2626;strokeWidth=2.5;arcSize=6;align=center;",
             '<font color="#991B1B" style="font-size: 16px; font-weight: bold;">🖥️ HDMI Display Subsystem</font><div><b style="color: #B91C1C; font-size: 12px;">(Teammate HDMI Module / Video IP)</b></div><hr style="border: 0.5px solid #FCA5A5;">'
             '<div style="text-align: left; font-size: 11.5px; color: #7F1D1D; padding-left: 8px;">'
             '• Renders 28×28 input image matrix<br>'
             '• Displays Predicted Digit (0-9) &amp; Status<br>'
             '• Shows Inference Latency / Error Flags<br>'
             '• Drives physical DVI/HDMI TMDS pairs</div>',
             2180, 240, 320, 150)

    # Straight horizontal external connections
    add_edge("e_onboard_uart", "edgeStyle=straight;strokeColor=#D97706;strokeWidth=3;endArrow=classic;startArrow=classic;",
             '<b style="color: #B45309; font-size: 11px;">UART RX/TX</b>', (830, 390), (920, 390))

    add_edge("e_sdcard_spi", "edgeStyle=straight;strokeColor=#7C3AED;strokeWidth=3;endArrow=classic;startArrow=classic;",
             '<b style="color: #6D28D9; font-size: 11px;">SPI (CS, SCLK, MOSI, MISO)</b>', (830, 610), (920, 610))

    add_edge("e_result_hdmi", "edgeStyle=straight;strokeColor=#E11D48;strokeWidth=3;endArrow=classic;",
             '<b style="color: #BE123C; font-size: 11px;">prediction[3:0], valid, sample_id</b>', (2120, 307), (2180, 307))

    # 32-bit SoC System MMIO & Memory Interconnect Bus Bar
    add_node("mmio_bus_bar", "rounded=1;whiteSpace=wrap;fillColor=#334155;strokeColor=#1E293B;strokeWidth=1;align=center;",
             '<b style="color: #F8FAFC; font-size: 13px;">32-bit SoC System MMIO &amp; Memory Interconnect Bus (Address, WData, RData, WStrobe, Re/We)</b>',
             920, 680, 1980, 35)

    # Perpendicular Bus Connections
    add_edge("e_uart_bus", "edgeStyle=straight;strokeColor=#F59E0B;strokeWidth=2.5;endArrow=classic;startArrow=classic;", "", (1030, 450), (1030, 680))
    add_edge("e_sd_bus", "edgeStyle=straight;strokeColor=#8B5CF6;strokeWidth=2.5;endArrow=classic;startArrow=classic;", "", (1080, 665), (1080, 680))
    add_edge("e_cpu_bus", "edgeStyle=straight;strokeColor=#2563EB;strokeWidth=3;endArrow=classic;startArrow=classic;", '<b style="color: #1D4ED8; font-size: 11px;">CPU Bus Interface</b>', (1480, 465), (1480, 680))
    add_edge("e_bram_bus", "edgeStyle=straight;strokeColor=#059669;strokeWidth=2.5;endArrow=classic;startArrow=classic;", "", (1580, 640), (1580, 680))
    add_edge("e_result_bus", "edgeStyle=straight;strokeColor=#E11D48;strokeWidth=2.5;endArrow=classic;startArrow=classic;", "", (1975, 375), (1975, 680))

    # ==========================================
    # 3.2 DEDICATED CNN ACCELERATOR HARDWARE CORE
    # ==========================================
    add_node("accel_container", "rounded=1;whiteSpace=wrap;fillColor=#F0FDF4;strokeColor=#16A34A;strokeWidth=2.5;dashed=1;dashPattern=8 6;arcSize=3;", "", 920, 745, 1980, 360)
    
    # MMIO Slave Interface Port (Top-Left of Accelerator, directly below Bus Bar)
    add_node("accel_port_box", "rounded=1;whiteSpace=wrap;fillColor=#DCFCE7;strokeColor=#16A34A;strokeWidth=2;arcSize=6;align=center;",
             '<b style="font-size: 12px; color: #166534;">🔌 MMIO Slave Port (Base: 0x4000_0000)</b>',
             940, 765, 270, 40)

    # Dedicated Accelerator Title Banner (Top-Right, beside MMIO Slave Port, no collision)
    add_node("accel_header", "rounded=1;whiteSpace=wrap;fillColor=#16A34A;strokeColor=#15803D;arcSize=6;align=center;",
             '<font color="#FFFFFF" style="font-size: 16px; font-weight: bold;">⚙️ Dedicated INT8 CNN Hardware Accelerator RTL Core</font><div><font color="#DCFCE7" style="font-size: 11px;">INT8×INT8 → INT32 4×4 Systolic Parallel Convolution Engine • Offloaded Hardware for Conv1 &amp; Conv2</font></div>',
             1240, 765, 1640, 40)

    # Bus connection to MMIO Port, then into Reg File
    add_edge("e_acc_bus_port", "edgeStyle=straight;strokeColor=#16A34A;strokeWidth=2.5;endArrow=classic;startArrow=classic;", "", (1075, 715), (1075, 765))
    add_edge("e_port_rf", "edgeStyle=straight;strokeColor=#16A34A;strokeWidth=2.5;endArrow=classic;startArrow=classic;", "", (1075, 805), (1075, 825))

    # 1. MMIO Register File
    add_node("acc_rf_box", "rounded=1;whiteSpace=wrap;fillColor=#FEF2F2;strokeColor=#EF4444;strokeWidth=2;align=left;spacingLeft=10;",
             '<b style="font-size: 13px; color: #991B1B;">1. MMIO Reg File (0x00-0x48)</b><hr style="border: 0.5px solid #FCA5A5;">'
             '<div style="font-size: 10.5px; color: #7F1D1D; font-family: \'Courier New\', monospace;">'
             '• CTRL (0x00) &amp; STATUS (0x04)<br>'
             '• IN_H/W (0x08/0C) | CIN/COUT (0x10/14)<br>'
             '• KERNEL (0x18) | STRIDE (0x1C)<br>'
             '• PADDING (0x20) | RELU_EN (0x24)<br>'
             '• OUT_H/W (0x28/2C)<br>'
             '• INPUT_DATA (0x30) | WT_DATA (0x34)<br>'
             '• OUTPUT_DATA (0x38) | CYCLES (0x3C)<br>'
             '• ERROR_CODE (0x48)</div>',
             940, 825, 270, 220)

    # 2. Validation & Controller FSM
    add_node("acc_val_box", "rounded=1;whiteSpace=wrap;fillColor=#FFFBEB;strokeColor=#F59E0B;strokeWidth=1.5;align=center;",
             '<b style="font-size: 13px; color: #92400E;">2. Validation Unit</b><div style="font-size: 11px; color: #78350F; text-align: left; padding-left: 6px; margin-top: 3px;">• Dimension checks<br>• CIN/COUT alignment<br>• Generates config_ok</div>',
             1240, 825, 170, 90)

    add_node("acc_fsm_box", "rounded=1;whiteSpace=wrap;fillColor=#FFFBEB;strokeColor=#F59E0B;strokeWidth=1.5;align=center;",
             '<b style="font-size: 13px; color: #92400E;">3. Controller FSM</b><div style="font-size: 11px; color: #78350F; text-align: left; padding-left: 6px; margin-top: 3px;">• IDLE, CONFIG, RUN, DRAIN<br>• Core enable &amp; Done pulses<br>• Hardware handshaking</div>',
             1440, 825, 180, 90)

    # 3. Convolution Sequencer
    add_node("acc_seq_box", "rounded=1;whiteSpace=wrap;fillColor=#DCFCE7;strokeColor=#16A34A;strokeWidth=1.5;align=center;",
             '<b style="font-size: 13px; color: #166534;">4. Convolution Sequencer</b><div style="font-size: 11px; color: #14532D; text-align: left; padding-left: 6px; margin-top: 3px;">• Loops: oh, ow_base, oc_base, ic, kh, kw<br>• Schedules 4×4 output tile MAC runs</div>',
             1650, 825, 260, 90)

    # 4. Input & Weight Buffers
    add_node("acc_inbuf_box", "rounded=1;whiteSpace=wrap;fillColor=#DBEAFE;strokeColor=#2563EB;strokeWidth=1.5;align=center;",
             '<b style="font-size: 13px; color: #1E40AF;">Input Buffer (BRAM)</b><div style="font-size: 11px; color: #1E3A8A; margin-top: 3px;">Max: 3136 × INT8<br>Dual-port 4×INT8/word</div>',
             1240, 940, 170, 95)

    add_node("acc_wtbuf_box", "rounded=1;whiteSpace=wrap;fillColor=#DBEAFE;strokeColor=#2563EB;strokeWidth=1.5;align=center;",
             '<b style="font-size: 13px; color: #1E40AF;">Weight Buffer (BRAM)</b><div style="font-size: 11px; color: #1E3A8A; margin-top: 3px;">Max: 4608 × INT8<br>Dual-port 4×INT8/word</div>',
             1440, 940, 180, 95)

    # 5. Address Generator & Data Feeder
    add_node("acc_feeder_box", "rounded=1;whiteSpace=wrap;fillColor=#E0E7FF;strokeColor=#4F46E5;strokeWidth=1.5;align=center;",
             '<b style="font-size: 13px; color: #3730A3;">5. Address Gen &amp; Feeder 4×4</b><div style="font-size: 11px; color: #312E81; text-align: left; padding-left: 6px; margin-top: 3px;">• Computes row/col addresses with pad/stride<br>• Broadcasts 4 activations &amp; 4 weights to PEs</div>',
             1650, 940, 260, 95)

    # 6. PE Array 4x4
    add_node("acc_pe_array_box", "rounded=1;whiteSpace=wrap;fillColor=#FEF08A;strokeColor=#CA8A04;strokeWidth=2.5;arcSize=6;align=center;",
             '<font color="#713F12" style="font-size: 15px; font-weight: bold;">🧮 4×4 Systolic PE Array (16 Parallel MAC Units)</font><hr style="border: 0.5px solid #EAB308;">'
             '<div style="font-size: 11.5px; color: #854D0E; text-align: left; padding-left: 8px;">'
             '<b>16 × [INT8 Activation × INT8 Weight → INT32 Accumulator]</b><br>'
             '• Computes 16 parallel dot products per clock cycle<br>'
             '• High throughput: 16 MACs/cycle @ 27MHz/50MHz<br>'
             '• Exact bit-for-bit match with software reference</div>',
             1940, 825, 430, 210)

    # 7. Output Path, ReLU, Output Buffer
    add_node("acc_outpath_box", "rounded=1;whiteSpace=wrap;fillColor=#FCE7F3;strokeColor=#DB2777;strokeWidth=2;align=center;",
             '<b style="font-size: 13px; color: #831843;">6. Output Writer &amp; ReLU</b><div style="font-size: 11px; color: #9D174D; margin-top: 3px;">• HW ReLU: <i>max(0, acc)</i><br>• Assembles 4×4 tiles</div>',
             2400, 825, 210, 90)

    add_node("acc_outbuf_box", "rounded=1;whiteSpace=wrap;fillColor=#FCE7F3;strokeColor=#DB2777;strokeWidth=2;align=center;",
             '<b style="font-size: 13px; color: #831843;">7. Output Buffer (INT32)</b><div style="font-size: 11px; color: #9D174D; margin-top: 3px;">• Drains result to MMIO<br>• Ready/Valid streaming</div>',
             2400, 940, 210, 95)

    # Accelerator internal edges
    add_edge("e_rf_val", "edgeStyle=straight;strokeColor=#F59E0B;strokeWidth=2;endArrow=classic;", "config", (1210, 870), (1240, 870))
    add_edge("e_val_fsm", "edgeStyle=straight;strokeColor=#F59E0B;strokeWidth=2;endArrow=classic;", "ok", (1410, 870), (1440, 870))
    add_edge("e_fsm_seq", "edgeStyle=straight;strokeColor=#16A34A;strokeWidth=2;endArrow=classic;", "start", (1620, 870), (1650, 870))
    add_edge("e_seq_feeder", "edgeStyle=straight;strokeColor=#4F46E5;strokeWidth=2;endArrow=classic;", "indices", (1780, 915), (1780, 940))
    
    # Reg File writing to Input & Weight Buffers
    add_edge("e_rf_inbuf", "edgeStyle=straight;strokeColor=#2563EB;strokeWidth=2;endArrow=classic;", "write act", (1210, 970), (1240, 970))
    add_edge("e_inbuf_wtbuf", "edgeStyle=straight;strokeColor=#2563EB;strokeWidth=2;endArrow=classic;", "write wt", (1410, 970), (1440, 970))

    # Weight Buffer to Feeder
    add_edge("e_wtbuf_feeder", "edgeStyle=straight;strokeColor=#2563EB;strokeWidth=2;endArrow=classic;", "INT8 data", (1620, 987), (1650, 987))
    
    # Feeder to PE Array
    add_edge("e_feeder_pe", "edgeStyle=straight;strokeColor=#CA8A04;strokeWidth=2.5;endArrow=classic;", '<b style="color: #854D0E; font-size: 11px;">4×4 Act &amp; Wt</b>', (1910, 987), (1940, 987))
    
    # PE Array to Output Writer
    add_edge("e_pe_relu", "edgeStyle=straight;strokeColor=#DB2777;strokeWidth=2.5;endArrow=classic;", '<b style="color: #831843; font-size: 11px;">INT32 sum</b>', (2370, 870), (2400, 870))
    
    # Output Writer to Output Buffer
    add_edge("e_relu_outbuf", "edgeStyle=straight;strokeColor=#DB2777;strokeWidth=2;endArrow=classic;", "ReLU out", (2505, 915), (2505, 940))

    # ==========================================
    # 3.3 FULL CNN INFERENCE DATAFLOW RIBBON
    # ==========================================
    add_node("flow_container", "rounded=1;whiteSpace=wrap;fillColor=#F8FAFC;strokeColor=#475569;strokeWidth=2;arcSize=4;", "", 920, 1130, 1980, 360)
    add_node("flow_header", "rounded=1;whiteSpace=wrap;fillColor=#475569;strokeColor=#334155;arcSize=6;align=center;",
             '<font color="#FFFFFF" style="font-size: 16px; font-weight: bold;">🔄 Full End-to-End CNN Inference Pipeline: Hardware Acceleration vs. Firmware Coordination</font>',
             940, 1145, 1940, 35)

    flow_steps = [
        ("Input INT8", "1×28×28 INT8<br>[-128, 127]<br>(784 bytes)", "#DBEAFE", "#2563EB", 940, 1195, 160, 95),
        ("Conv1 HW Core", "16 Filters 3×3<br>INT8×INT8→INT32<br>(16×28×28 Out)", "#DCFCE7", "#16A34A", 1140, 1195, 180, 95),
        ("RV32I Firmware", "ReLU + MaxPool 2×2<br>Requantize to INT8<br>(16×14×14 INT8)", "#EFF6FF", "#3B82F6", 1360, 1195, 190, 95),
        ("Conv2 HW Core", "32 Filters 3×3<br>INT8×INT8→INT32<br>(32×14×14 Out)", "#DCFCE7", "#16A34A", 1590, 1195, 180, 95),
        ("RV32I Firmware", "ReLU + MaxPool 2×2<br>Requantize to INT8<br>(32×7×7 = 1568 feats)", "#EFF6FF", "#3B82F6", 1810, 1195, 190, 95),
        ("FC1 (Firmware)", "1568 → 128 nodes<br>INT8 MAC + Bias<br>ReLU activation", "#FDF4FF", "#C026D3", 2040, 1195, 180, 95),
        ("FC2 (Firmware)", "128 → 10 Logits<br>INT8 MAC + Bias<br>Output Scores", "#FDF4FF", "#C026D3", 2260, 1195, 170, 95),
        ("Argmax Result", "Index of max logit<br>Digit 0 to 9<br>(e.g., Class '4')", "#FEF08A", "#CA8A04", 2470, 1195, 160, 95),
    ]

    for title, desc, f_color, s_color, x, y, w, h in flow_steps:
        is_hw = "HW Core" in title
        hw_tag = '<span style="background: #15803D; color: #FFF; font-size: 9px; padding: 2px 4px; border-radius: 3px;">RTL HARDWARE</span>' if is_hw else '<span style="background: #2563EB; color: #FFF; font-size: 9px; padding: 2px 4px; border-radius: 3px;">RV32I C FIRMWARE</span>' if ("Firmware" in title or "FC" in title or "Argmax" in title) else '<span style="background: #64748B; color: #FFF; font-size: 9px; padding: 2px 4px; border-radius: 3px;">IMAGE DATA</span>'
        add_node(f"flow_box_{x}", f"rounded=1;whiteSpace=wrap;fillColor={f_color};strokeColor={s_color};strokeWidth=2;arcSize=8;align=center;",
                 f'<b style="font-size: 13px;">{title}</b><div>{hw_tag}</div><div style="font-size: 11px; margin-top: 4px;">{desc}</div>',
                 x, y, w, h)

    # Flow arrows between pipeline steps
    for i in range(len(flow_steps) - 1):
        x_src = flow_steps[i][4] + flow_steps[i][6]
        x_dst = flow_steps[i+1][4]
        add_edge(f"flow_arr_{i}", "edgeStyle=straight;strokeColor=#334155;strokeWidth=2.5;endArrow=classic;endFill=1;", "", (x_src, 1242), (x_dst, 1242))

    add_node("flow_legend", "rounded=1;whiteSpace=wrap;fillColor=#FFFFFF;strokeColor=#CBD5E1;align=left;spacingLeft=15;",
             '<b style="font-size: 13px; color: #0F172A;">📌 Implementation Note on Convolution vs. Fully Connected (FC) Layers:</b>'
             '<div style="font-size: 11.5px; color: #334155; margin-top: 4px;">'
             '• <b style="color: #15803D;">Offloaded to Hardware Accelerator:</b> Conv1 (12,544 INT32 MAC outputs) and Conv2 (6,272 INT32 MAC outputs) are executed entirely by the dedicated 4×4 PE array hardware RTL.<br>'
             '• <b style="color: #2563EB;">Executed by Bare-Metal Firmware C on RV32I:</b> MaxPool 2×2, intermediate layer Requantization (INT32→INT8), FC1 (128 nodes), FC2 (10 logits), and Argmax are executed by the CPU firmware without dedicated standalone FC RTL engines.<br>'
              '• <b style="color: #D97706;">Two Input Data Paths:</b> (1) <i>PC Update Path:</i> PC GUI → onboard BL616 UART → RV32I → verified microSD slot. (2) <i>Inference Path:</i> microSD (SPI) → RV32I → BRAM/PE array.</div>',
             940, 1310, 1940, 125)

    # ==========================================
    # 4. VERIFIED SCOPE BOX (Top-Right)
    # ==========================================
    add_node("verified_container", "rounded=1;whiteSpace=wrap;fillColor=#F0FDF4;strokeColor=#15803D;strokeWidth=2.5;arcSize=4;shadow=1;", "", 3020, 140, 660, 820)
    add_node("verified_header", "rounded=1;whiteSpace=wrap;fillColor=#15803D;strokeColor=#166534;arcSize=6;align=center;",
             '<font color="#FFFFFF" style="font-size: 18px; font-weight: bold;">✅ Verified Scope &amp; Project Status</font>',
             3040, 160, 620, 45)

    verified_items = [
        ("RV32I bare-metal Firmware C implemented", "Complete UART protocol handling, SD-SPI loader, memory management, and full inference coordination.", True),
        ("UART RX/TX and MMIO implemented", "Baudrate 115200/921600 with framing, overrun protection, and CRC32 hardware/software verification.", True),
        ("SD-SPI interface implemented", "SPI master protocol controller for external non-volatile model weights and dataset access.", True),
        ("Conv1 and Conv2 RTL outputs match Python golden with zero mismatch", "Cycle-accurate ModelSim/Icarus Verilog testbenches verify 100% bit-exact equivalence (0 error across 18,816 output words).", True),
        ("Real handwritten images preprocess &amp; INT8 quantization verified", "Illumination leveling, stroke width distance transform, and scale normalization tested on 50 real handwritten digits.", True),
        ("Float32 and INT8 real-image accuracy 48/50 = 96.0%", "Quantization loss is 0.00% (INT8 predictions match Float32 predictions identically across all 50 samples).", True),
        ("Real handwritten samples successfully propagated through RTL Conv1/Conv2 simulation", "Sample 4_01 verified end-to-end through RISC-V SoC + AI Accelerator hardware simulation with 99.99% confidence on Class 4.", True),
        ("Gowin synthesis, place-and-route and bitstream generation completed", "Bitstream file TangNano20K_RISCV_CNN.fs generated and ready for SRAM/Flash programming.", True),
        ("Physical Tang Nano 20K, onboard UART, SD Card and HDMI bring-up", "Final verification uses the board USB-C bridge, onboard TF slot and HDMI monitor; no external CP2102 is required.", True),
    ]

    y_v = 220
    for title, desc, is_pass in verified_items:
        icon = '✅ <b style="color: #15803D;">[VERIFIED]</b>' if is_pass else '⏳ <b style="color: #D97706;">[PENDING BRING-UP]</b>'
        bg_c = "#FFFFFF" if is_pass else "#FFFBEB"
        border_c = "#BBF7D0" if is_pass else "#FDE68A"
        add_node(f"v_item_{y_v}", f"rounded=1;whiteSpace=wrap;fillColor={bg_c};strokeColor={border_c};strokeWidth=1.5;align=left;spacingLeft=10;",
                 f'{icon} <span style="font-size: 12px; color: #0F172A;"><b>{title}</b></span><div style="font-size: 11px; color: #475569; padding-left: 18px;">{desc}</div>',
                 3040, y_v, 620, 58)
        y_v += 64

    # Build full XML
    xml_content = f'''<mxfile host="Electron" modified="2026-10-01T08:58:00.000Z" agent="Antigravity" version="21.6.8" type="device">
  <diagram name="System Architecture" id="riscv_cnn_tang_nano_20k">
    <mxGraphModel dx="2400" dy="1400" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="3800" pageHeight="2000" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
{chr(10).join(cells)}
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>'''
    
    ET.fromstring(xml_content)
    return xml_content

xml = generate_drawio()
out_path = Path(r"h:\University\third-year\Part 1\Embedded System\Big_Project\RISC-V Controlled INT8 Convolution Accelerator.drawio")
out_path.write_text(xml, encoding="utf-8")
print(f"Successfully generated and validated {out_path} ({len(xml)} bytes)")
