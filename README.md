# RISC-V CNN Accelerator on Tang Nano 20K

Kho lưu trữ chung của nhóm cho đồ án nhận dạng chữ số viết tay trên FPGA **Tang Nano 20K**. Dự án kết hợp bộ xử lý **RV32I**, bộ tăng tốc CNN lượng tử **INT8**, giao tiếp **UART**, lưu trữ **microSD**, hiển thị **HDMI**, công cụ điều khiển trên máy tính và các nội dung triển khai Edge AI trên Linux.

README này giới thiệu nội dung của từng thư mục và hướng dẫn cách sử dụng các phần chính của repository.

## Thành phần chính

- **FPGA SoC:** CPU RV32I, CNN accelerator, UART bootloader, microSD/SPI, HDMI và các khối ngoại vi.
- **CNN pipeline:** huấn luyện mô hình MNIST, lượng tử hóa INT8, xuất trọng số/dữ liệu và kiểm tra kết quả trên FPGA.
- **Host Control Center:** giao diện Python trên Windows để kết nối bo mạch, nạp phần cứng, nạp firmware và chuẩn bị thẻ microSD.
- **RISC-V single-cycle:** thiết kế CPU độc lập tích hợp UART loader để nạp Instruction Memory và chạy các bài kiểm thử.
- **Linux/Edge AI:** tài liệu hệ điều hành, IPC, đa luồng, đồng bộ, tối ưu hiệu năng và demo ONNX Runtime kết nối UART.
- **Tài liệu dự án:** báo cáo đầy đủ, scientific paper, presentation, hình ảnh thực tế và video trình diễn.

## Cấu trúc repository

| Đường dẫn | Nội dung |
|---|---|
| `In_FPGA/` | Thiết kế SoC RISC-V + CNN triển khai trên Tang Nano 20K. |
| `In_FPGA/RISCV_CNN_AI_Accelerator/src/` | RTL Verilog của CPU, CNN accelerator, UART, microSD/SPI, HDMI, top-level và file ràng buộc chân. |
| `In_FPGA/RISCV_CNN_AI_Accelerator/tb/` | Testbench cho firmware, giao tiếp SD/SPI và luồng suy luận. |
| `In_FPGA/RISCV_CNN_AI_Accelerator/firmware_c/` | Firmware C chạy trên RV32I, linker script và công cụ build. |
| `In_FPGA/RISCV_CNN_AI_Accelerator/scripts/` | Script build FPGA và chạy kiểm thử tự động. |
| `In_FPGA/RISCV_CNN_AI_Accelerator/tools/` | GUI điều khiển, UART bootloader, công cụ tạo và ghi ảnh microSD. |
| `In_FPGA/RISCV_CNN_AI_Accelerator/docs/` | Memory map, trạng thái triển khai, hướng dẫn UART bootloader và kiểm thử không cần bo mạch. |
| `In_FPGA/RISCV_CNN_AI_Accelerator/sd_image/` | Mô tả layout model, dữ liệu và golden result trên microSD. |
| `Model Training/` | Notebook, script huấn luyện, checkpoint, tham số lượng tử và dữ liệu xuất cho FPGA. |
| `RISC-V/Code/` | CPU RV32I single-cycle, Instruction/Data Memory, UART RX/TX, UART loader, SoC top và constraint Tang Nano 20K. |
| `RISC-V/Controller/` | Assembly kiểm thử, script build và chương trình nạp Instruction Memory qua UART. |
| `Real_Digits/` | Ảnh chữ số thật ở các giai đoạn raw, processed, INT8, FPGA-ready cùng script và testbench kiểm tra. |
| `Linux/` | Tài liệu Linux, system-level programming, tối ưu hiệu năng/HPC và demo Edge AI phân tán. |
| `assets/` | Sơ đồ kiến trúc, ảnh phần cứng, ảnh GUI, kết quả suy luận và icon ứng dụng. |

## Nội dung thư mục Linux

