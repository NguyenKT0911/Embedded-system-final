# UART Loader và giao thức runtime

UART dùng bridge BL616 tích hợp trên Tang Nano 20K, 115200-8-N-1: FPGA RX
pin 70, FPGA TX pin 69; không dùng CP2102. Nút UART rời nối giữa FPGA pin 72
và 3V3, dùng pull-down nội bộ; giữ 0,5 giây để reset SoC về Loader. S1 chỉ chạy
CNN và S2 chỉ điều khiển chọn/shuffle ảnh.

Packet little-endian:

`55 AA | CMD:u8 | BYTE_ADDRESS:u32 | LENGTH:u16 | PAYLOAD | CRC32:u32`

CRC32 IEEE/zlib bao phủ `CMD + ADDRESS + LENGTH + PAYLOAD`. Loader nhận payload
tối đa 256 byte: `01` ghi IMEM, `02` ghi DMEM, `03` RUN, `04` PING; phản hồi
ACK `79`, PONG `A5`, NACK `1F`.

Dataset Manager nhận payload tối đa 128 byte và trả packet `CMD|80`: `20` đọc
status, `21` đọc slot, `22` BEGIN, `23` ghi chunk, `24` COMMIT CRC, `26` quay
lại Loader bằng MMIO.

Ứng dụng người dùng là `AI_FPGA_Control.pyw`; `tools/uart_bootload.py` chỉ là
CLI dành cho phát triển và regression.
