#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <omp.h> // Thư viện OpenMP cho Đa luồng

#define SIZE 1024 // Nhân 2 ma trận 1024x1024

double get_time() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main() {
    // Khởi tạo 3 ma trận: A, B, và Result (C)
    float *A = (float *)malloc(SIZE * SIZE * sizeof(float));
    float *B = (float *)malloc(SIZE * SIZE * sizeof(float));
    float *C = (float *)malloc(SIZE * SIZE * sizeof(float));

    // Fill data ngẫu nhiên
    for(int i=0; i<SIZE*SIZE; i++) { A[i]=1.0f; B[i]=2.0f; C[i]=0.0f; }

    printf("Bat dau nhan ma tran %dx%d...\n", SIZE, SIZE);
    double start = get_time();

    // Dòng bùa chú của OpenMP: Ép vòng lặp chạy đa luồng
    #pragma omp parallel for
    for (int i = 0; i < SIZE; i++) {
        for (int k = 0; k < SIZE; k++) {
            float r = A[i * SIZE + k];
            for (int j = 0; j < SIZE; j++) {
                C[i * SIZE + j] += r * B[k * SIZE + j]; // Duyệt B theo hàng (Cache Hit liên tục)
            }
        }
    }

    double end = get_time();
    printf("Thoi gian hoan thanh: %f giay\n", end - start);

    free(A); free(B); free(C);
    return 0;
}
