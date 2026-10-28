# TỔNG HỢP KIẾN THỨC NỀN TẢNG LINUX OPERATING SYSTEM (USER SPACE)

## 1. Khái niệm nền tảng hệ thống
* **User Space vs Kernel Space:**
  * **User Space (Ring 3):** Không gian bộ nhớ dành riêng cho các ứng dụng thông thường của người dùng thực thi. Tại đây, ứng dụng bị hạn chế quyền hạn, không được phép truy cập trực tiếp vào phần cứng vật lý nhằm bảo đảm an toàn hệ thống.
  * **Kernel Space (Ring 0):** Không gian bộ nhớ đặc quyền cao nhất dành cho nhân hệ điều hành (Linux Kernel). Nơi quản lý trực tiếp tài nguyên phần cứng (CPU, RAM, thiết bị ngoại vi) và thực thi các trình điều khiển (Device Drivers).
* **System Call (Lời gọi hệ thống):** Cầu nối giao tiếp cho phép một chương trình đang thực thi ở User Space yêu cầu các dịch vụ đặc quyền từ Kernel Space (ví dụ: cấp phát bộ nhớ, thao tác file, kết nối mạng).

---

## 2. Nhánh Quản lý Tiến trình (Process)
* **Process (Tiến trình):** Một thực thể độc lập của một chương trình đang được thực thi trong bộ nhớ, sở hữu không gian địa chỉ ảo (Virtual Address Space) và mã định danh riêng biệt (PID - Process ID).
* **`fork()`:** Hàm hệ thống tạo một tiến trình con bằng cách nhân bản (sao chép toàn bộ ngữ cảnh bộ nhớ, bảng file descriptor) từ tiến trình cha hiện tại. Tiến trình con nhận một PID mới.
* **`exec()` (Họ hàm `exec*`):** Hàm hệ thống nạp và ghi đè một tệp nhị phân mới vào không gian địa chỉ của tiến trình hiện tại, thay thế toàn bộ mã lệnh cũ bằng mã lệnh mới nhưng vẫn giữ nguyên PID.
* **`wait()` / `waitpid()`:** Hàm hệ thống bắt tiến trình cha tạm dừng (block) để chờ tiến trình con kết thúc, thu nhận mã thoát (Exit Status) và giải phóng các cấu trúc dữ liệu của tiến trình con nhằm chống sinh tiến trình ma (Zombie Process).
* **`signal`:** Cơ chế thông báo sự kiện ngắt mềm không đồng bộ do nhân hệ điều hành hoặc tiến trình khác gửi tới để yêu cầu xử lý (ví dụ: `SIGINT` khi ngắt bằng bàn phím, `SIGKILL` để buộc dừng).

---

## 3. Nhánh Quản lý Luồng (Thread)
* **Thread (Luồng / Lightweight Process):** Đơn vị thực thi nhỏ nhất được bộ điều phối của hệ điều hành gán thời gian chạy trên CPU. Một tiến trình có thể chứa nhiều luồng; các luồng này chia sẻ chung không gian bộ nhớ (Code, Data, Heap) nhưng sở hữu ngăn xếp (Stack) và thanh ghi riêng.
* **`pthread` (POSIX Threads):** Tiêu chuẩn giao diện lập trình luồng theo chuẩn POSIX trên các hệ điều hành họ Unix/Linux thông qua thư viện `<pthread.h>`.
* **Thread Lifecycle (Vòng đời của Luồng):** Tập hợp các trạng thái một luồng trải qua từ khi được tạo: *Khởi tạo (Ready)* -> *Đang chạy (Running)* -> *Chờ tài nguyên/Chặn (Blocked/Waiting)* -> *Kết thúc (Terminated)*.
* **Thread Scheduling (Lập lịch cho Luồng):** Cơ chế nhân Linux phân bổ thời gian thực thi của các CPU core cho từng luồng dựa trên mức ưu tiên và thuật toán chia sẻ thời gian (Completely Fair Scheduler - CFS).
* **`pthread_create()`:** Hàm tạo và khởi chạy một luồng thực thi mới trong cùng một tiến trình.
* **`pthread_join()`:** Hàm đồng bộ bắt một luồng phải tạm dừng để chờ một luồng khác kết thúc công việc trước khi thu gom tài nguyên và tiếp tục chạy.

---

## 4. Nhánh Bộ nhớ (Memory)
* **Stack (Ngăn xếp):** Vùng nhớ hoạt động theo cơ chế LIFO (Last In First Out), do trình biên dịch và hệ điều hành tự động cấp phát và giải phóng. Dùng để lưu trữ biến cục bộ, tham số hàm và địa chỉ trở về. Tốc độ rất nhanh nhưng kích thước bị giới hạn.
* **Heap:** Vùng nhớ dùng để cấp phát động trong quá trình chạy chương trình thông qua các hàm như `malloc()`, `calloc()`. Do lập trình viên chủ động quản lý kích thước và giải phóng (`free()`). Dung lượng lớn nhưng dễ xảy ra rò rỉ bộ nhớ (Memory Leak).
* **`mmap()`:** Lời gọi hệ thống ánh xạ trực tiếp một tệp tin trên ổ đĩa hoặc một vùng nhớ chia sẻ vào không gian địa chỉ ảo của tiến trình, cho phép truy cập dữ liệu với tốc độ cao mà không cần qua bước sao chép bộ đệm.
* **Virtual Memory (Bộ nhớ ảo):** Kỹ thuật quản lý bộ nhớ tạo ra một không gian địa chỉ liên tục giả lập cho mỗi tiến trình. Đơn vị quản lý bộ nhớ phần cứng (MMU) kết hợp cùng hệ điều hành sẽ ánh xạ các địa chỉ ảo này thành địa chỉ RAM vật lý thông qua bảng trang (Page Tables).

---

## 5. Nhánh Lập lịch CPU (CPU Scheduling)
* **Context Switching (Chuyển đổi ngữ cảnh):** Quá trình CPU lưu lại trạng thái thực thi hiện tại của một tiến trình/luồng (nội dung thanh ghi, con trỏ ngăn xếp) và khôi phục trạng thái của một tiến trình/luồng khác để tiếp tục thực thi.
* **Priority (Độ ưu tiên):** Giá trị số học biểu thị mức độ ưu tiên cấp phát chu kỳ CPU cho một tác vụ (thường được điều chỉnh thông qua giá trị `nice` từ -20 đến 19 trên Linux).
* **CPU Affinity (Gắn kết CPU):** Kỹ thuật gán cố định một tiến trình hoặc luồng chỉ được phép thực thi trên một lõi (core) CPU vật lý nhất định, giúp giảm thiểu độ trễ do chuyển đổi ngữ cảnh và tối ưu hóa bộ nhớ đệm Cache CPU.