| Thư mục | Nội dung |
|---|---|
| `Linux/Linux Operating System/` | Tài liệu nền tảng về hệ điều hành Linux. |
| `Linux/System Level/` | IPC, synchronization, multi-thread/multi-core programming và demo tích hợp bằng C. |
| `Linux/Hardware-Aware Performance Optimization & High-Performance Computing (HPC)/` | Tài liệu cache locality, memory pool, compiler/OpenMP, kiến trúc CPU, quản lý bộ nhớ và ví dụ C. |
| `Linux/Microarchitectural Optimization, Memory Hierarchy, and Runtime Profiling/` | Ghi chú tối ưu Deep Learning, quantization, ONNX và runtime. |
| `Linux/Distributed Edge AI Deployment On Linux/` | Demo PyQt5 + C++ sử dụng ONNX Runtime, OpenCV, multithreading và UART. |

Trong demo Edge AI:

- `train_lenet5.py` huấn luyện LeNet-5 trên MNIST và xuất mô hình ONNX.
- `edge_ai_core.cpp` chạy suy luận bằng ONNX Runtime/OpenCV, nhận tín hiệu từ UART và trả kết quả về thiết bị.
- `native_gui.py` là dashboard PyQt5 để chọn ảnh, khởi chạy AI core và hiển thị kết quả/thời gian xử lý.
- `images/` và `models/` chứa dữ liệu ảnh cùng mô hình phục vụ demo.

> Demo Linux có bộ phụ thuộc riêng như PyQt5, PyTorch/torchvision, OpenCV C++ và ONNX Runtime C++. Trước khi chạy, cần kiểm tra lại cổng UART `/dev/ttyUSB0` và thống nhất tên mô hình ONNX được tạo với tên mô hình mà `edge_ai_core.cpp` sử dụng.

## Các file ở thư mục gốc

| File | Nội dung / cách dùng |
|---|---|
| `AI_FPGA_Control.pyw` | Điểm khởi chạy Control Center trên Windows; file này gọi GUI tại `In_FPGA/RISCV_CNN_AI_Accelerator/tools/ai_fpga_gui.py`. |
| `Control_Center.lnk` | Shortcut mở nhanh Control Center. Nếu shortcut không đúng đường dẫn trên máy mới, chạy trực tiếp `AI_FPGA_Control.pyw`. |
| `requirements.txt` | Thư viện Python của Control Center: Pillow và PySerial. |
| `Final_Project.pdf` | Báo cáo kỹ thuật đầy đủ dạng PDF. |
| `Final_Project.docx` | Bản Word có thể chỉnh sửa của báo cáo. |
| `RISC_V_INT8_CNN_FPGA_Scientific_Paper.pdf` | Bài báo khoa học tổng hợp kiến trúc RISC-V, CNN INT8 và kết quả triển khai FPGA. |
| `Nhóm 07.pptx` | Presentation tổng kết dự án. |
| `Tìm hiểu về process_AI.md` | Ghi chú mô tả quy trình xử lý AI của dự án. |
| `.gitignore` | Loại trừ file build, file tạm và dữ liệu không cần đưa lên repository. |

## Yêu cầu

### Phần cứng

- Tang Nano 20K.
- Cáp USB hỗ trợ dữ liệu.
- Thẻ microSD.
- Màn hình/cáp HDMI nếu sử dụng phần hiển thị.
- Máy tính Windows cho Control Center; môi trường Linux cho các nội dung trong `Linux/`.

### Phần mềm chính

- Python 3.10 hoặc mới hơn.
- Gowin EDA để tổng hợp và nạp thiết kế FPGA.
- RISC-V GNU toolchain cho firmware và chương trình RV32I.
- PowerShell trên Windows để chạy các script build/test.
- Pillow và PySerial cho Control Center.

## Khởi chạy Control Center

Từ thư mục gốc của repository:

```powershell
python -m pip install -r requirements.txt
python .\AI_FPGA_Control.pyw
```

Có thể mở `Control_Center.lnk` trên máy đã cấu hình đúng shortcut. Khi sao chép repository sang máy hoặc ổ đĩa khác, nên chạy file Python trực tiếp nếu shortcut không hoạt động.

## Quy trình sử dụng với bo mạch

1. Kết nối Tang Nano 20K với máy tính bằng cáp USB.
2. Gắn thẻ microSD và kết nối màn hình HDMI nếu cần.
3. Mở `AI_FPGA_Control.pyw`.
4. Chọn đúng cổng COM rồi nhấn **Connect**.
5. Nhấn **Program Hardware (.fs)** để chọn và nạp bitstream.
6. Nhấn **Initialize microSD** để chuẩn bị model và bộ dữ liệu trên thẻ.
7. Nhấn **Load AI Runtime** để nạp firmware qua UART.
8. Thực hiện suy luận; theo dõi log trên Control Center và kết quả trên HDMI.

