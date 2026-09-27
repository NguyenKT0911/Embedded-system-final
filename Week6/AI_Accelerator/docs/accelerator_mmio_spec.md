# AI Accelerator MMIO Interface Specification
Version: 0.1

## Bus Interface

- Address width: 32 bits
- Data width: 32 bits
- Access mechanism: Memory-Mapped I/O
- Accelerator base address: `0x4000_0000`
- Activation format: signed INT8
- Weight format: signed INT8
- Accumulator/output format: signed INT32
- MMIO accesses are 32-bit and 4-byte aligned
- All register offsets are byte offsets relative to `ACC_BASE`

The surrounding RISC-V SoC also defines a write-only result stream sink at
`0x4000_1000`. This address is outside the accelerator register block. A
32-bit store uses a ready/valid handshake and stalls the CPU while the consumer
is not ready.

## Register Map

| Offset | Register       | R/W | Description |
| -----: | -------------- | :-: | ----------- |
| `0x00` | `CTRL`         |  W  | START, CLEAR |
| `0x04` | `STATUS`       |  R  | BUSY, DONE, ERROR |
| `0x08` | `INPUT_H`      | R/W | Input feature-map height |
| `0x0C` | `INPUT_W`      | R/W | Input feature-map width |
| `0x10` | `CIN`          | R/W | Number of input channels |
| `0x14` | `COUT`         | R/W | Number of output channels |
| `0x18` | `KERNEL_SIZE`  | R/W | Convolution kernel size |
| `0x1C` | `STRIDE`       | R/W | Convolution stride |
| `0x20` | `PADDING`      | R/W | Zero-padding size |
| `0x24` | `RELU_EN`      | R/W | Enable or disable ReLU |
| `0x28` | `OUT_H`        |  R  | Calculated output height |
| `0x2C` | `OUT_W`        |  R  | Calculated output width |
| `0x30` | `INPUT_DATA`   |  W  | Transfer 4 × INT8 activations |
| `0x34` | `WEIGHT_DATA`  |  W  | Transfer 4 × INT8 weights |
| `0x38` | `OUTPUT_DATA`  |  R  | Read 1 × INT32 output |
| `0x3C` | `INPUT_COUNT`  |  R  | Number of INT8 activations received |
| `0x40` | `WEIGHT_COUNT` |  R  | Number of INT8 weights received |
| `0x44` | `OUTPUT_COUNT` |  R  | Number of valid outputs generated |
| `0x48` | `ERROR_CODE`   |  R  | Error code |

## CTRL Register

Offset: `0x00`  
Access: Write

The CTRL register is used to control the operation of the AI accelerator.

| Bit | Name | Description |
|---|---|---|
| 0 | START | Start the convolution operation |
| 1 | CLEAR | Clear DONE, ERROR, and internal data counters |
| 31:2 | RESERVED | Reserved, write as 0 |

### START

Writing `1` to the START bit requests the accelerator to begin processing.

The START command is treated as a one-cycle internal pulse. The software does not need to keep this bit asserted.

### CLEAR

Writing `1` to the CLEAR bit clears the accelerator status and prepares the accelerator for a new operation.

CLEAR resets:

- DONE
- ERROR
- ERROR_CODE
- INPUT_COUNT
- WEIGHT_COUNT
- OUTPUT_COUNT

## STATUS Register

Offset: `0x04`  
Access: Read

The STATUS register reports the current operating state of the AI accelerator.

| Bit | Name | Description |
|---|---|---|
| 0 | BUSY | Accelerator is currently processing |
| 1 | DONE | Convolution operation has completed |
| 2 | ERROR | An error has occurred |
| 31:3 | RESERVED | Reserved, reads as 0 |

### BUSY

BUSY is set to `1` while the accelerator is performing a convolution operation.

When processing is complete, BUSY returns to `0`.

### DONE

DONE is set to `1` when the convolution operation has completed successfully.

DONE remains asserted until the software issues a CLEAR command through the CTRL register.

### ERROR

ERROR is set to `1` when the accelerator detects an invalid configuration or another processing error.

