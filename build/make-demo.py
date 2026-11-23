"""生成 README 里的演示动画（示意图，非真实录屏）。

用 Pillow 逐帧绘制：桌面 → 光标点「关窗」→ 窗口依次缩小关闭 → 干净桌面。
刻意不用真实截屏，避免把桌面上的私人窗口/文件录进去。

用法：
    python build/make-demo.py
输出：
    assets/demo.gif
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "demo.gif")

W, H = 760, 420
TASKBAR = 46
BG_TOP = (36, 41, 55)
BG_BOTTOM = (17, 20, 28)
BAR = (11, 13, 18)

FONT = None
for _n in ("msyh.ttc", "msyhbd.ttc", "simhei.ttf"):
    _p = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts", _n)
    if os.path.exists(_p):
        FONT = _p
        break


def font(size):
    if FONT is None:
        return ImageFont.load_default()
    try:
        return ImageFont.truetype(FONT, size)
    except Exception:
        return ImageFont.load_default()


F_TITLE = font(13)
F_SMALL = font(11)
F_BIG = font(33)


def base_image():
    img = Image.new("RGB", (W, H), BG_BOTTOM)
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)],
               fill=tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)))
    return img


def draw_taskbar(d, pressed=False):
    d.rectangle([0, H - TASKBAR, W, H], fill=BAR)
    for i, col in enumerate([(70, 120, 200), (90, 160, 110), (170, 110, 190)]):
        d.rounded_rectangle([28 + i * 46, H - TASKBAR + 11, 58 + i * 46, H - TASKBAR + 35],
                            radius=6, fill=col)
    cx, cy, s = W - 40, H - TASKBAR / 2, 30
    ix0, iy0 = cx - s / 2, cy - s / 2
    ix1, iy1 = cx + s / 2, cy + s / 2
    d.rounded_rectangle([ix0, iy0, ix1, iy1], radius=s * 0.24, fill=(255, 176, 110))
    d.rounded_rectangle([ix0, iy0 + s * 0.44, ix1 - 1, iy1 - 1], radius=s * 0.2, fill=(255, 118, 86))
    d.rounded_rectangle([ix0 + s * 0.20, iy0 + s * 0.22, ix0 + s * 0.72, iy0 + s * 0.60],
                        radius=2, outline=(255, 255, 255), width=2)
    br = s * 0.17
    bx, by = ix0 + s * 0.73, iy0 + s * 0.73
    d.ellipse([bx - br, by - br, bx + br, by + br], fill=(214, 51, 45), outline=(255, 255, 255), width=1)
    a = br * 0.5
    d.line([(bx - a, by - a), (bx + a, by + a)], fill=(255, 255, 255), width=2)
    d.line([(bx - a, by + a), (bx + a, by - a)], fill=(255, 255, 255), width=2)
    if pressed:
        d.ellipse([cx - 25, cy - 25, cx + 25, cy + 25], outline=(255, 214, 170), width=2)


WINDOWS = [
    dict(box=(40, 26, 366, 186), title="未命名 - 记事本", body="summary.txt",
         fill=(247, 249, 251), kind="text"),
    dict(box=(394, 26, 720, 186), title="新标签页 - Google Chrome", body="github.com",
         fill=(238, 241, 246), kind="chrome"),
    dict(box=(40, 200, 366, 348), title="下载 - 文件资源管理器", body="",
         fill=(252, 250, 247), kind="files"),
    dict(box=(394, 200, 720, 348), title="微信", body="",
         fill=(240, 244, 240), kind="chat"),
]


def window_image(w):
    """把单个窗口画成一张独立的小图（局部坐标）。"""
    x0, y0, x1, y1 = w["box"]
    ww, hh = x1 - x0, y1 - y0
    im = Image.new("RGBA", (ww, hh), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, ww - 1, hh - 1], radius=9, fill=w["fill"] + (255,),
                        outline=(96, 102, 116), width=1)
    d.rectangle([1, 1, ww - 2, 26], fill=(235, 238, 244))
    d.text((11, 6), w["title"], font=F_TITLE, fill=(30, 34, 44))
    for i in range(3):
        cxx = ww - 15 - i * 13
        d.ellipse([cxx - 3, 10, cxx + 3, 16], fill=(158, 166, 178))

    if w["body"]:
        d.text((14, 44), w["body"], font=F_SMALL, fill=(124, 132, 144))

    if w["kind"] == "files":
        d.rounded_rectangle([14, 46, 60, 92], radius=4, fill=(255, 206, 122))
        d.rounded_rectangle([70, 46, 116, 92], radius=4, fill=(152, 200, 255))
        for i in range(3):
            d.rounded_rectangle([14, 104 + i * 12, 150 - i * 22, 110 + i * 12],
                                radius=3, fill=(224, 228, 234))
    if w["kind"] == "chat":
        for i in range(3):
            yy = 52 + i * 30
            d.rounded_rectangle([14, yy, ww - 80 - i * 10, yy + 18], radius=9, fill=(210, 226, 210))
    if w["kind"] == "chrome":
        d.rounded_rectangle([14, 44, ww - 14, 60], radius=8, fill=(228, 232, 238))
    return im


def cursor_points(x, y):
    return [(x, y), (x, y + 18), (x + 5, y + 13), (x + 9, y + 21),
            (x + 13, y + 19), (x + 9, y + 11), (x + 16, y + 10)]


def build_frames():
    wins = [(w, window_image(w)) for w in WINDOWS]
    frames = []
    sx, sy = 360, 300
    tx, ty = W - 40, H - TASKBAR / 2

    for f in range(32):
        img = base_image().convert("RGBA")
        d = ImageDraw.Draw(img)

        # 窗口：f < start 时完整显示；之后 4 帧内缩小到消失
        for i, (w, wim) in enumerate(wins):
            start = 11 + i * 3
            if f < start:
                scale = 1.0
            else:
                t = min(1.0, (f - start) / 4.0)
                scale = 1.0 - t * t          # 先慢后快，像窗口"关掉"
            if scale <= 0.04:
                continue
            x0, y0, x1, y1 = w["box"]
            cw, ch = x1 - x0, y1 - y0
            nw, nh = max(1, int(cw * scale)), max(1, int(ch * scale))
            scaled = wim.resize((nw, nh), Image.LANCZOS)
            px = x0 + (cw - nw) // 2
            py = y0 + (ch - nh) // 2
            img.alpha_composite(scaled, (px, py))

        draw_taskbar(d, pressed=(f in (10, 11)))

        # 光标
        if f <= 5:
            cx, cy = sx, sy
        elif f <= 9:
            t = (f - 5) / 4.0
            cx, cy = sx + (tx - sx) * t, sy + (ty - sy) * t
        elif f <= 12:
            cx, cy = tx, ty - 3
        else:
            t = min(1.0, (f - 12) / 8.0)
            cx, cy = tx + (sx - tx) * t, ty + (sy - ty) * t
        d.polygon(cursor_points(cx, cy), fill=(255, 255, 255), outline=(20, 20, 20))

        # 结尾文字
        if f >= 25:
            k = min(1.0, (f - 25) / 3.0)
            col = (int(45 + 210 * k), int(45 + 190 * k), int(50 + 170 * k))
            txt = "1.2 秒 · 全部关闭"
            tw = d.textlength(txt, font=F_BIG)
            d.text(((W - tw) / 2, H / 2 - 34), txt, font=F_BIG, fill=col)

        frames.append(img.convert("RGB"))
    return frames


def main():
    frames = build_frames()
    pal = [f.convert("P", palette=Image.ADAPTIVE, colors=128) for f in frames]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    pal[0].save(OUT, save_all=True, append_images=pal[1:], duration=100, loop=0, optimize=True)
    print("ok ->", OUT, os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    main()
