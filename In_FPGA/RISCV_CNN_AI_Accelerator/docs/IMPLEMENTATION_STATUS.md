# Trạng thái triển khai 2026-10-16

Đã hoàn thành:

- Hardware `.fs` độc lập firmware, build Gowin và ghi external Flash từ GUI.
- UART BL616 onboard: FPGA RX pin70, TX pin69; không dùng CP2102.
- Packet Loader tối đa 256 byte, address/length/CRC32, ACK/NACK/PING/RUN.
- S1 nhấn-thả chạy CNN; nút UART rời pin 72 giữ 0,5 giây trở lại Loader. Xung
  nút được kéo dài và đồng bộ sang clock CPU. S2 shuffle 100 ảnh không lặp.
- Hai firmware 8 KiB: AI Runtime 8188 byte và Dataset Manager 7972 byte.
- SDHC CMD17/CMD24, ghi sector và đọc lại xác minh.
- RCN1 v3: 100 record × 816 byte, ID/label/valid/image CRC/record CRC.
- Tiền xử lý JPG/PNG thành MNIST 28×28 INT8 trong GUI.
- GUI kết nối COM, nạp IMEM/DMEM, progress/log/status, Flash hardware, khởi tạo
  microSD, xem trước ảnh và cập nhật slot.
- Firmware build, UART hello regression và Gowin bitstream build đều PASS.

Kết quả P&R cuối: Logic 15579/20736 (76%), Register 3226/15750 (21%), BSRAM
46/46 (100%), DSP 22/24 (92%); 0 setup và 0 hold violated endpoint. IMEM và
DMEM giữ 8 KiB dạng lũy thừa hai để Gowin suy luận BSRAM thay vì DFF. Pin report
xác nhận UART RX=70, TX=69.
