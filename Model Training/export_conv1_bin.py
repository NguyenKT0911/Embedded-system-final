import numpy as np

# Load data
x = np.load("conv1_activation_int8.npy")
w = np.load("conv1_weight_int8.npy")
g = np.load("conv1_golden_conv_int32.npy")

# Export raw binary
x.astype(np.int8).tofile("conv1_input.bin")
w.astype(np.int8).tofile("conv1_weight.bin")
g.astype(np.int32).tofile("conv1_golden.bin")

print("Export completed!")

print("conv1_input.bin  :", x.size, "bytes")
print("conv1_weight.bin :", w.size, "bytes")
print("conv1_golden.bin :", g.size * 4, "bytes")