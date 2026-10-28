from pathlib import Path

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "raw"
OUT_DIR = ROOT / "processed"

OUT_DIR.mkdir(parents=True, exist_ok=True)


def preprocess_digit(image_path: Path, target_stroke_px: float = 2.0) -> np.ndarray:
    """
    Tiền xử lý ảnh chữ số viết tay thô (raw) thành định dạng chuẩn MNIST 28x28:
    1. Làm sạch viền mép ảnh chụp (tránh vệt trắng/đen từ viền crop).
    2. Chuẩn hóa độ sáng bằng Gaussian division để khử bóng đổ mượt mà.
    3. Phân ngưỡng tự động Otsu để trích xuất nét chữ tự nhiên, chính xác.
    4. Hàn gắn các vi đứt đoạn bằng Morphological Closing.
    5. Lọc nhiễu thông minh bằng Connected Components, giữ toàn bộ nét chữ.
    6. Tự động chuẩn hóa độ dày nét (Stroke Width Normalization) để nét bút bi mảnh
       đạt độ dày chuẩn MNIST (xấp xỉ 2.0 - 2.5px trên canvas 28x28).
    7. Resize giữ tỷ lệ khung hình vào ô 20x20.
    8. Đặt vào canvas 28x28 và căn giữa theo trọng tâm kết hợp biên giới hạn (Bounded Centering).
    """
    # 1. Đọc ảnh grayscale
    gray = cv2.imread(str(image_path), cv2.IMREAD_GRAYSCALE)
    if gray is None:
        raise RuntimeError(f"Không thể đọc ảnh: {image_path}")

    # 2. Khử vệt mép ảnh chụp do crop/scan viền
    margin = 4
    if gray.shape[0] > 2 * margin and gray.shape[1] > 2 * margin:
        gray[:margin, :] = gray[margin:margin + 1, :]
        gray[-margin:, :] = gray[-margin - 1:-margin, :]
        gray[:, :margin] = gray[:, margin:margin + 1]
        gray[:, -margin:] = gray[:, -margin - 1:-margin]

    # 3. Khử bóng đổ và cân bằng ánh sáng bằng Gaussian Background Division
    sigma = max(gray.shape) / 12.0
    blur_bg = cv2.GaussianBlur(gray, (0, 0), sigmaX=sigma, sigmaY=sigma)
    norm = cv2.divide(gray, blur_bg, scale=255)

    # 4. Làm mượt nhẹ và phân ngưỡng tự động Otsu
    blur = cv2.GaussianBlur(norm, (5, 5), 0)
    _, bw = cv2.threshold(blur, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

    # 5. Hàn gắn các vi đứt đoạn trên nét bút
    bw = cv2.morphologyEx(
        bw,
        cv2.MORPH_CLOSE,
        cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    )

    # 6. Xóa nhiễu ở sát viền ảnh
    bw[:2, :] = 0
    bw[-2:, :] = 0
    bw[:, :2] = 0
    bw[:, -2:] = 0

    # 7. Tìm connected components
    n_labels, labels, stats, _ = cv2.connectedComponentsWithStats(
        bw,
        connectivity=8
    )

    if n_labels <= 1:
        raise RuntimeError(f"Không tìm thấy chữ số: {image_path}")

    components = []
    for label in range(1, n_labels):
        x, y, comp_w, comp_h, area = stats[label]
        if area >= 15:
            components.append((area, label, x, y, comp_w, comp_h))

    if not components:
        raise RuntimeError(f"Không tìm thấy component hợp lệ: {image_path}")

    components.sort(reverse=True)
    max_area = components[0][0]

    # Giữ các nét thuộc chữ số
    selected = [
        c for c in components
        if c[0] >= max(30, 0.015 * max_area)
    ]

    clean = np.zeros_like(bw)
    xs, ys, x2s, y2s = [], [], [], []

    for area, label, x, y, comp_w, comp_h in selected:
        clean[labels == label] = 255
        xs.append(x)
        ys.append(y)
        x2s.append(x + comp_w - 1)
        y2s.append(y + comp_h - 1)

    # 8. Crop đúng vùng bao chữ số
    x1 = min(xs)
    y1 = min(ys)
    x2 = max(x2s)
    y2 = max(y2s)

    digit = clean[y1:y2 + 1, x1:x2 + 1]
    dh, dw = digit.shape
    scale = 20.0 / max(dh, dw)

    # 9. Tự động chuẩn hóa độ dày nét chữ (Stroke Width Normalization)
    dist = cv2.distanceTransform(digit, cv2.DIST_L2, 3)
    if np.sum(dist > 0) > 0:
        stroke_width_raw = 2.0 * float(np.mean(dist[dist > 0]))
        projected_stroke = stroke_width_raw * scale
        # Nếu nét bút ở ảnh gốc quá mảnh khi thu về 20x20 (< target_stroke_px), tự động giãn nét thích ứng
        if projected_stroke < target_stroke_px:
            needed_dilation = int(round((target_stroke_px - projected_stroke) / scale))
            if needed_dilation >= 2:
                # Giới hạn kernel dilation để tránh bít kín các lỗ hổng tự nhiên của số 6, 8, 9
                k = min(needed_dilation, max(2, int(max(dh, dw) * 0.02)))
                digit = cv2.dilate(digit, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k)))
                dh, dw = digit.shape
                scale = 20.0 / max(dh, dw)

    # 10. Resize giữ tỷ lệ nằm trong khung 20x20
    new_w = max(1, round(dw * scale))
    new_h = max(1, round(dh * scale))

    digit_resized = cv2.resize(
        digit,
        (new_w, new_h),
        interpolation=cv2.INTER_AREA
    )

    # 11. Đặt vào Canvas 28x28 nền đen
    canvas = np.zeros((28, 28), dtype=np.uint8)
    ox = (28 - new_w) // 2
    oy = (28 - new_h) // 2
    canvas[oy:oy + new_h, ox:ox + new_w] = digit_resized

    # 12. Căn giữa theo trọng tâm kết hợp giới hạn độ lệch (Bounded Center of Mass)
    moments = cv2.moments(canvas)
    if moments["m00"] != 0:
        cx = moments["m10"] / moments["m00"]
        cy = moments["m01"] / moments["m00"]
        # Giới hạn độ dịch trong khoảng [-2, 2] để tránh làm lệch tâm hình học
        dx = int(np.clip(round(13.5 - cx), -2, 2))
        dy = int(np.clip(round(13.5 - cy), -2, 2))

        M = np.float32([
            [1, 0, dx],
            [0, 1, dy]
        ])

        canvas = cv2.warpAffine(
            canvas,
            M,
            (28, 28),
            borderValue=0
        )

    # Chuẩn hóa dải giá trị [0, 255]
    if canvas.max() > 0:
        canvas = cv2.normalize(
            canvas,
            None,
            0,
            255,
            cv2.NORM_MINMAX
        )

    return canvas


def main():
    total = 0

    for label in range(10):
        src_dir = RAW_DIR / str(label)
        dst_dir = OUT_DIR / str(label)

        dst_dir.mkdir(parents=True, exist_ok=True)

        for image_path in sorted(src_dir.glob("*.*")):
            if image_path.suffix.lower() not in {
                ".jpg",
                ".jpeg",
                ".png",
                ".bmp"
            }:
                continue

            output = preprocess_digit(image_path)
            out_path = dst_dir / f"{image_path.stem}.png"

            cv2.imwrite(str(out_path), output)
            print(f"[OK] {image_path.parent.name}/{image_path.name} -> {dst_dir.name}/{out_path.name}")
            total += 1

    print()
    print(f"Processed successfully: {total} digit images with stroke normalization (MNIST format 28x28).")


if __name__ == "__main__":
    main()