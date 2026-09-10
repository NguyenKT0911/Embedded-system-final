#  3: SYNCHRONIZATION – ĐỒNG BỘ HÓA

## 1. Tại sao phải đồng bộ hóa? (Các khái niệm cốt lõi)
* **Shared Resource (Tài nguyên dùng chung):** Bất kỳ biến bộ nhớ, file, bộ đệm (buffer) hoặc thiết bị ngoại vi nào mà nhiều luồng/tiến trình cùng có quyền truy cập.
* **Critical Section (Vùng tranh chấp / Đoạn găng):** Đoạn mã nguồn mà trong đó luồng thực hiện việc đọc/ghi vào tài nguyên dùng chung.
* **Race Condition (Tình trạng tranh chấp):** Hiện tượng xảy ra khi nhiều luồng cùng sửa đổi dữ liệu đồng thời, dẫn đến kết quả cuối cùng bị phụ thuộc vào việc luồng nào "chạy nhanh hơn" thay vì tính toán logic đúng.
  * *Ví dụ:* Tài khoản có 100k. Luồng A rút 50k, Luồng B nạp 50k. Cả hai cùng đọc số 100k một lúc rồi ghi đè $\rightarrow$ Số dư cuối cùng bị sai lệch.

---

## 2. Các rủi ro và lỗi kinh điển cần hiểu rõ
* **Deadlock (Khóa chết):** Hiện tượng hai tiến trình chờ đợi lẫn nhau giải phóng tài nguyên vô thời hạn, làm toàn bộ chương trình bị treo vĩnh viễn.
  * *Ví dụ:* Luồng 1 đang giữ Khóa A và chờ xin Khóa B; cùng lúc đó Luồng 2 đang giữ Khóa B và chờ xin Khóa A. Cả hai không bên nào chịu nhường.
* **Starvation (Đói tài nguyên):** Một luồng có độ ưu tiên thấp liên tục bị "bỏ đói", không bao giờ được cấp quyền truy cập tài nguyên vì các luồng ưu tiên cao hơn liên tục chiếm chỗ.
* **Livelock (Khóa động):** Tương tự deadlock, nhưng các luồng không đứng yên mà liên tục đổi trạng thái nhường nhịn nhau vòng tròn, kết quả là không có tác vụ nào thực sự được hoàn thành.
* **Priority Inversion (Nghịch đảo độ ưu tiên):** Luồng có độ ưu tiên cao nhất bị chặn gián tiếp bởi luồng có độ ưu tiên thấp nhất (do luồng thấp đang giữ khóa tài nguyên dùng chung mà luồng cao cần dùng).

---

## 3. Các công cụ đồng bộ hóa phổ biến

* **1. Mutex (Mutual Exclusion - Khóa độc quyền):**
  * *Cơ chế:* Hoạt động như một "ổ khóa duy nhất" vào phòng họp. 
  * Chỉ luồng nào cầm chìa khóa (`lock`) mới được vào Critical Section. Các luồng khác đến sau phải đứng chờ ngoài cửa cho đến khi luồng cầm chìa đi ra và mở khóa (`unlock`).
  * *Quy tắc vàng:* Luồng nào khóa thì chính luồng đó mới có quyền mở khóa.
* **2. Semaphore (Đèn hiệu / Biến đếm):**
  * *Cơ chế:* Là một biến đếm nguyên tử thể hiện số lượng tài nguyên khả dụng.
  * *Ví dụ:* Bãi đỗ xe có 3 chỗ trống (Semaphore = 3). Mỗi khi có 1 xe vào thì trừ đi 1 (`wait`). Khi số chỗ bằng 0, xe tiếp theo phải đứng chờ. Khi có xe ra thì cộng thêm 1 (`post`).
* **3. Condition Variable (Biến điều kiện):**
  * *Cơ chế:* Dùng để báo thức sự kiện. Luồng sẽ tự động giải phóng CPU và đi ngủ (`wait`) cho đến khi có một luồng khác thực hiện xong việc và phát tín hiệu đánh thức nó dậy (`signal` hoặc `broadcast`).
* **4. Spinlock (Khóa quay vòng):**
  * *Cơ chế:* Khác với Mutex (bắt luồng đi ngủ), Spinlock bắt luồng phải chạy một vòng lặp liên tục để kiểm tra xem khóa đã mở chưa (Busy-waiting).
  * *Ứng dụng:* Dành cho các tác vụ khóa cực kỳ ngắn trong nhân hệ điều hành (Kernel) để đỡ tốn chi phí đổi ngữ cảnh (Context switch).
* **5. RW Lock (Read-Write Lock - Khóa đọc/ghi):**
  * *Cơ chế:* Cho phép **nhiều luồng cùng đọc dữ liệu một lúc** mà không bị khóa. Nhưng khi có **1 luồng muốn ghi**, tất cả luồng đọc và ghi khác đều bị chặn lại.
* **6. Barrier (Rào chắn / Điểm hẹn):**
  * *Cơ chế:* Điểm dừng chân đồng bộ cho một nhóm luồng. Bất kể luồng nào tính toán xong trước đều phải đứng chờ tại Barrier; chỉ khi toàn bộ các luồng trong nhóm đều tới đích thì rào chắn mới mở để tất cả cùng đi tiếp.