Additional information about the error can be obtained from the ERROR_CODE register.

ERROR remains asserted until a CLEAR command is issued.

## Configuration Registers

The configuration registers define the convolution parameters used by the accelerator.

Configuration registers should be written before issuing the START command. Software should not modify these registers while BUSY is `1`.

### INPUT_H Register

Offset: `0x08`  
Access: Read/Write

Specifies the height of the input feature map.

| Bits | Name | Description |
|---|---|---|
| 15:0 | INPUT_H | Input feature-map height |
| 31:16 | RESERVED | Reserved, write as 0 |

For the current CNN:

- Conv1: INPUT_H = 28
- Conv2: INPUT_H = 14


### INPUT_W Register

Offset: `0x0C`  
Access: Read/Write

Specifies the width of the input feature map.

| Bits | Name | Description |
|---|---|---|
| 15:0 | INPUT_W | Input feature-map width |
| 31:16 | RESERVED | Reserved, write as 0 |

For the current CNN:

- Conv1: INPUT_W = 28
- Conv2: INPUT_W = 14


### CIN Register

Offset: `0x10`  
Access: Read/Write

Specifies the number of input channels.

| Bits | Name | Description |
|---|---|---|
| 15:0 | CIN | Number of input channels |
| 31:16 | RESERVED | Reserved, write as 0 |

For the current CNN:

- Conv1: CIN = 1
- Conv2: CIN = 16


### COUT Register

Offset: `0x14`  
Access: Read/Write

Specifies the number of output channels.

| Bits | Name | Description |
|---|---|---|
| 15:0 | COUT | Number of output channels |
| 31:16 | RESERVED | Reserved, write as 0 |

For the current CNN:

- Conv1: COUT = 16
- Conv2: COUT = 32


### KERNEL_SIZE Register

Offset: `0x18`  
Access: Read/Write

Specifies the convolution kernel size.

| Bits | Name | Description |
|---|---|---|
| 7:0 | KERNEL_SIZE | Convolution kernel size |
| 31:8 | RESERVED | Reserved, write as 0 |

Version 0.1 supports:

KERNEL_SIZE = 3


### STRIDE Register

Offset: `0x1C`  
Access: Read/Write

Specifies the convolution stride.

| Bits | Name | Description |
|---|---|---|
| 7:0 | STRIDE | Convolution stride |
| 31:8 | RESERVED | Reserved, write as 0 |

Version 0.1 supports:

STRIDE = 1


### PADDING Register

Offset: `0x20`  
Access: Read/Write

Specifies the amount of zero padding applied around the input feature map.

| Bits | Name | Description |
|---|---|---|
| 7:0 | PADDING | Zero-padding size |
| 31:8 | RESERVED | Reserved, write as 0 |

Version 0.1 supports:

PADDING = 1


### RELU_EN Register

Offset: `0x24`  
Access: Read/Write

Controls whether the ReLU activation function is applied to the convolution result.

| Bit | Name | Description |
|---|---|---|
| 0 | RELU_EN | `1`: enable ReLU, `0`: disable ReLU |
| 31:1 | RESERVED | Reserved, write as 0 |


### OUT_H Register

Offset: `0x28`  
Access: Read

Reports the calculated output feature-map height.

The output height is calculated from INPUT_H, KERNEL_SIZE, STRIDE, and PADDING.


### OUT_W Register

Offset: `0x2C`  
Access: Read

Reports the calculated output feature-map width.

The output width is calculated from INPUT_W, KERNEL_SIZE, STRIDE, and PADDING.

## Input Data Interface

### INPUT_DATA Register

Offset: `0x30`  
Access: Write

The INPUT_DATA register is used to transfer signed INT8 input activations from the RISC-V processor to the accelerator input buffer.

Because the MMIO data bus is 32 bits wide, each write transfers four signed INT8 activation values.

| Bits | Data |
|---|---|
| 7:0 | Activation 0 |
| 15:8 | Activation 1 |
| 23:16 | Activation 2 |
| 31:24 | Activation 3 |

