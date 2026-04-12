"""
Apple App Store 截图生成器
支持所有 Apple 要求的设备尺寸，可批量生成多种尺寸截图。

用法:
  python gen_appstore_screenshots.py --input screenshots/ --output output/
  python gen_appstore_screenshots.py --input screenshots/ --output output/ --devices iphone67 iphone65 ipad129
  python gen_appstore_screenshots.py --input screenshots/ --output output/ --bg "#1a1a2e" --title "日语学习"
  python gen_appstore_screenshots.py --list-devices

依赖: pip install Pillow
"""

import argparse
import os
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# ============================================================
# Apple App Store 所有要求的截图尺寸 (宽 x 高, 竖屏)
# ============================================================
DEVICE_SPECS = {
    # iPhone
    "iphone67": {
        "name": "iPhone 6.7\" (15 Pro Max / 16 Pro Max)",
        "size": (1320, 2868),
        "category": "iPhone",
    },
    "iphone65": {
        "name": "iPhone 6.5\" (11 Pro Max / XS Max)",
        "size": (1242, 2688),
        "category": "iPhone",
    },
    "iphone61_super_retina": {
        "name": "iPhone 6.1\" Super Retina (14 Pro / 15 Pro)",
        "size": (1206, 2622),
        "category": "iPhone",
    },
    "iphone61": {
        "name": "iPhone 6.1\" (11 / XR)",
        "size": (1170, 2532),
        "category": "iPhone",
    },
    "iphone55": {
        "name": "iPhone 5.5\" (8 Plus / 7 Plus / 6s Plus)",
        "size": (1242, 2208),
        "category": "iPhone",
    },
    # iPad
    "ipad129": {
        "name": "iPad Pro 12.9\" (3rd gen+)",
        "size": (2048, 2732),
        "category": "iPad",
    },
    "ipad129_6th": {
        "name": "iPad Pro 12.9\" (6th gen) / iPad Pro M4",
        "size": (2064, 2752),
        "category": "iPad",
    },
    "ipad11": {
        "name": "iPad Pro 11\"",
        "size": (1668, 2388),
        "category": "iPad",
    },
    "ipad109": {
        "name": "iPad 10.9\" (Air / 10th gen)",
        "size": (1640, 2360),
        "category": "iPad",
    },
    "ipad97": {
        "name": "iPad 9.7\"",
        "size": (1536, 2048),
        "category": "iPad",
    },
    # Apple Watch
    "watch_ultra": {
        "name": "Apple Watch Ultra (49mm)",
        "size": (410, 502),
        "category": "Watch",
    },
    "watch_series7_45": {
        "name": "Apple Watch Series 7+ (45mm)",
        "size": (396, 484),
        "category": "Watch",
    },
    "watch_series7_41": {
        "name": "Apple Watch Series 7+ (41mm)",
        "size": (352, 430),
        "category": "Watch",
    },
    # Mac
    "mac": {
        "name": "Mac",
        "size": (2880, 1800),
        "category": "Mac",
    },
    # Apple TV
    "apple_tv": {
        "name": "Apple TV",
        "size": (3840, 2160),
        "category": "TV",
    },
}

# 常用组合预设
PRESETS = {
    "iphone_all": ["iphone67", "iphone65", "iphone61", "iphone55"],
    "iphone_min": ["iphone67", "iphone55"],  # 最少需要的 iPhone 尺寸
    "ipad_all": ["ipad129", "ipad129_6th", "ipad11", "ipad109", "ipad97"],
    "ipad_min": ["ipad129", "ipad11"],
    "required": ["iphone67", "iphone65", "iphone55", "ipad129"],  # App Store 基本要求
}


def hex_to_rgb(hex_color: str) -> tuple:
    """将 hex 颜色转为 RGB 元组"""
    hex_color = hex_color.lstrip("#")
    if len(hex_color) == 3:
        hex_color = "".join(c * 2 for c in hex_color)
    return tuple(int(hex_color[i : i + 2], 16) for i in (0, 2, 4))


