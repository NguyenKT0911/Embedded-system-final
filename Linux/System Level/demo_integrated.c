#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/types.h>
#include <sys/wait.h>

#define NUM_ITEMS 4

// ==========================================
// MỤC 3: SYNCHRONIZATION - KHAI BÁO MUTEX
// ==========================================
pthread_mutex_t my_lock;
int total_shared_sum = 0; // Biến dùng chung (Shared Resource)

typedef struct {
    int worker_id;
    int value;
} WorkerArg;

// ==========================================
// MỤC 8: MULTI-THREAD - HÀM XỬ LÝ SONG SONG
// ==========================================
void* worker_function(void* arg) {
    WorkerArg* data = (WorkerArg*)arg;

    printf("[Worker Thread %d] Đang xử lý giá trị nhận được: %d\n", 
           data->worker_id, data->value);
    sleep(30); // Giả lập công việc tính toán tốn thời gian

    // KHÓA ĐỘC QUYỀN - BẢO VỆ VÙNG TRANH CHẤP (CRITICAL SECTION)
    pthread_mutex_lock(&my_lock);
    total_shared_sum += data->value;
    printf("[Worker Thread %d] Đã cập nhật tổng chung: %d\n", 
           data->worker_id, total_shared_sum);
    pthread_mutex_unlock(&my_lock);

    free(data);
    return NULL;
}

int main() {
    int pipe_channel[2]; // Kênh IPC Pipe: pipe_channel[0] đọc, [1] ghi

    // ==========================================
    // MỤC 2: IPC - TẠO KÊNH PIPE
    // ==========================================
    if (pipe(pipe_channel) == -1) {
        perror("Lỗi tạo pipe");
        return 1;
    }

    pid_t pid = fork(); // Tạo tiến trình Cha và Con độc lập

    if (pid < 0) {
        perror("Lỗi fork");
        return 1;
    }

    if (pid > 0) {
        // --------------------------------------------------
        // TIẾN TRÌNH CHA: ĐÓNG VAI TRÒ PRODUCER
        // --------------------------------------------------
        close(pipe_channel[0]); // Cha chỉ ghi, đóng đầu đọc
        printf("\n>>> [CHA - PID %d] Bắt đầu gửi dữ liệu qua Pipe...\n", getpid());

        for (int i = 1; i <= NUM_ITEMS; i++) {
            int send_val = i * 20;
            printf("[CHA] Đẩy số %d vào Pipe\n", send_val);
            write(pipe_channel[1], &send_val, sizeof(int));
            sleep(1); // Gửi tuần tự từng giây
        }

        close(pipe_channel[1]); // Báo cho tiến trình con biết đã hết dữ liệu
        wait(NULL);            // Chờ con dọn dẹp xong rồi mới thoát
        printf(">>> [CHA] Hoàn thành và thoát sạch sẽ.\n");
    } 
    else {
        // --------------------------------------------------
        // TIẾN TRÌNH CON: ĐÓNG VAI TRÒ CONSUMER + MULTI-THREAD
        // --------------------------------------------------
        close(pipe_channel[1]); // Con chỉ đọc, đóng đầu ghi
        pthread_t threads[NUM_ITEMS];
        pthread_mutex_init(&my_lock, NULL); // Khởi tạo ổ khóa

        printf("\n>>> [CON - PID %d] Đang đợi nhận dữ liệu từ Pipe...\n", getpid());

        int recv_val;
        int count = 0;

        // Đọc liên tục từ đường ống Pipe (IPC)
        while (read(pipe_channel[0], &recv_val, sizeof(int)) > 0) {
            WorkerArg* arg = (WorkerArg*)malloc(sizeof(WorkerArg));
            arg->worker_id = count + 1;
            arg->value = recv_val;

            // Kích hoạt luồng chạy tính toán song song
            pthread_create(&threads[count], NULL, worker_function, (void*)arg);
            count++;
        }
        close(pipe_channel[0]); // Đóng đầu đọc

        // Đồng bộ: Chờ tất cả Worker chạy xong
        for (int i = 0; i < count; i++) {
            pthread_join(threads[i], NULL);
        }

        pthread_mutex_destroy(&my_lock); // Xóa ổ khóa sau khi dùng xong
        printf(">>> [CON] Tổng số tính được = %d\n", total_shared_sum);

        // Giữ tiến trình chạy thêm 15 giây để kịp xem htop và chụp màn hình
        printf(">>> [CON] Đang giữ trạng thái 15s để kiểm tra tài nguyên...\n");
        sleep(15);
        exit(0);
    }

    return 0;
}