Each 8-bit field is interpreted as a signed two's-complement INT8 value.

When a 32-bit word is written to INPUT_DATA, the accelerator stores the four activation values sequentially into the internal input buffer.

The internal input write pointer is automatically incremented by four after each successful write.

INPUT_DATA should only be written while BUSY is `0`.

A CLEAR command resets the input write pointer and INPUT_COUNT to zero.

### Input Data Packing

The input activations are packed into a 32-bit MMIO word as follows:

bits [7:0]   = input[n]
bits [15:8]  = input[n+1]
bits [23:16] = input[n+2]
bits [31:24] = input[n+3]

After the write operation:

input_buffer[n]   = input[n]
input_buffer[n+1] = input[n+1]
input_buffer[n+2] = input[n+2]
input_buffer[n+3] = input[n+3]

The INPUT_COUNT register counts the number of INT8 activation values successfully received by the accelerator. Therefore, INPUT_COUNT increases by four after each 32-bit INPUT_DATA write.

### INPUT_COUNT Register

Offset: `0x3C`  
Access: Read

The INPUT_COUNT register reports the number of signed INT8 activation values that have been successfully written into the accelerator input buffer.

INPUT_COUNT is reset to zero by the CLEAR command.

Because each INPUT_DATA write transfers four INT8 values, INPUT_COUNT normally increases by four for every successful 32-bit write.

### Input Activation Order

Input activations are stored in channel-major order with tensor layout:

`[C][H][W]`

The flattened index is:

`index = (c * INPUT_H + h) * INPUT_W + w`

Therefore, the width index changes first, followed by height and then channel.

## Weight Data Interface

### WEIGHT_DATA Register

Offset: `0x34`  
Access: Write

The WEIGHT_DATA register is used to transfer signed INT8 convolution weights from the RISC-V processor to the accelerator weight buffer.

Because the MMIO data bus is 32 bits wide, each write transfers four signed INT8 weight values.

| Bits | Data |
|---|---|
| 7:0 | Weight 0 |
| 15:8 | Weight 1 |
| 23:16 | Weight 2 |
| 31:24 | Weight 3 |

Each 8-bit field is interpreted as a signed two's-complement INT8 value.

When a 32-bit word is written to WEIGHT_DATA, the accelerator stores the four weight values sequentially into the internal weight buffer.

The internal weight write pointer is automatically incremented by four after each successful write.

WEIGHT_DATA should only be written while BUSY is `0`.

A CLEAR command resets the weight write pointer and WEIGHT_COUNT to zero.

### Weight Data Packing

The convolution weights are packed into a 32-bit MMIO word as follows:

bits [7:0]   = weight[n]
bits [15:8]  = weight[n+1]
bits [23:16] = weight[n+2]
bits [31:24] = weight[n+3]

After the write operation:

weight_buffer[n]   = weight[n]
weight_buffer[n+1] = weight[n+1]
weight_buffer[n+2] = weight[n+2]
weight_buffer[n+3] = weight[n+3]

The WEIGHT_COUNT register counts the number of INT8 weight values successfully received by the accelerator. Therefore, WEIGHT_COUNT increases by four after each 32-bit WEIGHT_DATA write.

### WEIGHT_COUNT Register

Offset: `0x40`  
Access: Read

The WEIGHT_COUNT register reports the number of signed INT8 weight values that have been successfully written into the accelerator weight buffer.

WEIGHT_COUNT is reset to zero by the CLEAR command.

Because each WEIGHT_DATA write transfers four INT8 values, WEIGHT_COUNT normally increases by four for every successful 32-bit write.

### Weight Order

Convolution weights are stored using the tensor layout:

`[COUT][CIN][KH][KW]`

The flattened weight index is:

`index = (((oc * CIN + ic) * KERNEL_SIZE + kh) * KERNEL_SIZE + kw)`

Therefore, the kernel-width index changes first, followed by kernel height, input channel, and output channel.

## Output Data Interface

### OUTPUT_DATA Register

Offset: `0x38`  
Access: Read

