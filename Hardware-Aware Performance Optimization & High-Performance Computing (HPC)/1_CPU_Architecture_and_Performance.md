# 1. CPU Architecture & Performance (Kiến trúc CPU & Tối ưu Hiệu suất)

*Bối cảnh học thuật: Khi tối ưu hóa các mô hình Trí tuệ nhân tạo (AI/Deep Learning) trên CPU, quá trình thực thi không chỉ phụ thuộc vào cơ chế Process/Thread của Hệ điều hành, mà còn bị giới hạn bởi ranh giới vật lý của phần cứng (Hardware bounds). Hiểu rõ kiến trúc vi mô (Microarchitecture) của CPU là điều kiện tiên quyết để vắt kiệt hiệu suất.*

## Phân tích chuyên sâu các yếu tố cấu thành (Microarchitecture)

### 1. CPU Cache (Bộ nhớ đệm CPU)
Là hệ thống nhớ tĩnh (SRAM) tốc độ siêu cao được nhúng trực tiếp vào khuôn chip (die) để giảm thiểu hiện tượng thắt cổ chai Von Neumann. Nó được tổ chức theo kiến trúc phân cấp:
*   **L1 Cache (Cấp 1):** Nằm sát nhân xử lý (Core) nhất. Chia làm L1i (chứa lệnh) và L1d (chứa dữ liệu). Tốc độ truy xuất thường mất ~3-4 chu kỳ xung nhịp (clock cycles).
*   **L2 Cache (Cấp 2):** Lớn hơn L1 nhưng chậm hơn (~10-12 cycles). Đóng vai trò vùng đệm độc lập cho từng Core.
*   **L3 Cache (Cấp 3):** Dung lượng lớn nhất (Shared Cache), dùng chung cho toàn bộ các Cores. Độ trễ cao hơn (~40-75 cycles) nhưng vẫn vượt trội so với RAM.

### 2. Cache Locality (Tính cục bộ của bộ nhớ đệm)
Nguyên lý dự đoán của CPU: Khi một dữ liệu được yêu cầu, các dữ liệu lân cận nó cũng có khả năng cao sẽ được sử dụng.
*   **Spatial Locality (Cục bộ không gian):** Duyệt mảng liên tục (contiguous memory) giúp CPU nạp toàn bộ một khối dữ liệu (Cache line - thường là 64 bytes) vào Cache trong 1 lần đọc.
*   **Temporal Locality (Cục bộ thời gian):** Một biến số (như biến đếm vòng lặp) khi vừa được dùng sẽ được giữ lại trong L1 để truy xuất tức thì cho chu kỳ sau.

### 3. Cache Miss (Lỗi trượt bộ nhớ đệm)
Xảy ra khi CPU không tìm thấy dữ liệu trong L1/L2/L3, buộc phải truy xuất từ RAM chính (độ trễ lên đến ~300 cycles). 
*   Trong tính toán ma trận AI, nếu thuật toán duyệt dữ liệu nhảy cóc (như duyệt theo cột của ngôn ngữ C), Cache Miss sẽ xảy ra liên tục, khiến CPU rơi vào trạng thái rảnh rỗi (stall) chờ dữ liệu.

### 4. Memory Bandwidth (Băng thông bộ nhớ)
Tốc độ truyền dẫn dữ liệu tối đa giữa RAM và CPU (tính bằng GB/s). Trong các mô hình AI lớn (như LLM), hệ thống thường bị giới hạn bởi băng thông (Memory-bound) chứ không phải sức mạnh tính toán (Compute-bound).

### 5. SIMD (Single Instruction, Multiple Data)
Mô hình thực thi song song cấp độ dữ liệu (Data-level parallelism). Thay vì dùng 1 lệnh để cộng 2 số (Scalar), CPU cung cấp các thanh ghi vector rộng (128-bit, 256-bit, 512-bit) như **SSE, AVX, AVX-512** để thực hiện 1 lệnh cộng cho 4, 8, hoặc 16 cặp số dấu phẩy động (float32) trong cùng 1 chu kỳ máy.

### 6. Vectorization (Vector hóa)
Quá trình chuyển đổi mã nguồn vô hướng (Scalar code - tính từng phần tử) thành mã nguồn vector (chạy qua lệnh SIMD). Trình biên dịch có thể tự động làm (Auto-vectorization) hoặc lập trình viên ép buộc thông qua Intrinsic functions. 
> *Ví dụ AI:* Thay vì `for(i=0; i<N; i++) C[i] = A[i] * B[i];`, khối Vectorization sẽ xử lý từng cục 8 phần tử một.

### 7. CPU Affinity (Đồng nhất/Ghim luồng CPU)
Kỹ thuật trói buộc (pinning) một luồng (thread) vào một Core vật lý cụ thể thông qua hàm `sched_setaffinity()`.
*   **Mục đích:** Ngăn OS chuyển Thread sang Core khác, giúp tận dụng triệt để dữ liệu đang còn nóng (Warm Cache) trong L1/L2 của Core hiện tại.

### 8. NUMA (Non-Uniform Memory Access)
Kiến trúc cấp phát bộ nhớ trên các máy chủ đa Socket (Nhiều CPU vật lý). Mỗi CPU có vùng RAM nội bộ (Local memory). Khi Thread ở CPU_0 phải đọc RAM thuộc quản lý của CPU_1 (Remote memory), độ trễ (latency) sẽ tăng vọt do phải đi qua bus liên kết QPI/UPI.

### 9. Hyper-threading (Siêu phân luồng)
Công nghệ SMT (Simultaneous Multithreading) của Intel/AMD. Một nhân vật lý (Physical Core) được OS nhận diện thành hai nhân logic (Logical Cores) bằng cách nhân bản tập thanh ghi (Registers). Giúp CPU đan xen thực thi lệnh khi một luồng bị kẹt (ví dụ do Cache Miss).

### 10. Context Switching (Chuyển ngữ cảnh)
Khi OS ngắt một tiến trình để nhường CPU cho tiến trình khác, nó phải lưu trạng thái của thanh ghi hiện tại (PC, Stack Pointer) và nạp trạng thái mới. Quá trình này tốn từ hàng ngàn đến hàng chục ngàn chu kỳ, đồng thời làm mất tính khả dụng của Cache (TLB flush).