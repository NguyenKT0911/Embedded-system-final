# 10. AI Runtime / Inference Engine

Nếu mục tiêu cuối cùng là chạy mô hình AI hiệu quả trên Ubuntu CPU, việc đưa toàn bộ framework huấn luyện (như PyTorch/TensorFlow) lên là không tối ưu. Hệ thống cần các Inference Engine chuyên dụng.

    PyTorch / TensorFlow
           │ (Chuyển đổi đồ thị tĩnh trung gian)
           ▼
         ONNX
           │
           ▼
     ONNX Runtime
           │
           ▼
    CPU Execution Provider
           │
           ▼
    Multi-core + SIMD

## 10.1. Hệ sinh thái các Inference Engine phổ biến (Các hướng đáng học)

* ONNX (Open Neural Network Exchange): Định dạng chuẩn mở mô tả đồ thị tính toán của mô hình AI, giúp giao tiếp chéo giữa các framework.
* ONNX Runtime (ORT): Engine suy luận đa nền tảng tối ưu hóa cao. Phân tích đồ thị ONNX và ánh xạ trực tiếp vào phần cứng.
* TensorFlow Lite (TFLite): Engine gọn nhẹ cho thiết bị di động/nhúng.
* OpenVINO: Bộ công cụ của Intel tối ưu suy luận cực mạnh trên kiến trúc x86.
* TVM (Apache TVM): Trình biên dịch học máy tự động sinh mã máy nhị phân tối ưu cho từng vi kiến trúc phần cứng.

## 10.2. Luồng thực thi chi tiết (Execution Flow) từ PyTorch sang CPU

    PyTorch Model (Huấn luyện xong trên Python)
          │
          ▼ (Export ONNX: Cố định trọng số và đóng gói đồ thị)
     ONNX Runtime
       ├── Thread Optimization (Cấu hình số luồng tính toán)
       ├── Graph Optimization (Hợp nhất toán tử, loại bỏ node thừa)
       └── SIMD (Ánh xạ phép tính vào tập lệnh AVX2/AVX-512)
          │
          ▼
         CPU (Thực thi mã máy tốc độ cao)

Ưu thế khi sử dụng Inference Engine:
1. Loại bỏ toàn bộ overhead của cơ chế tính đạo hàm tự động (Autograd Engine).
2. Không phụ thuộc vào môi trường Python cồng kềnh (có thể nhúng qua C/C++ API).
3. Tiêu thụ RAM thấp hơn và tốc độ phản hồi (Latency) nhanh hơn rất nhiều.