The OUTPUT_DATA register is used by the RISC-V processor to read signed INT32 convolution results from the accelerator output buffer.

Because the MMIO data bus is 32 bits wide and each output value is signed INT32, each read transfers exactly one output value.

When OUTPUT_DATA is read, the accelerator returns the current output value from the internal output buffer.

After a successful read, the internal output read pointer is automatically incremented by one.

OUTPUT_DATA should only be read after DONE is `1`.

A CLEAR command resets the output read pointer and OUTPUT_COUNT to zero.

### OUTPUT_COUNT Register

Offset: `0x44`  
Access: Read

The OUTPUT_COUNT register reports the number of INT32 output values generated by the accelerator.

OUTPUT_COUNT is reset to zero by the CLEAR command.

After the convolution operation is complete, OUTPUT_COUNT indicates the total number of valid output values available in the output buffer.

### Output Data Order

Convolution outputs are stored using the tensor layout:

`[COUT][OUT_H][OUT_W]`

The flattened output index is:

`index = (oc * OUT_H + oh) * OUT_W + ow`

Therefore, the output-width index changes first, followed by output height and then output channel.

## Error Handling

The accelerator reports invalid operating conditions through the ERROR bit in the STATUS register and the ERROR_CODE register.

When an error is detected:

- ERROR is set to `1`
- BUSY is cleared to `0`
- DONE remains `0`
- ERROR_CODE stores the corresponding error value

ERROR and ERROR_CODE remain valid until a CLEAR command is issued.

### ERROR_CODE Register

Offset: `0x48`  
Access: Read

The ERROR_CODE register provides additional information about the error detected by the accelerator.

| Value | Name | Description |
|---|---|---|
| `0x00` | NO_ERROR | No error |
| `0x01` | INVALID_CONFIG | Invalid convolution configuration |
| `0x02` | INPUT_COUNT_ERROR | Incorrect number of input activation values |
| `0x03` | WEIGHT_COUNT_ERROR | Incorrect number of weight values |
| `0x04` | BUSY_ACCESS_ERROR | Invalid access while the accelerator is busy |
| `0x05` | UNSUPPORTED_CONFIG | Unsupported kernel, stride, or padding configuration |

### Configuration Validation

Before starting a convolution operation, the accelerator validates the configuration registers.

For version 0.1, the following configuration is supported:

- KERNEL_SIZE = 3
- STRIDE = 1
- PADDING = 1
- INPUT_H > 0
- INPUT_W > 0
- CIN > 0
- COUT > 0

If the configuration is not supported, the accelerator sets ERROR and updates ERROR_CODE.

### Buffer Capacity

Version 0.1 is sized for the current two-convolution CNN and supports up to:

- Maximum input values: 3,136 signed INT8 values
- Maximum weight values: 4,608 signed INT8 values
- Maximum output values: 12,544 signed INT32 values

Before accepting START, the accelerator must verify that the configured tensor sizes do not exceed these limits.

The required counts are derived from:

`EXPECTED_INPUT_COUNT = CIN * INPUT_H * INPUT_W`

`EXPECTED_WEIGHT_COUNT = COUT * CIN * KERNEL_SIZE * KERNEL_SIZE`

`EXPECTED_OUTPUT_COUNT = COUT * OUT_H * OUT_W`

A configuration that exceeds the supported capacity is considered invalid.

### Data Alignment

Version 0.1 requires the total number of input activation values and weight values to be multiples of four.

This restriction allows each 32-bit INPUT_DATA or WEIGHT_DATA write to contain exactly four valid INT8 values.

The current Conv1 and Conv2 configurations satisfy this requirement.

### Current CNN Operating Profiles

For the current CNN, the expected configurations are:

| Parameter | Conv1 | Conv2 |
|---|---:|---:|
| INPUT_H | 28 | 14 |
| INPUT_W | 28 | 14 |
| CIN | 1 | 16 |
| COUT | 16 | 32 |
| KERNEL_SIZE | 3 | 3 |
| STRIDE | 1 | 1 |
| PADDING | 1 | 1 |
| OUT_H | 28 | 14 |
| OUT_W | 28 | 14 |
| INPUT_COUNT | 784 | 3,136 |
| WEIGHT_COUNT | 144 | 4,608 |
| OUTPUT_COUNT | 12,544 | 6,272 |

