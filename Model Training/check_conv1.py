import numpy as np

x = np.load("conv1_activation_int8.npy")
w = np.load("conv1_weight_int8.npy")
g = np.load("conv1_golden_conv_int32.npy")

print("===== CONV1 INPUT =====")
print("shape =", x.shape)
print("dtype =", x.dtype)
print("size  =", x.size)
print("min   =", x.min())
print("max   =", x.max())

print()

print("===== CONV1 WEIGHT =====")
print("shape =", w.shape)
print("dtype =", w.dtype)
print("size  =", w.size)
print("min   =", w.min())
print("max   =", w.max())

print()

print("===== CONV1 GOLDEN =====")
print("shape =", g.shape)
print("dtype =", g.dtype)
print("size  =", g.size)
print("min   =", g.min())
print("max   =", g.max())