def find_font(preferred_size=60):
    """查找可用字体，优先中文字体"""
    font_candidates = [
        # Windows 中文字体
        "C:/Windows/Fonts/msyh.ttc",      # 微软雅黑
        "C:/Windows/Fonts/simhei.ttf",     # 黑体
        "C:/Windows/Fonts/simsun.ttc",     # 宋体
        # macOS 中文字体
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Light.ttc",
        # Linux
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        # 通用
        "C:/Windows/Fonts/arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for font_path in font_candidates:
        if os.path.exists(font_path):
            try:
                return ImageFont.truetype(font_path, preferred_size)
            except Exception:
                continue
    return ImageFont.load_default()


def generate_screenshot(
    source_path: str,
    target_size: tuple,
    output_path: str,
    bg_color: tuple = (26, 26, 46),
    title: str = None,
    subtitle: str = None,
    padding_ratio: float = 0.08,
    screenshot_ratio: float = 0.72,
    corner_radius: int = 40,
    shadow: bool = True,
    title_color: tuple = (255, 255, 255),
):
    """
    生成单张 App Store 截图

    Args:
        source_path: 源截图路径
        target_size: 目标尺寸 (宽, 高)
        output_path: 输出路径
        bg_color: 背景颜色 RGB
        title: 标题文字 (显示在截图上方)
        subtitle: 副标题文字
        padding_ratio: 内边距比例
        screenshot_ratio: 截图占画布高度比例 (有标题时)
        corner_radius: 截图圆角半径
        shadow: 是否添加阴影
        title_color: 标题颜色
    """
    target_w, target_h = target_size
    canvas = Image.new("RGB", (target_w, target_h), bg_color)

    # 加载源截图
    src = Image.open(source_path).convert("RGBA")

    padding = int(target_w * padding_ratio)

    if title:
        # 有标题: 截图在下方，标题在上方
        available_h = int(target_h * screenshot_ratio)
        title_area_h = target_h - available_h
    else:
        available_h = target_h - padding * 2
        title_area_h = 0

    available_w = target_w - padding * 2

    # 计算截图缩放
    src_w, src_h = src.size
    scale = min(available_w / src_w, available_h / src_h)
    new_w = int(src_w * scale)
    new_h = int(src_h * scale)
    src_resized = src.resize((new_w, new_h), Image.LANCZOS)

    # 添加圆角
    if corner_radius > 0:
        radius = int(corner_radius * scale)
        mask = Image.new("L", (new_w, new_h), 0)
        mask_draw = ImageDraw.Draw(mask)
        mask_draw.rounded_rectangle([(0, 0), (new_w - 1, new_h - 1)], radius=radius, fill=255)
        src_resized.putalpha(mask)

    # 计算截图位置 (水平居中)
    x = (target_w - new_w) // 2
    if title:
        y = title_area_h + (available_h - new_h) // 2
    else:
        y = (target_h - new_h) // 2

    # 添加阴影
    if shadow:
        shadow_offset = max(8, int(target_w * 0.005))
        shadow_blur = max(20, int(target_w * 0.015))
        shadow_img = Image.new("RGBA", (new_w + shadow_blur * 4, new_h + shadow_blur * 4), (0, 0, 0, 0))
        shadow_draw = ImageDraw.Draw(shadow_img)
        shadow_draw.rounded_rectangle(
            [(shadow_blur * 2, shadow_blur * 2),
             (shadow_blur * 2 + new_w - 1, shadow_blur * 2 + new_h - 1)],
            radius=int(corner_radius * scale) if corner_radius > 0 else 0,
            fill=(0, 0, 0, 80),
        )
        shadow_img = shadow_img.filter(ImageFilter.GaussianBlur(radius=shadow_blur))
        canvas.paste(
            shadow_img,
            (x - shadow_blur * 2 + shadow_offset, y - shadow_blur * 2 + shadow_offset),
            shadow_img,
        )

    # 粘贴截图
    canvas.paste(src_resized, (x, y), src_resized)

    # 绘制标题
    if title:
        draw = ImageDraw.Draw(canvas)
        title_font_size = int(target_w * 0.065)
        title_font = find_font(title_font_size)

        bbox = draw.textbbox((0, 0), title, font=title_font)
        tw = bbox[2] - bbox[0]
        tx = (target_w - tw) // 2
        ty = int(title_area_h * 0.3)
        draw.text((tx, ty), title, fill=title_color, font=title_font)

        if subtitle:
            sub_font_size = int(target_w * 0.04)
            sub_font = find_font(sub_font_size)
            bbox2 = draw.textbbox((0, 0), subtitle, font=sub_font)
            sw = bbox2[2] - bbox2[0]
            sx = (target_w - sw) // 2
            sy = ty + title_font_size + int(target_h * 0.02)
            sub_color = (*title_color[:3],) if len(title_color) == 3 else title_color
            # 稍微降低副标题透明度
            draw.text((sx, sy), subtitle, fill=sub_color, font=sub_font)

    # 输出
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    canvas.save(output_path, quality=95)


def process_batch(
    input_dir: str,
    output_dir: str,
    devices: list,
    bg_color: tuple = (26, 26, 46),
    title: str = None,
    subtitle: str = None,
    **kwargs,
):
    """批量处理目录中的截图"""
    input_path = Path(input_dir)
    output_path = Path(output_dir)

    # 支持的图片格式
    extensions = {".png", ".jpg", ".jpeg", ".webp"}
    images = sorted([f for f in input_path.iterdir() if f.suffix.lower() in extensions])

    if not images:
        print(f"错误: 在 {input_dir} 中未找到图片文件")
        sys.exit(1)

    print(f"找到 {len(images)} 张源截图")
    print(f"目标设备: {len(devices)} 种尺寸")
    print()

    total = len(images) * len(devices)
    count = 0

    for device_key in devices:
        spec = DEVICE_SPECS[device_key]
        device_dir = output_path / device_key
        device_dir.mkdir(parents=True, exist_ok=True)

        print(f"📱 {spec['name']} ({spec['size'][0]}x{spec['size'][1]})")

        for img_file in images:
            count += 1
            out_file = device_dir / f"{img_file.stem}.png"

            generate_screenshot(
                source_path=str(img_file),
                target_size=spec["size"],
                output_path=str(out_file),
                bg_color=bg_color,
                title=title,
                subtitle=subtitle,
                **kwargs,
            )
            print(f"  [{count}/{total}] {img_file.name} -> {out_file.relative_to(output_path)}")

    print(f"\n✅ 完成! 共生成 {count} 张截图，输出到: {output_path}")


def list_devices():
    """列出所有支持的设备"""
    print("=" * 65)
    print("支持的设备尺寸")
    print("=" * 65)

    categories = {}
    for key, spec in DEVICE_SPECS.items():
        cat = spec["category"]
        if cat not in categories:
            categories[cat] = []
        categories[cat].append((key, spec))

    for cat, devices in categories.items():
        print(f"\n--- {cat} ---")
        for key, spec in devices:
            w, h = spec["size"]
            print(f"  {key:<25} {w:>4} x {h:<4}  {spec['name']}")

    print(f"\n--- 预设组合 ---")
    for preset_name, device_list in PRESETS.items():
        print(f"  {preset_name:<25} {', '.join(device_list)}")


def main():
    parser = argparse.ArgumentParser(
        description="Apple App Store 截图生成器",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  %(prog)s --input shots/ --output out/
  %(prog)s --input shots/ --output out/ --devices iphone67 iphone55
  %(prog)s --input shots/ --output out/ --preset required
  %(prog)s --input shots/ --output out/ --bg "#667eea" --title "日语学习" --subtitle "轻松掌握日语"
  %(prog)s --list-devices
        """,
    )
    parser.add_argument("--input", "-i", help="源截图目录")
    parser.add_argument("--output", "-o", default="appstore_screenshots", help="输出目录 (默认: appstore_screenshots)")
    parser.add_argument("--devices", "-d", nargs="+", choices=list(DEVICE_SPECS.keys()), help="目标设备 (可多选)")
    parser.add_argument("--preset", "-p", choices=list(PRESETS.keys()), help="使用预设设备组合")
    parser.add_argument("--bg", default="#1a1a2e", help="背景颜色 hex (默认: #1a1a2e 深蓝)")
    parser.add_argument("--title", "-t", help="标题文字 (显示在截图上方)")
    parser.add_argument("--subtitle", "-s", help="副标题文字")
    parser.add_argument("--padding", type=float, default=0.08, help="内边距比例 (默认: 0.08)")
    parser.add_argument("--screenshot-ratio", type=float, default=0.72, help="截图占画布比例 (默认: 0.72)")
    parser.add_argument("--corner-radius", type=int, default=40, help="截图圆角半径 (默认: 40, 0=无圆角)")
    parser.add_argument("--no-shadow", action="store_true", help="不添加阴影")
    parser.add_argument("--title-color", default="#ffffff", help="标题颜色 hex (默认: #ffffff)")
    parser.add_argument("--list-devices", "-l", action="store_true", help="列出所有支持的设备尺寸")

    args = parser.parse_args()

    if args.list_devices:
        list_devices()
        return

    if not args.input:
        parser.error("请指定源截图目录: --input <目录>")

    if not os.path.isdir(args.input):
        parser.error(f"目录不存在: {args.input}")

    # 确定目标设备
    if args.preset:
        devices = PRESETS[args.preset]
    elif args.devices:
        devices = args.devices
    else:
        devices = PRESETS["required"]
        print(f"未指定设备，使用默认预设 'required': {', '.join(devices)}\n")

    process_batch(
        input_dir=args.input,
        output_dir=args.output,
        devices=devices,
        bg_color=hex_to_rgb(args.bg),
        title=args.title,
        subtitle=args.subtitle,
        padding_ratio=args.padding,
        screenshot_ratio=args.screenshot_ratio,
        corner_radius=args.corner_radius,
        shadow=not args.no_shadow,
        title_color=hex_to_rgb(args.title_color),
    )


if __name__ == "__main__":
    main()
