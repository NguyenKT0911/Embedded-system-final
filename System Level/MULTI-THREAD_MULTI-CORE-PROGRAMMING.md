# 8: MULTI-THREAD / MULTI-CORE PROGRAMMING

## 1. Nấc thang phát triển kiến trúc thực thi
* **Single Thread (Đơn luồng):** Chương trình chỉ có một dòng chảy tuần tự từ trên xuống dưới. Nếu gặp một lệnh chờ (như đọc mạng, đọc file), toàn bộ chương trình sẽ bị đứng chờ (Freeze).
* **Multi-Thread (Đa luồng):** Chia chương trình thành nhiều dòng chảy công việc chạy đồng thời (*Concurrency*), luồng này chờ mạng thì luồng kia vẫn tính toán hoặc vẽ giao diện bình thường.
* **Multi-Core Programming (Lập trình đa lõi):** Khai thác phần cứng CPU có nhiều Core vật lý để các luồng thực sự chạy song song cùng một tích tắc (*True Parallelism*).

---

## 2. Hai hình thức song song hóa cốt lõi (Parallelism Models)
* **Task Parallelism (Song song hóa tác vụ):**
  * Chia ứng dụng thành các nhiệm vụ có tính chất khác nhau, mỗi nhiệm vụ chạy trên một luồng/core riêng biệt.
  * *Ví dụ trong đồ án:*
    * Core 0: Chạy luồng đọc gói tin mạng TCP từ ESP32.
    * Core 1: Chạy luồng phân tích thuật toán / giải mã tín hiệu.
    * Core 2: Chạy luồng hiển thị giao diện đồ họa cho người dùng.
* **Data Parallelism (Song song hóa dữ liệu):**
  * Có một khối dữ liệu khổng lồ nhưng chỉ áp dụng cùng một thuật toán tính toán. Khối dữ liệu được cắt thành nhiều phần nhỏ để các Core cùng làm việc song song, sau đó gộp kết quả lại (*Merge Result*).
  * *Ứng dụng:* Xử lý ma trận trong mạng nơ-ron AI, xử lý lọc từng hàng điểm ảnh (Pixel) của một bức ảnh camera.

---

## 3. Các kỹ thuật lập trình đa luồng quan trọng
* **Thread Pool (Hồ bơi luồng):**
  * Thay vì mỗi lần có việc lại gọi lệnh tạo luồng mới (rất tốn tài nguyên và thời gian khởi tạo của CPU), ta tạo sẵn một số lượng luồng cố định (ví dụ 4 luồng ứng với 4 core).
  * Khi có tác vụ mới, chương trình chỉ việc ném vào hàng đợi để các luồng đang rảnh tự động lấy ra làm.
* **Producer – Consumer Pattern (Mô hình Người sản xuất – Người tiêu dùng):**
  * Bên tạo dữ liệu (Producer) và bên xử lý dữ liệu (Consumer) hoạt động hoàn toàn độc lập với tốc độ khác nhau thông qua một vùng đệm (Buffer Queue).
* **Work Queue (Hàng đợi công việc):** Cấu trúc dữ liệu lưu danh sách các nhiệm vụ đang chờ được Thread Pool gắp ra thực thi.
* **Load Balancing (Cân bằng tải):** Kỹ thuật phân chia lượng công việc đồng đều giữa các core CPU, ngăn ngừa tình trạng core thì quá tải 100% trong khi core khác bị nhàn rỗi.
* **Parallel Reduction:** Kỹ thuật gộp kết quả tính toán phân tán từ nhiều luồng thành một giá trị duy nhất (ví dụ: chia nhỏ mảng 1 triệu phần tử cho 4 core tính tổng riêng, sau đó cộng 4 tổng con lại).