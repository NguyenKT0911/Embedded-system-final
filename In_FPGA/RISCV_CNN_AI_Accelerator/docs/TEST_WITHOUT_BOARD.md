# Kiểm tra khi chưa có board

## Quick regression

```powershell
cd In_FPGA\RISCV_CNN_AI_Accelerator
.\scripts\run_c_firmware_tests.ps1 -Quick
```

Quick regression build cả AI Runtime và Dataset Manager, kiểm tra mã RV32I-only,
ảnh SD RCN1 v3, SD SPI MMIO và CPU khởi động qua packet UART CRC32.

## Full regression

```powershell
.\scripts\run_c_firmware_tests.ps1
```

Full regression dùng mô hình SDHC SPI đọc `model_sd.hex`, chạy Conv1/Conv2 trên
RTL accelerator, Pool/Requant/FC/Argmax trong firmware C và chỉ PASS khi Result
MMIO công bố đúng prediction/confidence sau khi testbench tạo nhấn S1 ảo.

## Build FPGA

```powershell
.\scripts\build_fpga.ps1
```

Build Gowin phải hoàn tất synthesis, place-and-route, timing và tạo
`impl/pnr/TangNano20K_RISCV_CNN.fs`. Báo cáo hiện tại dùng đủ 46/46 BSRAM và
22/24 DSP nên IMEM/DMEM được giữ ở 8 KiB mỗi vùng.

Không cần board cho ba bước trên. Trên board thật, ghi phần cứng vào Flash một
lần, ghi `model_sd.img` vào microSD, sau đó dùng UART BL616 tích hợp để nạp
firmware sau mỗi lần cấp nguồn. Không dùng CP2102 rời.
