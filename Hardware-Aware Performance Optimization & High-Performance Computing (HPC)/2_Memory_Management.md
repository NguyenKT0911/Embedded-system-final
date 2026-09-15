# 2. Memory Management (Quản trị Hệ thống Bộ nhớ)

*Bối cảnh học thuật: Các mô hình AI/Deep Learning làm việc với các khối Tensor (ma trận đa chiều) có kích thước khổng lồ. Việc quản trị bộ nhớ kém không chỉ gây cạn kiệt tài nguyên (OOM - Out of Memory) mà còn làm giảm tốc độ suy luận (Inference speed) do chi phí (overhead) của Hệ điều hành.*

## I. Linux Memory (Quản lý cấp hệ điều hành)

### 1. Virtual Memory & Physical Memory
*   **Virtual Memory (Bộ nhớ ảo):** Abstraction (lớp trừu tượng) do Kernel cung cấp. Mỗi tiến trình tưởng rằng nó đang sở hữu toàn bộ không gian RAM tĩnh.
*   **Physical Memory (Bộ nhớ vật lý):** Dung lượng RAM thực tế gắn trên bo mạch chủ. Khối quản lý bộ nhớ (MMU - Memory Management Unit) trên CPU chịu trách nhiệm dịch địa chỉ ảo sang địa chỉ vật lý.

### 2. Page & Page Fault
*   **Page (Trang nhớ):** Bộ nhớ ảo và vật lý được chia thành các khối có kích thước cố định (thường là 4KB). Quá trình ánh xạ được thực hiện trên từng Page thông qua Page Table.
*   **Page Fault (Lỗi trang):** Xảy ra khi CPU truy xuất một địa chỉ ảo chưa được ánh xạ vào RAM vật lý (hoặc đã bị tống xuống ổ cứng). HĐH phải kích hoạt ngắt (interrupt) để nạp trang đó từ ổ cứng vào RAM, gây ra độ trễ I/O khổng lồ.

### 3. Swap (Không gian tráo đổi)
Vùng không gian trên ổ cứng (HDD/SSD) được dùng làm RAM phụ. Khi RAM vật lý đầy, Kernel sẽ đẩy các Pages ít dùng nhất (LRU thuật toán) xuống Swap. Truy cập vào Swap chậm hơn RAM hàng ngàn lần.

### 4. Memory mapping (`mmap()`)
Hệ thống lệnh POSIX cho phép ánh xạ trực tiếp không gian bộ nhớ của tiến trình vào một tệp (file) hoặc một thiết bị phần cứng. Nó bỏ qua bộ đệm của không gian người dùng (user-space buffer), tăng tốc độ đọc/ghi dữ liệu lớn.

### 5. Copy-on-write (CoW - Sao chép khi ghi)
Khi dùng lệnh `fork()` để tạo Process con, Kernel không copy toàn bộ RAM của Process cha. Cả hai dùng chung một vùng nhớ vật lý (chỉ đọc). Chỉ khi một Process cố tình "ghi/chỉnh sửa", Kernel mới cấp phát một Page mới để copy dữ liệu sang.

## II. C/C++ Memory (Quản lý cấp ngôn ngữ)

*   **Stack allocation:** Cấp phát tĩnh bởi Compiler. Các biến cục bộ được đẩy (push) và lấy (pop) ra khỏi Stack cực nhanh bằng cách dịch chuyển con trỏ Stack Pointer. Dung lượng rất nhỏ (thường ~8MB trên Linux).
*   **Heap allocation:** Cấp phát động khi Runtime. Kích thước khổng lồ, quản lý rải rác.
*   **`malloc()` & `free()`:** API tiêu chuẩn của C để xin Kernel cấp phát (brk, sbrk) và trả lại bộ nhớ Heap. Quá trình tìm kiếm vùng nhớ trống trong Heap tốn nhiều chi phí thời gian.
*   **Memory leak (Rò rỉ bộ nhớ):** Khi cấp phát `malloc()` nhưng bỏ quên không `free()`. Khối RAM đó bị khóa vĩnh viễn cho đến khi tiến trình bị OS tiêu diệt.
*   **Buffer overflow (Tràn bộ đệm):** Hành vi ghi dữ liệu vượt quá kích thước vùng nhớ được cấp, dẫn đến ghi đè lên các vùng dữ liệu lân cận hoặc mã điều khiển hệ thống, gây lỗi Segmentation Fault.

## III. AI Performance (Tối ưu hóa bộ nhớ cho AI)

Mô hình chống chỉ định trong AI: `Load Data -> Allocate -> Free -> Allocate -> Free`.

*   **Memory allocation overhead:** Việc gọi `malloc()/free()` liên tục trong các vòng lặp tính Tensor buộc User-space phải gọi Syscall xuống Kernel-space, làm CPU phải chờ đợi HĐH (Overhead cao).
*   **Tensor allocation:** Các Tensors trong mạng Neural thay đổi kích thước theo từng Layer. Nếu không quản lý tốt sẽ gây phân mảnh bộ nhớ (Memory fragmentation).
*   **Memory Pool & Memory Reuse (Tối ưu thiết yếu):**
    *   **Pre-allocate:** Xin OS cấp một vùng RAM khổng lồ duy nhất lúc khởi động (Memory Pool).
    *   **Reuse:** Khi một Tensor không dùng nữa, thay vì `free()` trả OS, ta đưa vùng nhớ đó vào danh sách chờ. Khi cần tạo Tensor mới, ta tái sử dụng (Reuse) trực tiếp vùng nhớ này (Time complexity: $O(1)$).
*   **Zero-copy:** Kỹ thuật truyền dữ liệu trực tiếp từ ổ cứng/card mạng vào RAM mà không cần CPU tham gia sao chép (bằng công nghệ DMA), tiết kiệm tài nguyên CPU.
*   **Shared memory:** Đẩy dữ liệu qua lại giữa các Process (ví dụ: IPC `shmget`) mà không cần thông qua đường ống (Pipe/Socket), dữ liệu được đọc/ghi trực tiếp trên cùng một phân vùng vật lý.