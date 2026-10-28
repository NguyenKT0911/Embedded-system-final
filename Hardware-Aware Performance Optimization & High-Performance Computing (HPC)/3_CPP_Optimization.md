# 3. C/C++ Optimization (Kỹ thuật Tối ưu Hóa Mã Nguồn Hạng Nặng)

*Bối cảnh học thuật: Các Framework AI hiện đại như TensorFlow hay PyTorch luôn duy trì mô hình phân lớp. Tầng trên là Python (High-level AI Application) đóng vai trò giao diện dễ phát triển, trong khi các phép toán lõi (Optimized Computation) được chuyển giao hoàn toàn xuống tầng C/C++ để khai thác năng lực CPU/SIMD.*

## Kỹ thuật Tối ưu Hóa C/C++ Cấp thấp

### 1. Compiler Optimization (`-O2`, `-O3`)
Đừng tối ưu bằng tay những thứ Compiler có thể làm. GCC/Clang cung cấp các cờ (flags) để tự động hóa:
*   **`-O2`:** Tối ưu hóa mức độ cao mà không làm phình kích thước file nhị phân. Bao gồm xóa mã chết (dead code elimination), lập lịch lệnh (instruction scheduling).
*   **`-O3`:** Tối ưu hóa cực đoan (Aggressive optimization). Trình biên dịch sẽ cố gắng dự đoán nhánh (branch prediction), gỡ cuộn vòng lặp (loop unrolling) và quan trọng nhất là Tự động Vector hóa (Auto-vectorization) các phép toán vô hướng thành toán SIMD.

### 2. Inline function (`inline` keyword)
Hàm (Function) sinh ra chi phí (overhead) lưu tham số vào Stack và nhảy lệnh (jump). Khai báo `inline` yêu cầu Compiler bê nguyên nội dung của hàm đó chèn trực tiếp vào nơi gọi. Cực kỳ hiệu quả cho các hàm tính toán ngắn, lặp lại hàng triệu lần (ví dụ: hàm kích hoạt ReLU).

### 3. Pointer & Aliasing
*   **Con trỏ (Pointer):** Cho phép can thiệp trực tiếp vào địa chỉ vùng nhớ vật lý.
*   **Pointer Aliasing:** Khi 2 con trỏ cùng trỏ về một vùng nhớ, Compiler sẽ không dám tối ưu hóa vòng lặp vì sợ sai lệch dữ liệu. Sử dụng từ khóa `restrict` (trong C) báo cho Compiler biết con trỏ này là độc quyền, giúp Compiler mạnh dạn đưa biến vào thanh ghi (Register) để chạy nhanh hơn.

### 4. Memory Alignment (Căn chỉnh bộ nhớ)
CPU không đọc từng byte mà đọc từng khối (Cache Line, thường là 64 bytes).
*   Nếu một ma trận dữ liệu bắt đầu ở địa chỉ chia hết cho 64 (Align), CPU chỉ cần 1 chu kỳ để lấy lên Cache.
*   Nếu dữ liệu nằm vắt ngang giữa hai Cache Line (Unaligned), CPU phải thực hiện 2 chu kỳ nạp bộ nhớ, giảm 50% hiệu suất. Trong C, ta dùng `posix_memalign()` hoặc các từ khóa căn chỉnh của Compiler để ép dữ liệu vào đúng biên bộ nhớ.

### 5. Cache Optimization (Tối ưu hóa thân thiện Cache)
*   **Loop Tiling (Chia gạch vòng lặp):** Trong phép nhân ma trận lớn $O(N^3)$, nếu kích thước ma trận vượt quá dung lượng L1/L2 Cache, sẽ sinh ra Cache Miss liên tục. Kỹ thuật Loop Tiling bẻ ma trận lớn thành các khối (block/tile) nhỏ vừa vặn với kích thước Cache L1, xử lý dứt điểm từng khối rồi mới đi tiếp, tăng tỷ lệ Cache Hit (trúng bộ nhớ đệm) lên tối đa.

### 6. SIMD Intrinsics (Hàm nội tại SIMD)
Khi tính năng Auto-vectorization của Compiler (`-O3`) không đủ thông minh, lập trình viên C/C++ sẽ sử dụng bộ thư viện `<immintrin.h>`.
*   Đây là các lệnh cung cấp quyền truy cập trực tiếp vào tập lệnh AVX/AVX-512 của phần cứng.
*   *Ví dụ:* `_mm256_loadu_ps` (Nạp 8 số float vào thanh ghi 256-bit), `_mm256_fmadd_ps` (Nhân cộng chập Fused Multiply-Add), giúp tính ma trận nhanh hơn từ 8-16 lần so với vòng lặp `for` thông thường.

### 7. OpenMP (Open Multi-Processing)
Tiêu chuẩn công nghiệp để triển khai Đa luồng (Multi-threading) trên bộ nhớ chia sẻ.
*   Thay vì phải khởi tạo Pthreads thủ công phức tạp (khai báo mutex, quản lý vòng đời thread), lập trình viên chỉ cần chèn chỉ thị Tiền xử lý (Preprocessor directive) trước vòng lặp:
    `#pragma omp parallel for`
*   OpenMP sẽ tự động chia đều (fork) số lần lặp của vòng lặp cho tất cả các Core vật lý hiện có của CPU để xử lý song song, sau đó gom lại (join) ở cuối tiến trình.

> **Tiến trình vắt kiệt hiệu năng (Evolution of Performance):**
> Mã C nguyên thủy (Single Thread) $\rightarrow$ Tích hợp OpenMP (Chạy đa nhân) $\rightarrow$ Tích hợp SIMD (Song song hóa dữ liệu trên mỗi nhân) $\rightarrow$ Tối đa hóa phần cứng.