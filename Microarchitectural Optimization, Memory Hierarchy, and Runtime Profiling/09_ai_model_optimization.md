# 9. AI/DL Model Optimization (Model & Runtime Level)

Tối ưu hóa mô hình AI nằm ở tầng kiến trúc hệ thống cấp cao, nhằm thu nhỏ kích thước mô hình và giảm độ trễ suy luận mà vẫn đảm bảo độ chính xác.

                                 AI MODEL
                                    │
            ┌───────────────────────┼───────────────────────┐
            │                       │                       │
    Algorithm Optimization  Model Optimization      Runtime Optimization
            │                       │                       │
         Pruning              Quantization           Thread, Memory, CPU
                             (FP32 -> INT8)

## 9.1. Tối ưu cấp độ mô hình (Model-level Optimization)

* Quantization (Lượng tử hóa):
  * Chuyển đổi tham số trọng số (weights) và giá trị kích hoạt (activations) từ độ chính xác FP32 (32-bit floating point) sang INT8 (8-bit integer).
  * Lợi ích phần cứng: Giảm dung lượng mô hình đi 4 lần, giảm nghẽn băng thông bộ nhớ (Memory Bandwidth Bottleneck) và tận dụng tập lệnh INT8 trên CPU.
* Pruning (Cắt tỉa trọng số):
  * Loại bỏ các liên kết hoặc trọng số có giá trị gần bằng 0. Gồm Unstructured Pruning (tạo ma trận thưa) và Structured Pruning (cắt bỏ hẳn kênh/neuron).
* Knowledge Distillation (Chưng cất tri thức):
  * Dùng mô hình lớn (Teacher Model) đào tạo mô hình nhỏ (Student Model) học phân phối xác suất mềm (Soft Labels), duy trì độ chính xác với chi phí tính toán thấp.
* Lightweight Model Architecture:
  * Thiết kế kiến trúc tối ưu cho thiết bị nhúng/CPU bằng Depthwise Separable Convolution (MobileNet) hay Channel Shuffle (ShuffleNet) để giảm lượng phép toán.
* Operator Fusion (Hợp nhất toán tử):
  * Gộp các phép toán liền kề (ví dụ: Conv + BatchNorm + ReLU) thành một khối thực thi duy nhất. Giảm thiểu đọc/ghi RAM trung gian và giảm số lượt Cache Miss.

## 9.2. Tối ưu cấp độ thực thi (Runtime-level Optimization)

* Thread Optimization: Phân định cấu hình Intra-op parallelism (chia nhỏ một phép tính lớn cho nhiều nhân xử lý) và Inter-op parallelism (chạy song song các nhánh độc lập trong đồ thị).
* CPU Affinity (Ghim nhân CPU): Cố định luồng vào nhân CPU vật lý cụ thể (qua lệnh taskset hoặc sched_setaffinity), ngăn hệ điều hành luân chuyển tiến trình qua lại, bảo toàn dữ liệu nóng trong Cache L1/L2.
* Memory Reuse: Cấp phát trước một vùng đệm tĩnh (Memory Buffer Pool) thay vì gọi liên tục lệnh malloc() / free() sau mỗi frame dữ liệu, giúp triệt tiêu độ trễ phân mảnh bộ nhớ.
* Batch Size: Gom nhóm các mẫu dữ liệu vào cùng một lần suy luận để lấp đầy và tận dụng tối đa độ rộng của vector SIMD trên phần cứng.