import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms
import os

# 1. Định nghĩa cấu trúc mạng LeNet-5 (Tương thích ảnh 28x28)
class LeNet5(nn.Module):
    def __init__(self):
        super().__init__()
        # Thêm padding=2 để ảnh 28x28 thành 32x32 ảo, vừa vặn với LeNet-5 gốc
        self.conv1 = nn.Conv2d(1, 6, kernel_size=5, padding=2)
        self.pool = nn.MaxPool2d(2, 2)
        self.conv2 = nn.Conv2d(6, 16, kernel_size=5)
        self.fc1 = nn.Linear(16 * 5 * 5, 120)
        self.fc2 = nn.Linear(120, 84)
        self.fc3 = nn.Linear(84, 10)

    def forward(self, x):
        x = self.pool(torch.relu(self.conv1(x)))
        x = self.pool(torch.relu(self.conv2(x)))
        x = torch.flatten(x, 1)
        x = torch.relu(self.fc1(x))
        x = torch.relu(self.fc2(x))
        x = self.fc3(x)
        return x

def train_and_export():
    print("[INFO] Đang tải MNIST Dataset để huấn luyện...")
    transform = transforms.Compose([transforms.ToTensor()])
    train_data = datasets.MNIST(root='./data', train=True, download=True, transform=transform)
    train_loader = torch.utils.data.DataLoader(train_data, batch_size=64, shuffle=True)

    model = LeNet5()
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001)

    print("[INFO] Bắt đầu huấn luyện (1 Epoch)...")
    model.train()
    for batch_idx, (data, target) in enumerate(train_loader):
        optimizer.zero_grad()
        output = model(data)
        loss = criterion(output, target)
        loss.backward()
        optimizer.step()
        if batch_idx % 200 == 0:
            print(f"Tiến độ: [{batch_idx * len(data)}/60000] - Loss: {loss.item():.4f}")

    # Xuất ra định dạng ONNX chuẩn công nghiệp
    print("[INFO] Hoàn tất huấn luyện. Đang xuất file ONNX...")
    dummy_input = torch.randn(1, 1, 28, 28)
    onnx_path = "models/lenet5.onnx"
    torch.onnx.export(model, dummy_input, onnx_path, 
                      input_names=['input'], output_names=['output'])
    print(f"[OK] Đã lưu file mô hình tại: {onnx_path}")

if __name__ == "__main__":
    train_and_export()
