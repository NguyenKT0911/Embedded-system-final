# 2: IPC – INTER-PROCESS COMMUNICATION

## 1. Bản chất cốt lõi: Tại sao phải cần IPC?
* Trong Linux, mỗi tiến trình (Process) khi khởi chạy được cấp phát một **không gian địa chỉ ảo (Virtual Address Space) hoàn toàn độc lập**.
* Tiến trình A **tuyệt đối không thể tự ý đọc hay ghi vào bộ nhớ của Tiến trình B** (cơ chế bảo vệ bộ nhớ của hệ điều hành).
* **IPC (Inter-Process Communication)** chính là các "cây cầu" hoặc "kênh liên lạc" do nhân hệ điều hành (Kernel) cung cấp, giúp các tiến trình cách ly này có thể gửi nhận dữ liệu hoặc tín hiệu cho nhau an toàn.

---

## 2. Phân loại các cơ chế IPC theo mô hình kiến trúc

### Nhóm 1: Local IPC (Giao tiếp nội bộ giữa các tiến trình trên cùng một máy)
* **Signal (Tín hiệu):**
  * *Bản chất:* Là một ngắt phần mềm (software interrupt) truyền từ Kernel hoặc tiến trình này sang tiến trình khác.
  * *Đặc điểm:* Chỉ báo hiệu "sự kiện đã xảy ra" chứ không truyền được khối dữ liệu phức tạp.
  * *Ví dụ:* Khi nhấn tổ hợp phím `Ctrl + C` trên bàn phím, hệ điều hành gửi tín hiệu `SIGINT` đến tiến trình đang chạy để yêu cầu dừng an toàn.
* **Pipe (Ống dẫn vô danh):**
  * *Bản chất:* Tạo ra một đường ống truyền dữ liệu byte-stream một chiều (đầu này ghi - đầu kia đọc) hoạt động theo cơ chế FIFO (vào trước ra trước).
  * *Đặc điểm:* Chỉ dùng được giữa các tiến trình có quan hệ "huyết thống" (cha - con) tạo ra từ lệnh `fork()`.
* **FIFO (Named Pipe - Ống dẫn có tên):**
  * *Bản chất:* Cơ chế hoạt động y hệt Pipe nhưng được định danh bằng một file đặc biệt nằm trên ổ đĩa.
  * *Đặc điểm:* Cho phép 2 tiến trình hoàn toàn xa lạ (không cùng cha-con) có thể tìm thấy nhau thông qua đường dẫn file để trao đổi dữ liệu.
* **Message Queue (Hàng đợi thông điệp):**
  * *Bản chất:* Một danh sách liên kết các gói tin (gọi là message) nằm trong bộ nhớ do Kernel quản lý.
  * *Đặc điểm:* Dữ liệu được đóng gói thành từng thông điệp riêng biệt có kèm độ ưu tiên (Priority), bên nhận có thể chọn đọc thông điệp ưu tiên trước thay vì chỉ đọc tuần tự FIFO.
* **Unix Domain Socket (UDS):**
  * *Bản chất:* Giao thức Socket nhưng chỉ chạy nội bộ trên cùng một hệ điều hành thông qua một file socket cục bộ (`.sock`).
  * *Đặc điểm:* Tốc độ nhanh hơn nhiều so với Socket mạng vì bỏ qua toàn bộ các lớp kiểm tra checksum và định tuyến của ngăn xếp mạng TCP/IP.

### Nhóm 2: Shared IPC (Chia sẻ vùng nhớ cục bộ)
* **Shared Memory (Bộ nhớ chia sẻ):**
  * *Bản chất:* Hệ điều hành ánh xạ trực tiếp cùng một khối RAM vật lý vào không gian địa chỉ của nhiều tiến trình.
  * *Đặc điểm:* **Là phương thức IPC có tốc độ cao nhất** vì các tiến trình đọc/ghi thẳng vào RAM thật mà không cần Kernel phải sao chép dữ liệu qua lại (Zero-copy). Bắt buộc phải kết hợp với công cụ khóa (như Semaphore/Mutex) để tránh ghi đè dữ liệu.
* **`mmap()` (Memory Mapping):**
  * *Bản chất:* Hàm hệ thống dùng để ánh xạ một file trên đĩa hoặc một vùng nhớ ẩn danh vào bộ nhớ tiến trình, giúp thao tác với file nhanh như thao tác với mảng trong RAM.

### Nhóm 3: Network IPC (Giao tiếp qua mạng)
* **TCP Socket (Transmission Control Protocol):**
  * *Bản chất:* Giao thức hướng kết nối (Connection-oriented), yêu cầu thiết lập bắt tay (Handshake) trước khi truyền tin.
  * *Đặc điểm:* Đảm bảo dữ liệu không bị mất mát, đúng thứ tự gói tin. Phù hợp cho việc gửi lệnh điều khiển, kết quả test từ Ubuntu xuống mạch ngoại vi (ESP32).
* **UDP Socket (User Datagram Protocol):**
  * *Bản chất:* Giao thức phi kết nối (Connectionless), cứ thế gửi gói tin đi mà không chờ xác nhận.
  * *Đặc điểm:* Tốc độ cực nhanh, độ trễ thấp nhưng có thể mất vài gói tin nhỏ. Phù hợp cho việc bắn luồng dữ liệu cảm biến (streaming data) liên tục.

### Nhóm 4: Nâng cao & Ứng dụng AI/Distributed
* **ZeroMQ / MQTT:** Các thư viện nhắn tin nhẹ, linh hoạt cho hệ thống IoT và nhúng phân tán.
* **gRPC / HTTP REST:** Giao thức giao tiếp cấp cao giữa các dịch vụ (Microservices), thường dùng để ứng dụng C/C++ gọi sang một Service chạy model AI bằng Python.