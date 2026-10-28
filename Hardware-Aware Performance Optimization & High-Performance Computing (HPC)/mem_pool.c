#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define ITERATIONS 30000          // 30,000 vòng lặp
#define TENSOR_SIZE (256 * 1024)   // Kích thước 256KB cho mỗi Tensor

double get_time() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main() {
    printf("Bat dau test Memory Allocation...\n");
    volatile long dummy_checksum = 0; // Biến volatile ép CPU không được bỏ qua tính toán

    // --- TEST 1: BAD PRACTICE (XIN / TRA LIEN TUC) ---
    double start1 = get_time();
    for (int i = 0; i < ITERATIONS; i++) {
        char *tensor = (char *)malloc(TENSOR_SIZE);
        if (tensor) {
            // Ghi dữ liệu vào đầu và cuối để ép OS cấp trang nhớ vật lý (Page Fault)
            tensor[0] = (char)(i & 0xFF);
            tensor[TENSOR_SIZE - 1] = (char)((i + 1) & 0xFF);
            dummy_checksum += tensor[0] + tensor[TENSOR_SIZE - 1];
            free(tensor);
        }
    }
    double end1 = get_time();
    printf("1. Xin/Tra lien tuc (Bad Practice): %f giay\n", end1 - start1);

    // --- TEST 2: GOOD PRACTICE (MEMORY POOL & REUSE) ---
    double start2 = get_time();
    char *memory_pool = (char *)malloc(TENSOR_SIZE); // Cấp phát duy nhất 1 lần
    if (memory_pool) {
        for (int i = 0; i < ITERATIONS; i++) {
            // Tái sử dụng vùng đệm có sẵn
            memory_pool[0] = (char)(i & 0xFF);
            memory_pool[TENSOR_SIZE - 1] = (char)((i + 1) & 0xFF);
            dummy_checksum += memory_pool[0] + memory_pool[TENSOR_SIZE - 1];
        }
        free(memory_pool); // Giải phóng 1 lần duy nhất
    }
    double end2 = get_time();
    printf("2. Memory Pool (Good Practice) : %f giay\n", end2 - start2);

    return 0;
}
