"""
言旅 Kotabi — App Icon Generator（浮世绘风格）
North-Hokusai inspired: 藍色 indigo sea · 朱色 vermilion sun · 白浪 white waves
"""
from PIL import Image, ImageDraw, ImageFont
import math, os, sys

SIZE = 1024
OUT  = r"d:\PROJECT\JapaneseLearn\mobile\assets\images\app_icon.png"

INDIGO       = ( 27,  58, 110)
INDIGO_DARK  = ( 13,  30,  60)
INDIGO_MID   = ( 45,  85, 150)
CREAM_SKY    = (252, 242, 205)
CREAM2       = (240, 220, 160)
VERMILION    = (192,  52,  28)
VERMILION_D  = (150,  35,  15)
BLACK        = ( 15,  15,  20)
WHITE        = (255, 255, 255)
FOAM         = (220, 238, 255)

def wave_y(x, base, amp, freq, phase=0.0):
    t = (x / SIZE) * 2 * math.pi * freq + phase
    return base - int(amp * (math.sin(t)*0.55 + math.sin(t*2.1)*0.3 + math.sin(t*0.5)*0.15))

def draw_sky(draw):
    sky_bottom = int(SIZE * 0.38)
    draw.rectangle([0, 0, SIZE, sky_bottom], fill=CREAM_SKY)
    draw.rectangle([0, sky_bottom, SIZE, sky_bottom + 14], fill=CREAM2)
    draw.rectangle([0, sky_bottom + 14, SIZE, SIZE], fill=INDIGO)

def draw_sun(draw):
    cx, cy = SIZE // 2, int(SIZE * 0.22)
    r = 155
    draw.ellipse([cx-r-8, cy-r-8, cx+r+8, cy+r+8], fill=VERMILION_D)
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=VERMILION)
    rh = 28
    draw.ellipse([cx-rh, cy-rh-20, cx+rh, cy+rh-20], fill=(220, 100, 70))

def draw_waves(draw):
    layers = [
        (0.62, 52, 2.0, 0.0,  INDIGO_MID,  FOAM),
        (0.71, 62, 1.7, 1.1,  INDIGO,      WHITE),
        (0.82, 72, 2.3, 2.4,  INDIGO_DARK, WHITE),
    ]
    for (base_r, amp, freq, phase, body_col, foam_col) in layers:
        base = int(SIZE * base_r)
        top_pts = [(x, wave_y(x, base, amp, freq, phase)) for x in range(0, SIZE + 1, 4)]
        poly = top_pts + [(SIZE, SIZE), (0, SIZE)]
        draw.polygon(poly, fill=body_col)
        for xi in range(0, SIZE, SIZE // 7):
            px = xi + int((SIZE // 14) * math.sin(phase + xi))
            py = wave_y(px, base, amp, freq, phase)
            claw_pts = [
                (px-28, py+10), (px, py-32), (px+28, py+10),
                (px+10, py+22), (px-10, py+22),
            ]
            draw.polygon(claw_pts, fill=foam_col)
            draw.line(claw_pts + [claw_pts[0]], fill=BLACK, width=2)
        pts_line = [(x, wave_y(x, base, amp, freq, phase)) for x in range(0, SIZE+1, 2)]
        draw.line(pts_line, fill=BLACK, width=2)

def find_cjk_font():
    for p in [r"C:\Windows\Fonts\msyhbd.ttc", r"C:\Windows\Fonts\msyh.ttc",
              r"C:\Windows\Fonts\simsun.ttc", r"C:\Windows\Fonts\simhei.ttf",
              r"C:\Windows\Fonts\msjh.ttc",   r"C:\Windows\Fonts\msgothic.ttc"]:
        if os.path.exists(p): return p
    return None

def find_latin_font():
    for p in [r"C:\Windows\Fonts\georgia.ttf", r"C:\Windows\Fonts\calibrib.ttf",
              r"C:\Windows\Fonts\calibri.ttf",  r"C:\Windows\Fonts\segoeui.ttf",
              r"C:\Windows\Fonts\arial.ttf"]:
        if os.path.exists(p): return p
    return None

def draw_kanji(draw, cjk_font_path, latin_font_path):
    font = ImageFont.truetype(cjk_font_path, 390)
    char = "言"
    bbox = draw.textbbox((0, 0), char, font=font)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    tx = (SIZE - tw) // 2 - bbox[0]
    ty = int(SIZE * 0.28) - bbox[1]
    for dx, dy in [(-6,-6),(6,-6),(-6,6),(6,6),(-7,0),(7,0),(0,-7),(0,7),
                   (-4,-4),(4,-4),(-4,4),(4,4)]:
        draw.text((tx+dx, ty+dy), char, font=font, fill=BLACK)
    draw.text((tx, ty), char, font=font, fill=WHITE)
    if latin_font_path:
        font_sub = ImageFont.truetype(latin_font_path, 64)
        sub = "Kotabi"
        sb  = draw.textbbox((0, 0), sub, font=font_sub)
        sw  = sb[2] - sb[0]
        sx  = (SIZE - sw) // 2 - sb[0]
        sy  = ty + th + bbox[1] + 18
        for dx, dy in [(-2,0),(2,0),(0,-2),(0,2)]:
            draw.text((sx+dx, sy+dy), sub, font=font_sub, fill=VERMILION_D)
        draw.text((sx, sy), sub, font=font_sub, fill=CREAM_SKY)

def draw_border(draw):
    m = 18
    draw.rectangle([m, m, SIZE-m, SIZE-m], outline=BLACK, width=5)
    draw.rectangle([m+10, m+10, SIZE-m-10, SIZE-m-10], outline=(50,50,60), width=2)

def main():
    print("生成言旅 Kotabi 浮世绘图标...")
    cjk   = find_cjk_font()
    latin = find_latin_font()
    if not cjk: sys.exit("找不到 CJK 字体")
    print(f"  CJK: {cjk}\n  Latin: {latin}")

    img  = Image.new("RGBA", (SIZE, SIZE), (0,0,0,255))
    draw = ImageDraw.Draw(img, "RGBA")

    draw_sky(draw)
    draw_sun(draw)
    draw_waves(draw)
    draw_kanji(draw, cjk, latin)
    draw_border(draw)

    mask = Image.new("L", (SIZE, SIZE), 0)
    md   = ImageDraw.Draw(mask)
    md.rounded_rectangle([0, 0, SIZE, SIZE], radius=180, fill=255)
    img.putalpha(mask)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, "PNG")
    print(f"✓ 图标已保存: {OUT}  尺寸: {img.size}")

if __name__ == "__main__":
    main()
