import sys, os, random, shutil
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                             QHBoxLayout, QLabel, QPushButton, QTextEdit, QFrame, QGridLayout)
from PyQt5.QtGui import QFont, QPixmap, QColor
from PyQt5.QtCore import QProcess, Qt

class EdgeAIDashboard(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Edge AI Accelerator (OS Optimized)")
        self.setGeometry(100, 100, 1000, 700)
        self.setStyleSheet("background-color: #1e1e1e; color: #ffffff;")
        
        main_widget = QWidget()
        self.setCentralWidget(main_widget)
        layout = QVBoxLayout(main_widget)
        
        # --- HEADER ---
        header = QLabel("RISC-V / Edge AI Accelerator Dashboard")
        header.setFont(QFont("Segoe UI", 18, QFont.Bold))
        header.setAlignment(Qt.AlignCenter)
        header.setStyleSheet("background-color: #007acc; padding: 15px; border-radius: 5px;")
        layout.addWidget(header)
        
        # --- GRID LAYOUT ---
        grid = QGridLayout()
        
        # 1. Image Panel
        self.img_display = QLabel("No Image")
        self.img_display.setStyleSheet("border: 2px solid #333; background: #000;")
        self.img_display.setFixedSize(250, 250)
        self.img_display.setScaledContents(True)
        grid.addWidget(QLabel("<b>1. Sample Image (MNIST)</b>"), 0, 0)
        grid.addWidget(self.img_display, 1, 0, 3, 1)
        
        btn_random = QPushButton("🎲 Load Random Sample")
        btn_random.setStyleSheet("background-color: #333; padding: 10px; border-radius: 5px;")
        btn_random.clicked.connect(self.load_random_image)
        grid.addWidget(btn_random, 4, 0)

        # 2. Results Panel
        self.lbl_result = QLabel("--")
        self.lbl_result.setFont(QFont("Segoe UI", 48, QFont.Bold))
        self.lbl_result.setStyleSheet("color: #4CAF50;")
        self.lbl_result.setAlignment(Qt.AlignCenter)
        grid.addWidget(QLabel("<b>2. Inference Result</b>"), 0, 1)
        grid.addWidget(self.lbl_result, 1, 1)
        
        # 3. Timing Information (NEW)
        self.lbl_time = QLabel("0.0 ms")
        self.lbl_time.setFont(QFont("Segoe UI", 24, QFont.Bold))
        self.lbl_time.setStyleSheet("color: #FF9800;")
        self.lbl_time.setAlignment(Qt.AlignCenter)
        grid.addWidget(QLabel("<b>3. Execution Time (OS Optimized)</b>"), 2, 1)
        grid.addWidget(self.lbl_time, 3, 1)
        
        layout.addLayout(grid)
        
        # --- CONTROL & LOGS ---
        btn_run = QPushButton("▶ Khởi động AI Core (Multithreading)")
        btn_run.setStyleSheet("background-color: #d84315; color: white; padding: 15px; font-weight: bold; font-size: 14px; border-radius: 5px;")
        btn_run.clicked.connect(self.start_cpp_core)
        layout.addWidget(btn_run)
        
        layout.addWidget(QLabel("<b>4. System Console Log</b>"))
        self.console = QTextEdit()
        self.console.setReadOnly(True)
        self.console.setStyleSheet("background-color: #000000; color: #00FF00; font-family: Consolas;")
        layout.addWidget(self.console)
        
        self.process = QProcess(self)
        self.process.readyReadStandardOutput.connect(self.handle_stdout)
        self.load_random_image()

    def load_random_image(self):
        image_dir = "images"
        if not os.path.exists(image_dir): return
        image_files = [f for f in os.listdir(image_dir) if f.endswith(('.png', '.jpg')) and f != "sample.png"]
        if not image_files: return
        
        random_file = random.choice(image_files)
        src_path = os.path.join(image_dir, random_file)
        dest_path = os.path.join(image_dir, "sample.png")
        shutil.copyfile(src_path, dest_path)
        
        self.img_display.setPixmap(QPixmap(dest_path))
        self.console.append(f"[GUI] Da nap anh: {random_file}")

    def start_cpp_core(self):
        self.console.append("[GUI] Đang khởi động Core...")
        env = self.process.processEnvironment()
        env.insert("LD_LIBRARY_PATH", "./onnxruntime/lib:" + env.value("LD_LIBRARY_PATH", ""))
        self.process.setProcessEnvironment(env)
        self.process.start("./edge_ai_core")

    def handle_stdout(self):
        data = self.process.readAllStandardOutput().data().decode().strip()
        for line in data.split('\n'):
            if line:
                self.console.append(line)
                if "[RESULT]" in line:
                    num = line.split("so: ")[1].strip()
                    self.lbl_result.setText(f"{num}")
                elif "[TIME]" in line:
                    time_val = line.replace("[TIME]", "").strip()
                    self.lbl_time.setText(time_val)

if __name__ == '__main__':
    app = QApplication(sys.argv)
    window = EdgeAIDashboard()
    window.show()
    sys.exit(app.exec_())
