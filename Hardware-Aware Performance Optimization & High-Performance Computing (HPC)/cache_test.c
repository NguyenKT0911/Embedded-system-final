#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define N 10000 // Ma trận 10,000 x 10,000 (Khoảng 400MB)

double get_time() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main() {
    // Cấp phát mảng 1 chiều nhưng dùng như mảng 2 chiều (tránh tràn Stack)
    int *arr = (int *)malloc(N * N * sizeof(int));
    if (!arr) { printf("Memory allocation failed!\n"); return 1; }

    printf("Bat dau test Cache...\n");

    // --- TEST 1: DUYỆT THEO HÀNG (CACHE FRIENDLY) ---
    double start1 = get_time();
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            arr[i * N + j] = 1; // Duyệt các ô nhớ liền kề nhau
        }
    }
    double end1 = get_time();
    printf("1. Duyet theo HANG (Cache Hit): %f giay\n", end1 - start1);

    // --- TEST 2: DUYỆT THEO CỘT (CACHE UNFRIENDLY) ---
    double start2 = get_time();
    for (int j = 0; j < N; j++) {
        for (int i = 0; i < N; i++) {
            arr[i * N + j] = 2; // Nhảy cóc địa chỉ bộ nhớ liên tục
        }
    }
    double end2 = get_time();
    printf("2. Duyet theo COT (Cache Miss): %f giay\n", end2 - start2);

    free(arr);
    return 0;
}
