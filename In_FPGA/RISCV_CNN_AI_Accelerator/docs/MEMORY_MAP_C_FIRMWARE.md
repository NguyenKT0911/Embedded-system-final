# Memory map da chot cho firmware C

| Vung | Dia chi | Kich thuoc | Quyen | Muc dich |
|---|---:|---:|---|---|
| IMEM CPU | 0x0000_0000 | 8 KiB | execute | Firmware RV32I C |
| Result/HDMI handoff | 0x1000_0000 | 16 B | RW | prediction, sample ID, valid |
| UART | 0x2000_0000 | 16 B | RW | log, lenh dieu khien, firmware UART |
| SD SPI | 0x3000_0000 | 16 B | RW | khe TF onboard |
| CNN accelerator | 0x4000_0000 | 76 B | RW | config, input, weight, output |
| Result stream | 0x4000_1000 | 4 B | W | stream ket qua cho host |
| DMEM alias cu | 0x0000_0000 | 8 KiB | RW | tuong thich assembly |
| DMEM C | 0x8000_0000 | 8 KiB | RW | data, bss, workspace, stack |

IMEM va DMEM la hai bo nho vat ly rieng (Harvard). Firmware C luon dung DMEM
tai 0x8000_0000. Build script tach ELF thanh hai file MEM HEX; host gui chung qua
UART BL616 tích hợp cho Loader ghi vào BSRAM. RTL không còn INIT_FILE/$readmemh.
UART va CPU dung chung mot cong ghi DMEM qua mux; sau RUN, CPU chiem quyen truy cap.

UI còn có `0x5000_000C` (HDMI lock) và `0x5000_0010` (ghi 1 để quay lại
Loader). Dataset Manager dùng thanh ghi reload để ứng dụng tự nạp lại AI Runtime.

## Thanh ghi SD SPI

| Offset | Ten | Y nghia |
|---:|---|---|
| 0x00 | CONTROL | bit 0 = CS_N |
| 0x04 | STATUS | bit 0 = busy, bit 1 = RX valid |
| 0x08 | DATA | ghi mot byte; doc byte nhan va xoa valid |
| 0x0C | DIVIDER | SCLK = clk / (2*(divider+1)) |

