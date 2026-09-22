# 6. Python Performance & Execution Bottlenecks

## 6.1. Kiến trúc thực thi & Bản chất của GIL (Global Interpreter Lock)

Khi chạy ứng dụng Python trên hệ điều hành, phân tầng kiến trúc diễn ra như sau:

    Python Application
           │
           ▼
    Python Interpreter (CPython)
           │
          GIL (Global Interpreter Lock)
       ┌───┴───┐
       │       │
    Threading Multiprocessing

* Cơ chế hoạt động của GIL: CPython (trình thông dịch mặc định của Python) sử dụng cơ chế quản lý bộ nhớ tự động thông qua Reference Counting (đếm tham chiếu). Để ngăn ngừa hiện tượng tranh chấp bộ nhớ (Race Condition) khi nhiều luồng cùng thay đổi giá trị biến tham chiếu của một đối tượng (PyObject), CPython áp dụng một khóa mutex toàn cục gọi là GIL (Global Interpreter Lock).
* Hệ quả phần cứng: GIL chỉ cho phép duy nhất một luồng (thread) nắm giữ quyền thực thi mã byte (bytecode) tại một thời điểm trên CPU. Dù hệ thống có bao nhiêu nhân vật lý (multi-core), các luồng Python thuần cũng chỉ luân phiên chạy trên 1 nhân CPU duy nhất.

## 6.2. Phân tích CPU-bound vs I/O-bound và Phạm vi hiệu quả

* CPU-bound (Nghẽn tại CPU): Các phép toán nặng về xử lý số liệu, mã hóa, tính toán ma trận. Tác vụ này liên tục đòi hỏi chu kỳ lệnh của CPU.
* I/O-bound (Nghẽn tại I/O): Các thao tác đọc/ghi file từ ổ cứng, gọi socket mạng, gửi HTTP request. Tác vụ này dành phần lớn thời gian để chờ phần cứng ngoại vi phản hồi.

Khi nào threading hiệu quả?
* Chỉ hiệu quả với tác vụ I/O-bound. Khi một luồng rơi vào trạng thái chờ I/O, CPython sẽ tự động nhả GIL để nhường quyền chạy cho luồng khác.

Khi nào dùng multiprocessing?
* Bắt buộc dùng cho tác vụ CPU-bound nếu muốn tận dụng đa nhân. Mỗi tiến trình con sở hữu một không gian bộ nhớ ảo riêng và một tiến trình CPython độc lập (có GIL riêng), giúp tận dụng 100% tài nguyên đa nhân.

GIL ảnh hưởng đến AI như thế nào?
* Các hàm lõi của PyTorch/TensorFlow được viết bằng C++ và tự nhả GIL. Tuy nhiên, nếu khâu tiền xử lý (Preprocessing) hoặc hậu xử lý (Postprocessing) viết bằng Python thuần nhiều luồng, GIL sẽ khóa chặt CPU, biến khâu nạp dữ liệu thành điểm nghẽn nghiêm trọng.

## 6.3. Chuỗi tối ưu hóa hiệu năng (Python Optimization Pipeline)

    Slow Python Loop
           │ (Thay thế vòng lặp thông dịch bằng thư viện C)
           ▼
    NumPy Vectorization
           │ (Gọi các thư viện số học cấp thấp BLAS/LAPACK)
           ▼
    C/C++ Backend
           │ (Tận dụng tập lệnh phần cứng song song)
           ▼
    SIMD / Multi-thread

1. NumPy Vectorization: Sử dụng mảng khối bộ nhớ liên tục (Contiguous Memory Buffer) bằng C. Khi thực thi phép toán mảng, CPU áp dụng tập lệnh SIMD (AVX2/AVX-512) để tính toán đồng thời nhiều dữ liệu trong một xung nhịp.
2. C/C++ Extension: Viết mô-đun tính toán nặng bằng C/C++, biên dịch thành thư viện chia sẻ (.so) và gọi từ Python, hoàn toàn chủ động điều khiển luồng và nhả GIL thủ công.
3. Async Programming: Quản lý hàng nghìn kết nối mạng I/O đồng thời trên một luồng bằng Event Loop (asyncio) với chi phí chuyển đổi ngữ cảnh gần như bằng không.