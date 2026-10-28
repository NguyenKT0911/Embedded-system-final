import numpy as np
import os

# =========================
# Load original NPY files
# =========================
x_npy = np.load("conv1_activation_int8.npy").astype(np.int8)
w_npy = np.load("conv1_weight_int8.npy").astype(np.int8)
g_npy = np.load("conv1_golden_conv_int32.npy").astype(np.int32)

# =========================
# Load raw BIN files
# =========================
x_bin = np.fromfile("conv1_input.bin", dtype=np.int8)
w_bin = np.fromfile("conv1_weight.bin", dtype=np.int8)
g_bin = np.fromfile("conv1_golden.bin", dtype=np.int32)

# Flatten original arrays
x_ref = x_npy.flatten()
w_ref = w_npy.flatten()
g_ref = g_npy.flatten()

print("========== FILE SIZE ==========")
print("conv1_input.bin  =", os.path.getsize("conv1_input.bin"), "bytes")
print("conv1_weight.bin =", os.path.getsize("conv1_weight.bin"), "bytes")
print("conv1_golden.bin =", os.path.getsize("conv1_golden.bin"), "bytes")

print()

print("========== INPUT CHECK ==========")
print("NPY count :", x_ref.size)
print("BIN count :", x_bin.size)
print("First 16 NPY:", x_ref[:16])
print("First 16 BIN:", x_bin[:16])

if np.array_equal(x_ref, x_bin):
    print("INPUT : PASS")
else:
    print("INPUT : FAIL")

print()

print("========== WEIGHT CHECK =========")
print("NPY count :", w_ref.size)
print("BIN count :", w_bin.size)
print("First 16 NPY:", w_ref[:16])
print("First 16 BIN:", w_bin[:16])

if np.array_equal(w_ref, w_bin):
    print("WEIGHT : PASS")
else:
    print("WEIGHT : FAIL")

print()

print("========== GOLDEN CHECK =========")
print("NPY count :", g_ref.size)
print("BIN count :", g_bin.size)
print("First 8 NPY:", g_ref[:8])
print("First 8 BIN:", g_bin[:8])

if np.array_equal(g_ref, g_bin):
    print("GOLDEN : PASS")
else:
    print("GOLDEN : FAIL")

print()

if (
    np.array_equal(x_ref, x_bin)
    and np.array_equal(w_ref, w_bin)
    and np.array_equal(g_ref, g_bin)
):
    print("================================")
    print("ALL CONV1 BINARY FILES: PASS")
    print("================================")
else:
    print("SOME FILES FAILED!")