#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 `testcards/images/` 下的 30 张合成名片图片。

## 用途

这些图片是 **OCR 的输入**：在 Mac 上经 Vision 识别后产出
`testcards/ocr/<卡片ID>.txt`，再由 `FieldExtractionEvaluatorTests` 统计字段级准确率（任务 4.4）。

## 内容来源

图片上的文字**逐字来自** `testcards/ground_truth.json` 的 `groundTruth` 字段：

- 中文卡用 `手机: 值` 这类中文标签，英文卡用裸值——与
  `BusinessCardFieldParserTests` 里手写 OCR 夹具的风格保持一致，避免让评价受
  「夹具从没出现过的排版」干扰；
- `additionalEmails`（TC06 / TC23）在邮箱行之后按出现顺序各占一行的裸值，
  对应「同字段多候选」场景；
- **不做任何翻译**。真值里没有英文译名，凭空补一个就违反了「AI 不得虚构信息」，
  因此 `bilingual` 布局只通过排版（双色块、右侧竖条）体现，文字内容与中文卡同形。

## 局限性（须随准确率结论一并说明）

本脚本渲染的文字比真实拍摄的照片干净：无镜头畸变、无真实纸张纹理、无环境光反射。
`tilted` / `darkBg` / `lightBg` / `shadow` / `complexBg` / `occluded` 六种降质是
**程序化、确定性的**，只用来覆盖数据集中已声明的类别，不代表真实拍照的退化分布。
因此由此得到的字段级准确率**偏乐观**，不能当成真实场景的准确率。

## 用法

    python testcards/tools/generate_card_images.py

