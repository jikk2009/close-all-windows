"""生成「关窗」的原创图标（暖色系）。

设计：暖橙渐变圆角方块 + 白色窗口轮廓 + 右下角红色关闭角标。
不依赖任何外部素材，纯代码绘制，随仓库一起以 MIT 许可发布。

用法：
    python build/make-icon.py
需要 Pillow（pip install pillow）。
输出：
    assets/closeall.ico       多尺寸图标（16~256）
    assets/icon-preview.png   256x256 预览图
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")

S = 1024
M = 36          # 外边距
R = 208         # 圆角半径

TOP = (255, 206, 128)      # 暖黄
BOTTOM = (255, 106, 74)    # 珊瑚橙红
INK = (255, 255, 255)      # 窗口线条
BADGE = (214, 51, 45)      # 关闭角标红


def diagonal_gradient(size, c1, c2):
    """从左上到右下的线性渐变。"""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return img


def rounded_mask(size, margin, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [margin, margin, size - margin, size - margin], radius=radius, fill=255)
    return mask


def build():
    mask = rounded_mask(S, M, R)
    bg = diagonal_gradient(S, TOP, BOTTOM)

    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    img.paste(bg, (0, 0), mask)

    d = ImageDraw.Draw(img)

    # ---- 窗口 ----
    left, top, right, bottom = 196, 232, 800, 704
    d.rounded_rectangle([left, top, right, bottom], radius=46,
                        outline=INK, width=42)
    # 标题栏分隔线
    bar_y = top + 124
    d.line([(left + 12, bar_y), (right - 12, bar_y)], fill=INK, width=32)
    # 标题栏左侧小圆点
    d.ellipse([left + 52, top + 40, left + 100, top + 88], fill=INK)

    # ---- 右下角关闭角标 ----
    cx, cy, r = 748, 730, 168
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=BADGE, outline=INK, width=26)

    arm, w = 74, 62
    for sx, sy in ((1, 1), (1, -1)):
        d.line([(cx - arm * sx, cy - arm * sy), (cx + arm * sx, cy + arm * sy)],
               fill=INK, width=w)
    for px, py in ((cx - arm, cy - arm), (cx + arm, cy + arm),
                   (cx - arm, cy + arm), (cx + arm, cy - arm)):
        rr = w // 2
        d.ellipse([px - rr, py - rr, px + rr, py + rr], fill=INK)

    os.makedirs(ASSETS, exist_ok=True)
    img.resize((256, 256), Image.LANCZOS).save(os.path.join(ASSETS, "icon-preview.png"))
    img.save(os.path.join(ASSETS, "closeall.ico"), format="ICO",
             sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48),
                    (64, 64), (96, 96), (128, 128), (256, 256)])
    print("ok ->", ASSETS)


if __name__ == "__main__":
    build()
