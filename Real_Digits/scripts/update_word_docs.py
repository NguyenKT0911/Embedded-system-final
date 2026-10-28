import sys
import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

def update_doc_2_3():
    doc = docx.Document('2.3.Convolutional Neural Networks and Quantization.docx')
    print(f"Loaded 2.3 with {len(doc.paragraphs)} paragraphs.")

    # 1. Update Fully Connected Layer & Argmax in 2.3.4
    # Find paragraph containing "The final classification layer commonly produces one score for each candidate class."
    for p in doc.paragraphs:
        if "The final classification layer commonly produces one score for each candidate class" in p.text:
            p.text = (
                "The final classification layer commonly produces one score (logit) for each candidate class. "
                "In digit recognition systems, such as the 10-class MNIST classifier (classes 0 to 9), the final layer produces a 10-dimensional output vector z = [z0, z1, ..., z9]. "
                "The predicted digit class y_pred is then determined by the Argmax operation, which identifies the index of the candidate class with the maximum activation score: "
                "y_pred = argmax_{c in {0..9}} (z_c). "
                "From an embedded hardware implementation perspective, computing the Argmax over integer logits avoids the computational complexity and numerical precision overhead of exponentiation and Softmax normalization, as the monotonic nature of the exponential function ensures that argmax(Softmax(z)) is mathematically identical to argmax(z)."
            )
            print("Updated 2.3: Fully Connected & Argmax text.")
            break

    # 2. Update Symmetric INT8 Quantization in 2.3.6
    # Find paragraph containing "Using a symmetric representation simplifies the numerical relationship"
    for p in doc.paragraphs:
        if "Using a symmetric representation simplifies the numerical relationship" in p.text:
            p.text = (
                "Using a symmetric representation simplifies the numerical relationship between the real and integer domains because no zero-point subtraction is required during arithmetic multiplication (z = 0). "
                "In standard digital hardware and two's complement arithmetic, signed 8-bit integers (INT8) span the full numerical range of [-128, 127], where the scale factor is calibrated using the maximum absolute tensor magnitude: s = max(|x|) / 127. "
                "The quantization function is consequently defined as q = clip(round(x / s), -128, 127). "
                "This symmetric representation provides full compatibility with native FPGA DSP multipliers and enables bit-exact consistency between PyTorch Float32 simulation, INT8 quantization models, and cycle-accurate RTL execution."
            )
            print("Updated 2.3: Symmetric INT8 Quantization range [-128, 127].")
            break

    # 3. Update Quantized Activations and Weights in 2.3.6 (Input preprocessing & quantization)
    for p in doc.paragraphs:
        if "Quantizing weights and activations from 32-bit floating point to 8-bit integers" in p.text:
            p.text = (
                "For practical vision systems, raw input image pixels in the range [0, 255] are first normalized to the Float32 domain using the dataset mean (mu) and standard deviation (sigma): "
                "x_float = ((img / 255.0) - mu) / sigma (with mu = 0.1307 and sigma = 0.3081 for MNIST standard normalization). "
                "The normalized floating-point tensor is then quantized to signed INT8 using an input scale factor S_in = 0.022216: x_int8 = clip(round(x_float / S_in), -128, 127). "
                "Under this transformation, background pixels (value 0) map cleanly to integer -19, while maximum foreground strokes (value 255) map to +127. "
                "Quantizing both weights and activations from 32-bit floating point to 8-bit signed integers reduces the raw storage footprint and memory transfer bandwidth by a factor of 4x, while enabling efficient parallel integer multiply-accumulate hardware execution."
            )
            print("Updated 2.3: Input preprocessing & INT8 quantization.")
            break

    # 4. Update INT8 Multiplication and INT32 Accumulation (Headroom & Overflow Proof)
    for p in doc.paragraphs:
        if "For N accumulated products in the symmetric range, the worst-case product sum is bounded" in p.text:
            p.text = (
                "For a convolution layer accumulating N product terms, the maximum possible product sum is bounded by N * 127^2 before bias addition. "
                "In the target CNN architecture, the largest convolutional layer (Conv2 with 3x3 kernel over 16 input channels) accumulates N = 3 * 3 * 16 = 144 terms per output value. "
                "The worst-case product sum evaluates to: Max_Sum = 144 * 127^2 = 2,322,576. "
                "Representing this maximum sum requires ceil(log2(2,322,576 + 1)) + 1 = 23 bits (including the sign bit). "
                "A 32-bit signed accumulator provides a maximum representable value of 2^31 - 1 = 2,147,483,647, which provides more than 9 bits of headroom above the worst-case theoretical peak. "
                "Consequently, 32-bit accumulation mathematically guarantees that arithmetic overflow cannot occur under any possible combination of INT8 inputs and weights, eliminating the need for complex intermediate saturation or clipping logic in the hardware datapath."
            )
            print("Updated 2.3: Accumulator headroom & overflow proof.")
            break

    # 5. Update Requantization of Accumulated Results (Fixed-point scaling)
    for p in doc.paragraphs:
        if "Practical integer-only inference implementations can realize this scaling" in p.text:
            p.text = (
                "In practical embedded inference systems, the requantization scaling multiplier M = (s_A * s_W) / s_Y is represented as a fixed-point quantity M ~= M0 * 2^(-n), where M0 is an integer multiplier and n is a right-shift parameter. "
                "The requantization operation can thus be executed using integer multiplication followed by an arithmetic right shift: "
                "Y_q = clip(round((M0 * (ACC_INT32 + Bias_INT32)) >> n), -128, 127). "
                "This fixed-point formulation avoids floating-point division and enables requantization, non-linear activation (ReLU), and spatial pooling to be executed efficiently in integer hardware or bare-metal RISC-V firmware."
            )
            print("Updated 2.3: Requantization fixed-point formulation.")
            break

    doc.save('2.3.Convolutional Neural Networks and Quantization.docx')
    print("Saved 2.3.Convolutional Neural Networks and Quantization.docx successfully.")