输出 `testcards/images/TC01.png` … `TC30.png`，并打印自检结果。
"""

from __future__ import annotations

import hashlib
import json
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ---------------------------------------------------------------- 路径与字体

REPO_ROOT = Path(__file__).resolve().parents[2]
GROUND_TRUTH = REPO_ROOT / "testcards" / "ground_truth.json"
OUTPUT_DIR = REPO_ROOT / "testcards" / "images"

# Windows 自带字体；换机器时改这里即可。
FONT_CJK = "C:/Windows/Fonts/msyh.ttc"        # 微软雅黑
FONT_CJK_BOLD = "C:/Windows/Fonts/msyhbd.ttc"
FONT_LATIN = "C:/Windows/Fonts/arial.ttf"
FONT_LATIN_BOLD = "C:/Windows/Fonts/arialbd.ttf"

# 中文标签与 BusinessCardFieldParserTests 的夹具一致。
LABELS_ZH = {
    "mobile": "手机",
    "phone": "电话",
    "fax": "传真",
    "email": "邮箱",
    "website": "网址",
    "address": "地址",
}
CONTACT_ORDER = ["mobile", "phone", "fax", "email", "website", "address"]

# 名片卡面尺寸按 5:3 的常见比例（横版 1160x696、竖版 696x1160），
# 场景画布留出桌面色边距，使图片看起来像一张照片而不是满幅截图。
SCENE_H = (1400, 900)
CARD_H = (1160, 696)
SCENE_V = (900, 1400)
CARD_V = (696, 1160)

# 排版自检收集到的问题（不阻断生成，最后统一打印）。
WARNINGS: list[str] = []


# ---------------------------------------------------------------- 字体自检


def glyph_bytes(font: ImageFont.FreeTypeFont, ch: str) -> bytes:
    """把一个字符渲染成灰度位图的原始字节，用于比较字形。"""
    side = font.size * 3
    img = Image.new("L", (side, side), 0)
    ImageDraw.Draw(img).text((font.size, font.size), ch, font=font, fill=255)
    return img.tobytes()


def check_font_coverage(font_path: str, chars: set[str]) -> list[str]:
    """确认字体对每个用到的字符都有真实字形（防 tofu/豆腐块）。

    做法是把每个字符的位图与私用区码位 U+E000（一定没有真实字形）的位图比对：
    缺字形时 FreeType 会返回同一个 `.notdef`，二者位图一致。
    """
    font = ImageFont.truetype(font_path, 48)
    notdef = glyph_bytes(font, "\ue000")
    return [
        ch for ch in sorted(chars)
        if not ch.isspace() and glyph_bytes(font, ch) == notdef
    ]


# ---------------------------------------------------------------- 文本排版


def contact_lines(truth: dict, extra_emails: list[str], use_zh_labels: bool) -> list[str]:
    """按真值拼出联系方式行；字段缺失就不出现（不写占位值）。"""
    lines: list[str] = []
    for key in CONTACT_ORDER:
        value = truth.get(key)
        if not value:
            continue
        lines.append(f"{LABELS_ZH[key]}: {value}" if use_zh_labels else value)
        if key == "email":
            # 多 Email：主邮箱之外的候选按出现顺序各占一行裸值（同字段多候选）。
            lines.extend(extra_emails)
    return lines


def font_for(text: str, size: int, bold: bool) -> ImageFont.FreeTypeFont:
    """含中日韩字符的文本用雅黑，纯西文用 Arial（更接近真实名片）。"""
    has_cjk = any(ord(ch) > 0x2E80 for ch in text)
    if has_cjk:
        path = FONT_CJK_BOLD if bold else FONT_CJK
    else:
        path = FONT_LATIN_BOLD if bold else FONT_LATIN
    return ImageFont.truetype(path, size)


def fitted_font(text: str, size: int, bold: bool, max_width: int) -> ImageFont.FreeTypeFont:
    """在给定宽度内自适应缩小字号，避免长地址/长公司名溢出卡面。"""
    while size > 14:
        font = font_for(text, size, bold)
        if font.getlength(text) <= max_width:
            return font
        size -= 2
    return font_for(text, size, bold)


def draw_multiline(draw: ImageDraw.ImageDraw, lines, xy, size, color, bold,
                   max_width, line_gap):
    """逐行绘制，返回最后一行文字的底部 y 坐标（不含行距）。"""
    x, y = xy
    for text in lines:
        font = fitted_font(text, size, bold, max_width)
        draw.text((x, y), text, font=font, fill=color)
        y += font.size + line_gap
    return y - line_gap if lines else y


# ---------------------------------------------------------------- 卡面绘制


def render_card(card: dict) -> Image.Image:
    """绘制一张卡面（尚未放到桌面上、尚未旋转）。"""
    is_vertical = card["layout"] == "vertical"
    width, height = CARD_V if is_vertical else CARD_H
    quality = card["quality"]
    truth = card["groundTruth"]
    extra_emails = list(card.get("additionalEmails", []))

    # 英文卡用裸值，中文/双语卡用中文标签（与 BusinessCardFieldParserTests 的手写夹具一致）。
    # 判定依据是姓名是否含中文：英文卡的姓名是拉丁字母，因此走裸值分支。
    use_zh_labels = (
        card["layout"] == "bilingual"
        or any(ord(ch) > 0x2E80 for ch in (truth.get("name") or ""))
    )

    dark = quality == "darkBg"
    low_contrast = quality == "lightBg"

    if dark:
        bg, primary, secondary = (38, 38, 48), (242, 242, 246), (176, 178, 198)
        accent = (108, 123, 255)
    elif low_contrast:
        bg, primary, secondary = (255, 255, 255), (190, 190, 196), (200, 200, 206)
        accent = (214, 214, 220)
    else:
        bg, primary, secondary = (255, 255, 255), (28, 28, 34), (96, 98, 110)
        accent = (32, 108, 214)

    card_img = Image.new("RGB", (width, height), bg)
    draw = ImageDraw.Draw(card_img)

    pad = 60
    inner = width - pad * 2

    # 左侧色条：视觉上的「名片感」，也让检测器有明确的矩形边界。
    draw.rectangle([0, 0, 14, height], fill=accent)

    # 双语卡加一条右侧竖条，用来体现 bilingual 排版（内容不做翻译）。
    if card["layout"] == "bilingual":
        draw.rectangle([width - 24, 0, width - 14, height], fill=accent)

    scale = 1.0 if not is_vertical else 1.08

    company = truth.get("company")
    name = truth.get("name") or ""
    job_title = truth.get("jobTitle")

    y = int(round(pad * (1.0 if not is_vertical else 1.3)))
    if company:
        font = fitted_font(company, int(34 * scale), True, inner)
        draw.text((pad, y), company, font=font, fill=secondary)
        y += font.size + 14

    font = fitted_font(name, int(66 * scale), True, inner)
    draw.text((pad, y), name, font=font, fill=primary)
    y += font.size + 10

    if job_title:
        font = fitted_font(job_title, int(30 * scale), False, inner)
        draw.text((pad, y), job_title, font=font, fill=secondary)
        y += font.size + 16

    y = max(y, int(height * (0.36 if not is_vertical else 0.30)))
    draw.line([pad, y, width - pad, y], fill=accent, width=2)
    y += 22

    lines = contact_lines(truth, extra_emails, use_zh_labels)
    bottom = draw_multiline(draw, lines, (pad, y), int(28 * scale), primary, False,
                            inner, 18 if not is_vertical else 26)

    # 排版自检：联系方式块必须留在卡面内，且每行都完整落在左右边距之间。
    if bottom > height - pad // 2:
        WARNINGS.append(f"{card['id']}: 联系方式块底部 {bottom} 超出卡面可用高度 {height - pad // 2}")
    for text in lines:
        used = font_for(text, int(28 * scale), False)
        if used.getlength(text) > inner:
            WARNINGS.append(f"{card['id']}: 行内容超出可用宽度「{text}」")

    return card_img


# ---------------------------------------------------------------- 场景与降质


def make_scene(card: dict) -> tuple[Image.Image, tuple[int, int]]:
    """生成桌面背景并返回（场景图, 卡面粘贴位置）。"""
    is_vertical = card["layout"] == "vertical"
    size = SCENE_V if is_vertical else SCENE_H
    quality = card["quality"]
    rng = random.Random(int(hashlib.sha1(card["id"].encode()).hexdigest()[:8], 16))

    if quality == "complexBg":
        # 杂色背景：随机色块 + 条纹，模拟桌面上的杂物。
        scene = Image.new("RGB", size, (222, 216, 204))
        draw = ImageDraw.Draw(scene)
        for _ in range(90):
            x0 = rng.randint(-60, size[0])
            y0 = rng.randint(-60, size[1])
            w = rng.randint(40, 200)
            h = rng.randint(40, 200)
            color = (rng.randint(120, 235), rng.randint(120, 235), rng.randint(120, 235))
            draw.rectangle([x0, y0, x0 + w, y0 + h], fill=color)
        for i in range(0, size[1], 26):
            draw.line([0, i, size[0], i], fill=(198, 190, 176), width=2)
        scene = scene.filter(ImageFilter.GaussianBlur(1.2))
    elif quality == "darkBg":
        scene = Image.new("RGB", size, (16, 16, 22))
        draw = ImageDraw.Draw(scene)
        for i in range(0, size[1], 40):
            draw.line([0, i, size[0], i], fill=(26, 26, 34), width=1)
    else:
        # 常规桌面：浅灰，带轻微的径向暗角，避免整图纯色。
        scene = Image.new("RGB", size, (232, 230, 228))
        draw = ImageDraw.Draw(scene)
        cx, cy = size[0] / 2, size[1] / 2
        max_r = (cx ** 2 + cy ** 2) ** 0.5
        for r in range(int(max_r), 0, -6):
            t = r / max_r
            shade = int(232 - 26 * (t ** 2))
            draw.ellipse([cx - r, cy - r, cx + r, cy + r],
                         fill=(shade, shade - 2, shade - 4))

    card_w, card_h = CARD_V if is_vertical else CARD_H
    pos = ((size[0] - card_w) // 2, (size[1] - card_h) // 2)
    return scene, pos


def add_noise(img: Image.Image, amount: int, seed: int) -> Image.Image:
    """叠加轻微噪点，让降质样本不至于像纯矢量图。"""
    rng = random.Random(seed)
    pixels = img.load()
    for _ in range(img.width * img.height // 6):
        x = rng.randrange(img.width)
        y = rng.randrange(img.height)
        r, g, b = pixels[x, y]
        delta = rng.randint(-amount, amount)
        pixels[x, y] = (
            min(255, max(0, r + delta)),
            min(255, max(0, g + delta)),
            min(255, max(0, b + delta)),
        )
    return img


def apply_quality(scene: Image.Image, pos, card_img: Image.Image, card: dict) -> Image.Image:
    """把卡面按质量变体放到场景上。"""
    quality = card["quality"]
    seed = int(hashlib.sha1(card["id"].encode()).hexdigest()[:8], 16)

    angle = {"tilted": 5.0, "complexBg": 2.5, "darkBg": -1.5, "shadow": 1.5}.get(quality, 0.0)

    if angle:
        # expand=True 才能留住被旋转后跑到原画布之外的卡角，否则看起来像被裁过。
        placed = card_img.convert("RGBA").rotate(
            angle, resample=Image.BICUBIC, expand=True, fillcolor=(0, 0, 0, 0)
        )
        pos = ((scene.width - placed.width) // 2, (scene.height - placed.height) // 2)
    else:
        placed = card_img.convert("RGBA")

    # 投影：让卡面与桌面之间有层次。
    shadow = Image.new("RGBA", scene.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    sx, sy = pos[0] + 10, pos[1] + 14
    shadow_draw.rectangle(
        [sx, sy, sx + placed.width, sy + placed.height],
        fill=(0, 0, 0, 90),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    scene = Image.alpha_composite(scene.convert("RGBA"), shadow)

    scene.paste(placed, pos, placed)

    if quality == "shadow":
        # 斜向阴影：模拟拍摄时手或机身挡住的光线。
        shade = Image.new("RGBA", scene.size, (0, 0, 0, 0))
        shade_draw = ImageDraw.Draw(shade)
        for i in range(scene.width):
            alpha = int(150 * max(0.0, (i / scene.width - 0.15)) / 0.85)
            shade_draw.line([i, 0, i, scene.height], fill=(0, 0, 0, alpha))
        scene = Image.alpha_composite(scene, shade)

    if quality == "occluded":
        # 手指遮住右下角：只做确定性遮挡，不改变卡面文字本身。
        occl = Image.new("RGBA", scene.size, (0, 0, 0, 0))
        occl_draw = ImageDraw.Draw(occl)
        w, h = scene.size
        occl_draw.ellipse(
            [w * 0.62, h * 0.68, w * 1.05, h * 1.25],
            fill=(222, 176, 148, 255),
        )
        occl_draw.ellipse(
            [w * 0.70, h * 0.74, w * 1.10, h * 1.30],
            fill=(214, 166, 138, 255),
        )
        occl = occl.filter(ImageFilter.GaussianBlur(6))
        scene = Image.alpha_composite(scene, occl)

    result = scene.convert("RGB")
    if quality != "good":
        result = add_noise(result, 6 if quality in ("tilted", "shadow") else 10, seed)
    return result


# ---------------------------------------------------------------- 主流程


def main() -> int:
    data = json.loads(GROUND_TRUTH.read_text(encoding="utf-8"))
    cards = data["cards"]

    # ---- 字体自检：确认所有字符都有真实字形，且不会渲染成豆腐块。
    charset: set[str] = set()
    for card in cards:
        truth = card["groundTruth"]
        for value in truth.values():
            if value:
                charset.update(str(value))
        charset.update(card.get("additionalEmails", []))
        charset.update(LABELS_ZH.values())
    charset.update("茁")  # 占位，保证集合非空

    for path in (FONT_CJK, FONT_CJK_BOLD):
        missing = check_font_coverage(path, charset)
        if missing:
            print(f"[自检失败] {path} 缺少字形: {''.join(missing)}", file=sys.stderr)
            return 1
    print(f"[自检通过] 中文字体覆盖 {len(charset)} 个字符，无豆腐块")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    for card in cards:
        image = render_card(card)
        scene, pos = make_scene(card)
        image = apply_quality(scene, pos, image, card)
        out = OUTPUT_DIR / f"{card['id']}.png"
        image.save(out, format="PNG", optimize=True)
        print(f"  {card['id']}  {card['layout']:<10} {card['quality']:<10} "
              f"{image.width}x{image.height}  {out.stat().st_size // 1024} KB")

    print(f"\n已生成 {len(cards)} 张到 {OUTPUT_DIR}")

    if WARNINGS:
        print("\n[排版自检发现问题]", file=sys.stderr)
        for warning in WARNINGS:
            print(f"  - {warning}", file=sys.stderr)
        return 1

    print("[排版自检通过] 30 张卡的联系方式块都在卡面内且未超出左右边距")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
