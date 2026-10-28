# CƠ SỞ LÝ THUYẾT: KIẾN TRÚC MẠNG TÍCH CHẬP LENET-5

## 1. Giới thiệu tổng quan về LeNet-5
LeNet-5 là một trong những kiến trúc Mạng thần kinh tích chập (Convolutional Neural Network - CNN) đầu tiên và kinh điển nhất, được đề xuất bởi Yann LeCun vào năm 1998. Mô hình này được thiết kế đặc biệt để nhận dạng các ký tự viết tay và chữ số (bộ dữ liệu MNIST). Sự ra đời của LeNet-5 đã đặt nền móng vững chắc cho sự phát triển của các mô hình Deep Learning hiện đại trong lĩnh vực thị giác máy tính (Computer Vision).

Đặc điểm cốt lõi của LeNet-5 là việc sử dụng 3 cơ chế cơ bản:
* Trường tiếp nhận cục bộ (Local Receptive Fields): Trích xuất các đặc trưng không gian (cạnh, góc).
* Chia sẻ trọng số (Shared Weights): Giảm thiểu số lượng tham số cần huấn luyện, giúp mô hình nhẹ hơn.
* Lấy mẫu con không gian (Spatial Subsampling): Giảm kích thước dữ liệu, tăng khả năng kháng nhiễu với các biến dạng nhỏ của hình ảnh.

## 2. Sơ đồ kiến trúc tổng thể

Sơ đồ luồng dữ liệu đi qua các lớp của LeNet-5:

    Input Image
        │   (Ảnh xám kích thước 32x32)
        ▼
    Layer C1: Convolutional Layer
        │   (6 bộ lọc 5x5. Đầu ra: 28x28x6)
        ▼
    Layer S2: Subsampling (Pooling) Layer
        │   (Lấy mẫu trung bình 2x2. Đầu ra: 14x14x6)
        ▼
    Layer C3: Convolutional Layer
        │   (16 bộ lọc 5x5. Đầu ra: 10x10x16)
        ▼
    Layer S4: Subsampling (Pooling) Layer
        │   (Lấy mẫu trung bình 2x2. Đầu ra: 5x5x16)
        ▼
    Layer C5: Convolutional Layer (Fully Connected)
        │   (120 bộ lọc 5x5. Đầu ra: 1x1x120)
        ▼
    Layer F6: Fully Connected Layer
        │   (84 nơ-ron)
        ▼
    Output Layer
            (10 nơ-ron tương ứng 10 lớp phân loại: Chữ số 0-9)

## 3. Phân tích chi tiết từng lớp (Layers)

Kiến trúc LeNet-5 bao gồm tổng cộng 7 lớp (không tính lớp đầu vào), chứa khoảng 60.000 tham số có thể huấn luyện.

1. Lớp đầu vào (Input Layer):
* Kích thước ảnh: $32 \times 32$ pixel, hệ màu Grayscale (1 kênh màu).
* Lý do chọn 32x32: Giúp các đặc trưng quan trọng ở rìa ảnh gốc (28x28) rơi vào tâm của các trường tiếp nhận ở các lớp chập sâu hơn.

2. Lớp C1 (Convolutional Layer 1):
* Số lượng bộ lọc (Filters/Kernels): 6
* Kích thước kernel: $5 \times 5$, bước trượt (stride) = 1.
* Kích thước bản đồ đặc trưng (Feature Map) đầu ra: $28 \times 28 \times 6$.
* Chức năng: Trích xuất các đặc trưng thô ban đầu như cạnh, nét ngang, dọc.

3. Lớp S2 (Subsampling/Average Pooling Layer 2):
* Kích thước cửa sổ pooling: $2 \times 2$, bước trượt = 2.
* Kích thước đầu ra: $14 \times 14 \times 6$.
* Chức năng: Giảm một nửa độ phân giải của bản đồ đặc trưng, làm mờ đi các chi tiết thừa, giúp mạng tập trung vào hình dáng tổng thể và giảm bớt gánh nặng tính toán. Hàm kích hoạt thường dùng là Tanh hoặc Sigmoid.

4. Lớp C3 (Convolutional Layer 3):
* Số lượng bộ lọc: 16
* Kích thước kernel: $5 \times 5$, bước trượt = 1.
* Kích thước đầu ra: $10 \times 10 \times 16$.
* Điểm đặc biệt: Trong bản gốc, LeCun không kết nối tất cả 16 bộ lọc với toàn bộ 6 kênh của S2 để phá vỡ tính đối xứng của mạng và giới hạn số lượng liên kết.

5. Lớp S4 (Subsampling/Average Pooling Layer 4):
* Kích thước cửa sổ pooling: $2 \times 2$, bước trượt = 2.
* Kích thước đầu ra: $5 \times 5 \times 16$.

6. Lớp C5 (Convolutional Layer 5):
* Bản chất là một lớp tích chập với 120 bộ lọc kích thước $5 \times 5$. Do đầu vào từ S4 cũng đang là $5 \times 5$, kết quả đầu ra sẽ trở thành một mảng phẳng kích thước $1 \times 1 \times 120$ (hoạt động giống hệt một lớp Fully Connected).

7. Lớp F6 (Fully Connected Layer):
* Gồm 84 nơ-ron kết nối đầy đủ với 120 nơ-ron của lớp C5. 
* Con số 84 xuất phát từ việc thiết kế ảnh ma trận bitmap ký tự chuẩn theo dạng 7x12 pixel ở thời điểm năm 1998.

8. Lớp Output (Lớp đầu ra):
* Bao gồm 10 nơ-ron, đại diện cho xác suất của 10 lớp ký tự (từ số 0 đến số 9).
* Mạng nguyên bản sử dụng hàm tính lỗi Gaussian (RBF), tuy nhiên trong các cài đặt hiện đại, lớp này thường được thay thế bằng hàm kích hoạt Softmax kết hợp với Cross-Entropy Loss.