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
| `RISC-V/` | Tài liệu và mã nguồn liên quan đến lõi RISC-V được sử dụng trong hệ thống. |
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
| `Summary.pdf` | Bản tóm tắt đồ án. |
| `Summary.docx` | Bản Word có thể chỉnh sửa của tài liệu tóm tắt. |
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
- Bản tóm tắt: [`Summary.pdf`](Summary.pdf)
- Video trình diễn: [Release v1.0.0](https://github.com/NguyenKT0911/Embedded-system-final/releases/tag/v1.0.0)

Các thành viên có thể tiếp tục bổ sung mã nguồn và tài liệu vào đúng thư mục
tương ứng trong những lần cập nhật sau.
