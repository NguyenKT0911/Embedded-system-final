# RISC-V CNN Accelerator on Tang Nano 20K

Kho lưu trữ chung của nhóm cho đồ án nhận dạng chữ số viết tay trên FPGA Tang
Nano 20K. README này tập trung vào cấu trúc thư mục, nội dung của từng nhóm file
và cách sử dụng dự án.

## Cấu trúc thư mục

| Thư mục | Nội dung |
|---|---|
| `In_FPGA/` | Thiết kế FPGA hoàn chỉnh, mã Verilog, testbench, firmware RISC-V và các script build. |
| `In_FPGA/RISCV_CNN_AI_Accelerator/src/` | RTL của CPU RV32I, bộ tăng tốc CNN, UART, microSD, HDMI và file ràng buộc chân FPGA. |
| `In_FPGA/RISCV_CNN_AI_Accelerator/tb/` | Testbench dùng để mô phỏng và kiểm tra từng khối cũng như toàn hệ thống. |
| `In_FPGA/RISCV_CNN_AI_Accelerator/firmware_c/` | Firmware C chạy trên CPU RV32I và các script biên dịch firmware. |
| `In_FPGA/RISCV_CNN_AI_Accelerator/tools/` | Công cụ tạo ảnh microSD, nạp firmware qua UART và các tiện ích hỗ trợ. |
| `In_FPGA/RISCV_CNN_AI_Accelerator/scripts/` | Script build FPGA và chạy các bài kiểm thử tự động. |
| `Model Training/` | Notebook, script huấn luyện, trọng số, tham số lượng tử INT8 và dữ liệu xuất cho FPGA. |
| `RISC-V/` | Thiết kế RISC-V single-cycle độc lập và công cụ điều khiển qua UART. |
| `RISC-V/Code/` | Mã Verilog của CPU RV32I single-cycle tích hợp UART, gồm ALU, control unit, datapath, register file, Instruction/Data Memory, UART RX/TX, UART loader, SoC top và file ràng buộc Tang Nano 20K. |
| `RISC-V/Controller/` | Chương trình Assembly và các script Python để build chương trình thử nghiệm, nạp `program.bin` vào Instruction Memory qua UART và đọc kết quả kiểm thử. |
| `Real_Digits/` | Ảnh chữ số thật, dữ liệu đã xử lý, dữ liệu INT8 và các file mô phỏng kiểm thử. |
| `assets/` | Sơ đồ kiến trúc, ảnh phần cứng, giao diện điều khiển và kết quả trình diễn. |

## Các file chính

| File | Nội dung / cách dùng |
|---|---|
| `AI_FPGA_Control.pyw` | Chương trình điều khiển chính trên Windows. Dùng để kết nối cổng COM, nạp bitstream, khởi tạo microSD và nạp firmware. |
| `Control_Center.lnk` | Shortcut mở nhanh chương trình điều khiển. Nếu shortcut không hoạt động, chạy trực tiếp `AI_FPGA_Control.pyw`. |
| `requirements.txt` | Danh sách thư viện Python cần cho chương trình điều khiển. |
| `Final_Project.pdf` | Báo cáo kỹ thuật đầy đủ của đồ án. |
| `Final_Project.docx` | Bản Word có thể chỉnh sửa của báo cáo đầy đủ. |
| `Nhóm 7.pptx` | Presentation tiếng Anh tổng kết kiến trúc, quy trình triển khai, kiểm thử và kết quả của dự án. |
| `Tìm hiểu về process_AI.md` | Ghi chú về quy trình xử lý AI trong dự án. |
| `.gitignore` | Loại trừ file build, file tạm và dữ liệu lớn không cần đưa lên GitHub. |

## Yêu cầu

### Phần cứng

- Tang Nano 20K.
- Cáp USB kết nối bo mạch với máy tính.
- Thẻ microSD.
- Màn hình HDMI.

### Phần mềm

- Windows.
- Python 3.10 trở lên.
- Gowin EDA nếu cần build lại bitstream FPGA.
- ModelSim hoặc QuestaSim nếu cần chạy mô phỏng Verilog.

## Cách chạy chương trình điều khiển

Mở PowerShell tại thư mục gốc của dự án và cài thư viện:

```powershell
python -m pip install -r requirements.txt
```

Chạy chương trình:

```powershell
python .\AI_FPGA_Control.pyw
```

Có thể dùng `Control_Center.lnk` để mở nhanh nếu đường dẫn trong shortcut phù
hợp với máy đang sử dụng.

## Cách sử dụng với bo mạch

1. Kết nối Tang Nano 20K với máy tính bằng cáp USB.
2. Gắn thẻ microSD và kết nối màn hình HDMI.
3. Mở `AI_FPGA_Control.pyw`.
4. Chọn đúng cổng COM rồi nhấn **Connect**.
5. Nhấn **Program Hardware (.fs)** để chọn và nạp bitstream FPGA.
6. Nhấn **Initialize microSD** để ghi model và bộ dữ liệu vào thẻ nhớ.
7. Nhấn **Load AI Runtime** để nạp firmware qua UART.
8. Chọn ảnh trên bo mạch và chạy nhận dạng; kết quả được hiển thị qua HDMI.

> **Lưu ý:** `Initialize microSD` ghi trực tiếp lên thẻ nhớ và có thể xóa dữ
> liệu đang có. Cần kiểm tra đúng ổ đĩa trước khi xác nhận.

## Sử dụng RISC-V single-cycle qua UART

Các file liên quan nằm trong `RISC-V/Code/` và `RISC-V/Controller/`.

1. Sửa chương trình kiểm thử trong `RISC-V/Controller/program.S`.
2. Cài RISC-V GNU toolchain có các lệnh `riscv-none-elf-gcc`,
   `riscv-none-elf-objdump` và `riscv-none-elf-objcopy`.
3. Mở PowerShell tại thư mục controller và build chương trình:

   ```powershell
   cd ".\RISC-V\Controller"
   python .\build.py
   ```

4. Mở `run_program_test.py` và sửa biến `PORT` thành cổng COM của bo mạch
   (mặc định hiện tại là `COM8`).
5. Cài PySerial rồi nạp `program.bin` vào Instruction Memory qua UART:

   ```powershell
   python -m pip install pyserial
   python .\run_program_test.py
   ```

`run_program_test.py` sử dụng baud rate `115200`, gửi chương trình vào
Instruction Memory và chờ kết quả của sáu nhóm kiểm thử RV32I trả về qua UART.
Script `build.py` có tham chiếu tới `bin2hex.ps1`; cần đặt file này trong
`RISC-V/Controller/` nếu muốn tạo thêm `program.hex`.

## Build và kiểm thử

Các thao tác build được thực hiện trong thư mục:

```powershell
cd ".\In_FPGA\RISCV_CNN_AI_Accelerator"
```

Build firmware:

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

## Tài liệu và video

- Báo cáo đầy đủ: [`Final_Project.pdf`](Final_Project.pdf)
- Presentation tổng kết dự án: [`RISC-V_CNN_Accelerator_Project_Presentation.pdf`](RISC-V_CNN_Accelerator_Project_Presentation.pdf)
- Video hướng dẫn và trình diễn: [YouTube playlist](https://www.youtube.com/playlist?list=PLU8j17gnRm0I)

Các thành viên có thể tiếp tục bổ sung mã nguồn và tài liệu vào đúng thư mục
tương ứng trong những lần cập nhật sau.