def update_doc_2_4():
    doc = docx.Document('2.4.CNN HARDWARE ACCELERATION.docx')
    print(f"\nLoaded 2.4 with {len(doc.paragraphs)} paragraphs.")

    # 1. Update Motivation in 2.4.1 (Heterogeneous SoC & Host-Accelerator Partitioning)
    for p in doc.paragraphs:
        if "A dedicated CNN accelerator addresses these constraints" in p.text:
            p.text = (
                "A dedicated CNN accelerator addresses these constraints by combining high-density arithmetic processing elements with explicitly managed local on-chip storage. "
                "In resource-constrained embedded systems, an effective architectural paradigm is a Heterogeneous Host-Accelerator System-on-Chip (SoC). "
                "In this architecture, a general-purpose processor (such as a 32-bit RISC-V RV32I CPU running bare-metal C firmware) acts as the central system controller, handling external communication (UART, SD-SPI), memory allocation in working BRAM, layer parameter configuration, and irregular/lightweight layers (such as Max Pooling, linear Fully Connected layers, and Argmax classification). "
                "Simultaneously, computationally intensive 2D convolution layers (Conv1, Conv2), which account for over 90% of the total MAC workload, are offloaded to a dedicated parallel hardware accelerator core. "
                "This hardware-software co-design strategy balances compute performance, memory bandwidth, and FPGA logic utilization."
            )
            print("Updated 2.4: Motivation & Heterogeneous SoC co-design.")
            break

    # 2. Update PE Array in 2.4.4 (2D Systolic Array Spatial-Channel Parallelism)
    for p in doc.paragraphs:
        if "Multiple processing elements are organized into an array" in p.text:
            p.text = (
                "Multiple processing elements are organized into a 2D Processing Element (PE) array so that many MAC operations can be executed concurrently. "
                "In a 2D spatial-channel tiled architecture (such as a 4x4 PE array containing 16 parallel MAC units), the two dimensions of the array are mapped to spatial output positions (M = 4 pixels) and output feature channels (N = 4 channels). "
                "During each clock cycle, the array computes 16 simultaneous dot products: each PE row processes a distinct spatial output coordinate while each PE column accumulates a distinct output channel. "
                "This 2D systolic organization maximizes data reuse across adjacent pixels and filter channels, sustaining a peak throughput of 16 INT8xINT8 MAC operations per clock cycle."
            )
            print("Updated 2.4: 2D Systolic 4x4 PE Array spatial-channel parallelism.")
            break

    # 3. Update Memory Hierarchy in 2.4.5 (Multi-tier Embedded Memory Architecture)
    for p in doc.paragraphs:
        if "The memory system determines whether the PE array can sustain its intended throughput" in p.text:
            p.text = (
                "The memory system determines whether the PE array can sustain its intended throughput without stalling. "
                "In an embedded FPGA SoC, memory is organized into a four-tier hierarchy: "
                "(1) External Non-Volatile Storage: MicroSD Card via SPI interface (storing model weights, quantization scale parameters, and offline datasets) and Host PC via UART. "
                "(2) High-Speed On-Chip Working Memory: A 16KB Dual-Port Block RAM (BRAM / Scratchpad) mapped into the CPU memory space, providing fast staging for input activations, feature maps, and layer weights without external bus contention (external storage connects to the CPU/BRAM and never directly to the PE array). "
                "(3) Dedicated Accelerator Buffers: Synchronous on-chip dual-port SRAM buffers (Input Activation Buffer of 3136 bytes and Weight Buffer of 4608 bytes) providing continuous, low-latency operand feeds to the compute core. "
                "(4) Local PE Register Files: Dedicated operand registers and 32-bit accumulators within each MAC unit holding active activations, weights, and stationary partial sums."
            )
            print("Updated 2.4: Multi-tier Embedded Memory Architecture.")
            break

    # 4. Update Dataflow in 2.4.6 (Output-Stationary Tiling Advantage)
    for p in doc.paragraphs:
        if "In an output-stationary dataflow, each PE retains a partial sum" in p.text:
            p.text = (
                "In an Output-Stationary (OS) dataflow, each PE retains its intermediate accumulated partial sum in a local 32-bit register until the full dot product across all input channels and kernel positions (Kh * Kw * Cin) is complete. "
                "This organization is especially advantageous for resource-constrained FPGA accelerators because it completely eliminates intermediate read-modify-write memory traffic to on-chip BRAM. "
                "Activations and filter weights are streamed into the PE array to update the stationary accumulators, and only the final, fully-accumulated INT32 results are written back to the output buffer, minimizing memory bandwidth demand and dynamic switching power."
            )
            print("Updated 2.4: Output-Stationary Dataflow advantage.")
            break

    # 5. Update Hardware Accelerator Interface in 2.4.9 (MMIO Slave Architecture & Register Map)
    for p in doc.paragraphs:
        if "A hardware accelerator requires a defined interface for configuration" in p.text:
            p.text = (
                "A hardware accelerator requires a well-defined interface for configuration, data access, and completion reporting. "
                "In a 32-bit SoC system, the accelerator is integrated as a Memory-Mapped I/O (MMIO) slave peripheral connected to the system interconnect (e.g., base address 0x4000_0000). "
                "The host processor interacts with the accelerator through a standardized MMIO Register File comprising: "
                "(1) Control Register (CTRL at 0x00): START pulse and CLEAR signals. "
                "(2) Status Register (STATUS at 0x04): BUSY, DONE, and CONFIG_OK flags. "
                "(3) Dimension Configuration Registers (0x08 - 0x2C): INPUT_H, INPUT_W, CIN, COUT, KERNEL_SIZE, STRIDE, PADDING, RELU_EN, OUT_H, and OUT_W. "
                "(4) Memory Buffer Ports (0x30 - 0x38): 32-bit packed word streaming for INPUT_DATA (4xINT8/word), WEIGHT_DATA (4xINT8/word), and OUTPUT_DATA (INT32). "
                "(5) Performance & Diagnostic Registers (0x3C - 0x48): Execution CYCLE_COUNT and ERROR_CODE. "
                "Hardware validation logic verifies parameter constraints and asserts CONFIG_OK before execution, ensuring robust and deterministic hardware-software handshaking."
            )
            print("Updated 2.4: MMIO Slave Architecture & Register Map.")
            break

    doc.save('2.4.CNN HARDWARE ACCELERATION.docx')
    print("Saved 2.4.CNN HARDWARE ACCELERATION.docx successfully.")

if __name__ == '__main__':
    update_doc_2_3()
    update_doc_2_4()
