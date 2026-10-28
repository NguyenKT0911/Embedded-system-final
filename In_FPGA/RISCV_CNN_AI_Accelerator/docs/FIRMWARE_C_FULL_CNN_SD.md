# Firmware C, CNN và microSD

## Kiến trúc chạy

Phần cứng RV32I, UART Loader, SPI microSD, CNN Accelerator và HDMI nằm trong
bitstream Flash. Sau khi cấp nguồn, cầu UART BL616 tích hợp trên Tang Nano 20K
nạp IMEM/DMEM bằng packet có địa chỉ, độ dài và CRC32; không cần CP2102 rời.

Do IMEM chỉ có 8 KiB và đã sử dụng 8.188/8.192 byte, hệ thống có hai firmware:

- **AI Runtime**: đọc model/ảnh từ microSD, chạy CNN và xuất HDMI.
- **Dataset Manager**: nhận ảnh MNIST INT8 qua UART, ghi slot microSD, đọc lại,
  kiểm tra CRC rồi mới đánh dấu slot hợp lệ.

Giữ nút UART rời nối pin 72 khoảng 0,5 giây sẽ dừng/reset CPU và trở lại UART
Loader. Nhấn-thả S1 khi AI Runtime đang chạy sẽ bắt đầu suy luận. S2 chọn ảnh
theo chu kỳ shuffle 100 phần tử không lặp sớm.

## Luồng AI Runtime

1. Khởi tạo microSD ở SPI mode và kiểm tra header RCN1 v3.
2. Đọc ảnh được shuffle chọn từ slot 0..99 và cập nhật preview HDMI.
3. Conv1/Conv2 chạy trên accelerator; Pool/Requant/FC/Argmax chạy trong firmware.
4. Prediction, sample ID và confidence được commit nguyên tử cho HDMI.

## Định dạng SD RCN1 version 3

`sd_image/model_sd.img` là ảnh sector thô, không dùng FAT. Sector 0 chứa header,
bảng section và CRC32. Các section bất biến chứa Conv1, Conv2, FC1, bias, FC2 và
tham số lượng tử hóa. Vùng dataset bắt đầu tại sector 408.

Mỗi trong 100 slot dài 816 byte:

- byte 0..3: sample ID;
- byte 4: nhãn 0..9;
- byte 5: cờ hợp lệ;
- byte 8..11: CRC32 của ảnh;
- byte 12..15: CRC32 toàn record;
- byte 16..19: calibration max;
- byte 20..29: confidence tham chiếu;
- byte 32..815: ảnh 28x28 INT8.

Ảnh hiện tại dài 290.816 byte, tương đương 568 sector. Dataset Manager cập nhật
theo thứ tự `begin -> chunk -> commit`; cờ valid chỉ được bật sau khi CRC ảnh và
read-back microSD đều đạt.

## Build và kiểm thử

```powershell
cd In_FPGA\RISCV_CNN_AI_Accelerator
.\firmware_c\build_firmware.ps1
python .\tools\export_sd_image.py "..\..\Model Training\FPGA_UART_export" .\sd_image
.\scripts\run_c_firmware_tests.ps1 -Quick
.\scripts\build_fpga.ps1
```

Exporter kiểm tra pipeline host và pipeline số nguyên trên đủ 100 ảnh; kết quả
tham chiếu là 98/100. Testbench nạp firmware qua đúng giao thức UART CRC32 thay
vì dùng `$readmemh` trực tiếp vào RAM.

## Sử dụng

Mở `AI_FPGA_Control.pyw` ở thư mục gốc. Ứng dụng đảm nhiệm chọn COM, ghi Flash,
khởi tạo microSD, nạp hai firmware, tiền xử lý JPG/PNG và cập nhật dataset. Các
launcher `.bat` cũ đã bị loại bỏ để chỉ còn một quy trình nhất quán.