### Input and Weight Count Validation

Before accepting the START command, the accelerator checks whether the expected number of input activations and weights has been received.

The expected number of input activations is:

`EXPECTED_INPUT_COUNT = CIN * INPUT_H * INPUT_W`

The expected number of weights is:

`EXPECTED_WEIGHT_COUNT = COUT * CIN * KERNEL_SIZE * KERNEL_SIZE`

The START command is accepted only when:

`INPUT_COUNT == EXPECTED_INPUT_COUNT`

and

`WEIGHT_COUNT == EXPECTED_WEIGHT_COUNT`

Otherwise, the accelerator reports an error and does not begin processing.


## Access Rules

The following access rules apply to version 0.1:

- Configuration registers must be written only while BUSY is `0`.
- INPUT_DATA and WEIGHT_DATA must be written only while BUSY is `0`.
- START must not be issued while BUSY is `1`.
- OUTPUT_DATA should be read only after DONE is `1`.
- CLEAR may be used after a completed operation or error to prepare the accelerator for the next operation.
- Reserved bits must be written as `0` and are read as `0`.

If software performs an invalid access while BUSY is `1`, the accelerator reports `BUSY_ACCESS_ERROR`.

## Complete Transaction Sequence

A convolution operation is performed using the following sequence:

1. Software issues CLEAR through the CTRL register.
2. Software writes INPUT_H, INPUT_W, CIN, COUT, KERNEL_SIZE, STRIDE, PADDING, and RELU_EN.
3. Software writes all input activations through INPUT_DATA.
4. Software writes all convolution weights through WEIGHT_DATA.
5. Software may read INPUT_COUNT and WEIGHT_COUNT to verify that all required values were received.
6. Software issues START through the CTRL register.
7. The accelerator validates the configuration and data counts.
8. If validation succeeds, BUSY is set to `1` and convolution processing begins.
9. Software polls STATUS until either DONE or ERROR becomes `1`.
10. When processing completes successfully, BUSY becomes `0`, DONE becomes `1`, and OUTPUT_COUNT reports the number of valid outputs.
11. Software reads convolution results sequentially through OUTPUT_DATA.
12. Software issues CLEAR before configuring the next convolution operation.

The logical transaction flow is:

`CLEAR -> CONFIG -> INPUT_DATA -> WEIGHT_DATA -> START -> BUSY -> DONE -> OUTPUT_DATA -> CLEAR`

If an error is detected:

`START/access -> ERROR -> read ERROR_CODE -> CLEAR`

## RISC-V Integration Notes

The RISC-V implementation may be single-cycle, multi-cycle, or pipelined. The accelerator interface is independent of the internal CPU microarchitecture.

The RISC-V side must provide:

- 32-bit MMIO address generation
- 32-bit load/store data transfers
- Address decoding for the accelerator MMIO region
- Write access to control, configuration, input, and weight registers
- Read access to status, counter, error, and output registers

The final accelerator base address is intentionally left as `TBD` until the RISC-V memory map and address decoder are finalized.

The processor's 256-byte local memory is separate from the accelerator MMIO register space. Large activation, weight, and output tensors are therefore handled through the accelerator data interfaces rather than being stored entirely in the processor's local data memory.

## Version 0.1 Summary

Version 0.1 defines a 32-bit MMIO interface for a signed INT8 convolution accelerator with signed INT32 accumulation/output.

The interface supports the current Conv1 and Conv2 workloads of the MNIST CNN and defines:

- Control and status signaling
- Convolution configuration
- Packed INT8 activation transfer
- Packed INT8 weight transfer
- Sequential INT32 output reads
- Tensor ordering conventions
- Data counters
- Configuration and capacity validation
- Error reporting
- A complete software-to-accelerator transaction sequence

The accelerator base address and the low-level bus wiring remain to be finalized during integration with the RISC-V processor.
