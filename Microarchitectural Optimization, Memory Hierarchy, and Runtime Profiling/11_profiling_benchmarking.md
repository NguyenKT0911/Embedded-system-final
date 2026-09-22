# 11. Profiling & Benchmarking (Rất quan trọng)

Nguyên tắc kỹ thuật cốt lõi: "Muốn tối ưu thì phải biết chậm ở đâu" và "Không tối ưu trước khi đo".

    AI Application
          │
          ▼
      Profiling ──┬── CPU Usage
                  ├── Memory
                  ├── Cache
                  ├── Thread
                  └── Execution Time
          │
          ▼
    Find Bottleneck (Xác định điểm nghẽn)
          │
          ▼
    Optimization (Ánh xạ kỹ thuật tối ưu)

## 11.1. Chu trình đo kiểm chuẩn (Quy trình Benchmarking)

    Measure
       │
       ▼
    Find Bottleneck
       │
       ▼
    Optimize
       │
       ▼
    Measure Again
       │
       ▼
    Compare

1. Measure: Đo lường hiện trạng ban đầu.
2. Find Bottleneck: Tìm nút thắt cổ chai (Tài nguyên nào đang bão hòa?).
3. Optimize: Thực hiện tối ưu hóa đúng mục tiêu.
4. Measure Again: Đo kiểm lại trong cùng điều kiện.
5. Compare: Đánh giá và so sánh mức độ cải thiện.

## 11.2. Phân loại bộ công cụ chẩn đoán đa tầng

Công cụ phân tích cấp độ Linux (Theo dõi OS):
* top / htop: Theo dõi mức sử dụng tải của từng core CPU, trạng thái tiến trình, RAM chiếm dụng.
* ps: Liệt kê chi tiết cây tiến trình và số lượng luồng.
* free: Giám sát dung lượng RAM thực, bộ nhớ đệm (Buff/Cache) và Swap.
* vmstat: Phân tích số lượt chuyển đổi ngữ cảnh (Context Switch), ngắt hệ thống (Interrupts).
* iostat: Đo thông lượng đọc/ghi đĩa và tỷ lệ chờ I/O.

Công cụ phân tích Hiệu năng (Performance & Hardware):
* perf: Đo bộ đếm phần cứng (Hardware Counters): số chu kỳ lệnh (Cycles), số lượt trượt Cache (Cache Misses).
* time: Phân tách rõ thời gian thực (Real Time), thời gian mã ứng dụng chạy (User Time) và thời gian Kernel chạy (Sys Time).
* Valgrind: Phân tích rò rỉ bộ nhớ (Memory Leak) và cấp phát Heap.
* gprof: Profiler cấp độ hàm cho chương trình C/C++.

Công cụ phân tích cấp độ Python:
* cProfile: Ghi nhận số lần gọi hàm, tổng thời gian của từng module mã Python.
* line_profiler: Phân tích độ trễ chi tiết trên từng dòng code cụ thể.
* memory_profiler: Theo dõi lượng RAM tăng/giảm sau khi mỗi dòng code được thực thi.