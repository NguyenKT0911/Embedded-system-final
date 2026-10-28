#include <iostream>
#include <fcntl.h>
#include <termios.h>
#include <unistd.h>
#include <onnxruntime_cxx_api.h>
#include <opencv2/opencv.hpp>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <chrono>

// Các biến dùng chung và cơ chế đồng bộ hóa (Synchronization)
std::mutex mtx;
std::condition_variable cond_var;
bool trigger_ai = false;
int uart_fd = -1;

// Luồng 1: Lắng nghe ngắt phần cứng (I/O Thread)
void uart_listener() {
    char rx_buffer[1];
    while (true) {
        if (read(uart_fd, rx_buffer, 1) > 0 && (rx_buffer[0] == 'n' || rx_buffer[0] == 'N')) {
            std::cout << "\n[EVENT] Nhan ngat hardware. Danh thuc luong AI...\n";
            {
                std::lock_guard<std::mutex> lock(mtx);
                trigger_ai = true;
            }
            cond_var.notify_one(); // Gửi tín hiệu đánh thức
        }
    }
}

int main() {
    std::cout << std::unitbuf; // Tắt đệm để IPC gửi log lên GUI ngay lập tức
    std::cout << "[INFO] Khoi tao kien truc AI Da luong (Multithreading)...\n";
    
    Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "EdgeAI_Environment");
    Ort::SessionOptions session_options;
    session_options.SetIntraOpNumThreads(1);
    Ort::Session session(env, "models/mnist.onnx", session_options);
    
    uart_fd = open("/dev/ttyUSB0", O_RDWR | O_NOCTTY);
    if (uart_fd == -1) {
        std::cerr << "[ERROR] Khong the mo UART.\n";
        return 1;
    }

    struct termios tty;
    tcgetattr(uart_fd, &tty);
    cfsetospeed(&tty, B115200);
    cfsetispeed(&tty, B115200);
    tty.c_cflag |= (CLOCAL | CREAD | CS8);
    tty.c_cflag &= ~(PARENB | CSTOPB);
    tty.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
    tcsetattr(uart_fd, TCSANOW, &tty);
    std::cout << "[INFO] Ket noi UART thanh cong.\n";

    // Khởi động luồng song song
    std::thread listener(uart_listener);

    // Luồng chính: Xử lý AI (Compute Thread)
    while (true) {
        std::unique_lock<std::mutex> lock(mtx);
        cond_var.wait(lock, []{ return trigger_ai; }); // Đứng chờ tín hiệu từ luồng I/O
        trigger_ai = false;
        lock.unlock(); 

        // BẮT ĐẦU ĐO THỜI GIAN
        auto start_time = std::chrono::high_resolution_clock::now();

        cv::Mat img = cv::imread("images/sample.png", cv::IMREAD_GRAYSCALE);
        if (img.empty()) {
            std::cerr << "[ERROR] Khong tim thay ảnh.\n";
            continue;
        }
        cv::resize(img, img, cv::Size(28, 28));
        img.convertTo(img, CV_32F, 1.0 / 255.0); 

        std::vector<float> input_tensor_values(img.ptr<float>(), img.ptr<float>() + 28 * 28);
        std::vector<int64_t> input_dims = {1, 1, 28, 28};
        
        auto memory_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
        auto input_tensor = Ort::Value::CreateTensor<float>(
            memory_info, input_tensor_values.data(), input_tensor_values.size(), input_dims.data(), input_dims.size());

        const char* input_names[] = {"Input3"};
        const char* output_names[] = {"Plus214_Output_0"};
        auto output_tensors = session.Run(Ort::RunOptions{nullptr}, input_names, &input_tensor, 1, output_names, 1);
        
        float* floatarr = output_tensors.front().GetTensorMutableData<float>();
        int prediction = std::distance(floatarr, std::max_element(floatarr, floatarr + 10));
        
        // KẾT THÚC ĐO THỜI GIAN
        auto end_time = std::chrono::high_resolution_clock::now();
        std::chrono::duration<double, std::milli> inference_time = end_time - start_time;

        std::cout << "[RESULT] Mang AI phan loai hinh anh la so: " << prediction << "\n";
        std::cout << "[TIME] " << inference_time.count() << " ms\n"; // In định dạng để GUI bắt log
        
        char result = '0' + prediction;
        write(uart_fd, &result, 1);
    }
    
    listener.join();
    close(uart_fd);
    return 0;
}