> **Cảnh báo:** thao tác **Initialize microSD** có thể ghi đè dữ liệu trên thẻ. Hãy kiểm tra chính xác thiết bị lưu trữ trước khi xác nhận.

## Build và kiểm thử FPGA SoC

Mở PowerShell tại thư mục dự án rồi chuyển tới thư mục thiết kế:

```powershell
cd ".\In_FPGA\RISCV_CNN_AI_Accelerator"
```

Build firmware C:

```powershell
.\firmware_c\build_firmware.ps1
```

Build bitstream FPGA:

```powershell
.\scripts\build_fpga.ps1
```

Chạy bộ kiểm thử nhanh:

```powershell
.\scripts\run_c_firmware_tests.ps1 -Quick
```

Chạy toàn bộ kiểm thử:

```powershell
.\scripts\run_c_firmware_tests.ps1
```

Xem thêm hướng dẫn và trạng thái triển khai trong `In_FPGA/RISCV_CNN_AI_Accelerator/docs/`.

## Sử dụng RISC-V single-cycle qua UART

Các file RTL nằm trong `RISC-V/Code/`; chương trình nạp và kiểm thử nằm trong `RISC-V/Controller/`.

1. Chỉnh sửa chương trình trong `RISC-V/Controller/program.S`.
2. Cài RISC-V GNU toolchain có các lệnh `riscv-none-elf-gcc`, `riscv-none-elf-objdump` và `riscv-none-elf-objcopy`.
3. Build chương trình:

   ```powershell
   cd ".\RISC-V\Controller"
   python .\build.py
   ```

4. Mở `run_program_test.py` và sửa biến `PORT` thành cổng COM của bo mạch; giá trị mặc định hiện tại là `COM8`.
5. Nạp `program.bin` vào Instruction Memory và đọc kết quả:

   ```powershell
   python -m pip install pyserial
   python .\run_program_test.py
   ```

Script sử dụng UART `115200` baud, giới hạn chương trình ở 1 KiB Instruction Memory và chờ kết quả của sáu nhóm kiểm thử RV32I. `build.py` có tham chiếu tới `bin2hex.ps1`; cần bổ sung file này trong `RISC-V/Controller/` nếu muốn tạo `program.hex`.

## Model và dữ liệu chữ số

- Dùng `Model Training/MNIST_AI_Model_Upgrade_Colab.ipynb` hoặc các script tương ứng để huấn luyện/kiểm tra mô hình.
- Các file trong `Model Training/FPGA_UART_export/` chứa model, trọng số, activation INT8, golden data và manifest xuất cho FPGA.
- `Real_Digits/raw/` chứa ảnh đầu vào ban đầu.
- Các script trong `Real_Digits/scripts/` thực hiện tiền xử lý, lượng tử hóa, xuất dữ liệu và kiểm thử.
- `Real_Digits/processed/`, `int8_quantized/` và `fpga_ready_data/` chứa kết quả ở từng giai đoạn.
- `Real_Digits/simulation/` chứa dữ liệu HEX và testbench phục vụ đối chiếu mô phỏng.

Khi thay đổi mô hình hoặc cách lượng tử hóa, cần tạo lại dữ liệu FPGA/golden result tương ứng trước khi kiểm thử phần cứng.

## Tài liệu và video

- [Báo cáo đầy đủ – PDF](Final_Project.pdf)
- [Bản chỉnh sửa báo cáo – DOCX](Final_Project.docx)
- [Scientific paper – RISC-V INT8 CNN FPGA](RISC_V_INT8_CNN_FPGA_Scientific_Paper.pdf)
- [Presentation – Nhóm 07](Nh%C3%B3m%2007.pptx)
- [Ghi chú quy trình AI](T%C3%ACm%20hi%E1%BB%83u%20v%E1%BB%81%20process_AI.md)
- [Video hướng dẫn và trình diễn trên YouTube](https://www.youtube.com/playlist?list=PLU8j17gnRm0I)

## Đóng góp nội dung

Repository được dùng chung cho toàn nhóm. Khi bổ sung mã nguồn hoặc tài liệu, hãy đặt file vào đúng thư mục chức năng, cập nhật README nếu cấu trúc thay đổi và tránh commit các file build/tạm không cần thiết.
