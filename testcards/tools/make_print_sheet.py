# -*- coding: utf-8 -*-
"""把 30 张测试名片的「卡面」排版成 A4 打印件（含裁切标记）。

## 用途

打印后裁成实物名片，用任意能拍照的设备（含 Android）拍下来，再把照片喂进
模拟器相册，用于 `docs/UI验收清单.md` M18 的**真实拍摄条件下**的识别复核
与 T06 `isReliable()` 阈值标定（见 `docs/Mac端验收执行手册.md` §4.3）。

## 与语料的关系

- 卡面复用 `testcards/tools/generate_card_images.py` 的 `render_card`，
  保证打印内容与 `testcards/images/` 里的语料**逐字一致**；
- 只还原「卡面设计」（横版 / 竖版 / 双语，白底 / 深底浅字 / 浅底浅字）；
  拍摄类降质（倾斜 / 阴影 / 遮挡 / 杂乱背景）是采集环节的产物，
  打印不出来、也不该打印，一律按常规白底出。
- 卡面按标准名片尺寸重排（横版 90×54 mm、竖版 54×90 mm），
  而 `testcards/images/` 是 5:3 场景图，两者比例不同，属预期差异。

## 局限（须随复核结论一并说明）

自印卡是真实拍摄条件下的测试对象，但**纸张与工艺与商用名片有差异**
（铜版纸 / 覆膜 / 无覆膜）。结论里不许把它等同于商用名片，须如实标注。

## 用法

    python testcards/tools/make_print_sheet.py

输出 `<仓库上一级>/CamCardClone-测试名片打印件-A4.pdf`（A4 300dpi、多页）。
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]
OUT = REPO.parent / "CamCardClone-测试名片打印件-A4.pdf"

DPI = 300.0


def mm(v: float) -> int:
    return int(round(v / 25.4 * DPI))


# ---------------------------------------------------------------- 载入现有渲染器
_spec = importlib.util.spec_from_file_location(
    "gen", REPO / "testcards" / "tools" / "generate_card_images.py")
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)

CARD_W, CARD_H = 90.0, 54.0      # 标准名片尺寸（横版）
VERT_W, VERT_H = 54.0, 90.0      # 竖版
LABEL_H = 5.0                    # 卡面下方写编号的留白（裁切时丢弃）
GAP_X, GAP_Y = 6.0, 4.0
A4_W, A4_H = 210.0, 297.0

ORIENT = {"horizontal": "横版", "bilingual": "双语", "vertical": "竖版"}
FACE = {
    "good": "常规白底",
    "darkBg": "深底浅字",
    "lightBg": "浅底浅字",
    # 拍摄类降质：打印件仍是常规白底
    "tilted": "常规白底",
    "complexBg": "常规白底",
    "shadow": "常规白底",
    "occluded": "常规白底",
}

F_HEAD = ImageFont.truetype(gen.FONT_CJK_BOLD, mm(4.6))
F_NOTE = ImageFont.truetype(gen.FONT_CJK, mm(2.7))
F_CAP = ImageFont.truetype(gen.FONT_CJK, mm(3.1))


# ---------------------------------------------------------------- 绘制
def face_of(card: dict, vertical: bool) -> Image.Image:
    """渲染卡面并缩放到打印尺寸。"""
    img = gen.render_card(card)
    size = (mm(VERT_W), mm(VERT_H)) if vertical else (mm(CARD_W), mm(CARD_H))
    return img.resize(size, Image.LANCZOS)


def crop_marks(d: ImageDraw.ImageDraw, x: int, y: int, w: int, h: int) -> None:
    """四角 L 形裁切标记，画在卡面之外（不侵入卡面）。"""
    arm, off = mm(3.0), mm(0.6)
    for cx, cy, sx, sy in ((x, y, -1, -1), (x + w, y, 1, -1),
                           (x, y + h, -1, 1), (x + w, y + h, 1, 1)):
        d.line([cx + sx * off, cy, cx + sx * arm, cy], fill=(0, 0, 0), width=1)
        d.line([cx, cy + sy * off, cx, cy + sy * arm], fill=(0, 0, 0), width=1)


def new_page(title: str, note: str) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    page = Image.new("RGB", (mm(A4_W), mm(A4_H)), (255, 255, 255))
    d = ImageDraw.Draw(page)
    d.text((mm(A4_W / 2), mm(11)), title, font=F_HEAD, fill=(0, 0, 0), anchor="mm")
    d.text((mm(A4_W / 2), mm(16.5)), note, font=F_NOTE, fill=(96, 96, 96), anchor="mm")
    return page, d


def layout_page(cards: list[dict], cw_mm: float, ch_mm: float, cols: int,
                title: str, note: str) -> Image.Image:
    page, d = new_page(title, note)
    cw, ch, lh = mm(cw_mm), mm(ch_mm), mm(LABEL_H)
    rows = -(-len(cards) // cols)
    total_w = cols * cw_mm + (cols - 1) * GAP_X
    total_h = rows * (ch_mm + LABEL_H) + (rows - 1) * GAP_Y
    ox = (A4_W - total_w) / 2
    oy = (A4_H - total_h) / 2 + 4.0

    for i, card in enumerate(cards):
        r, c = divmod(i, cols)
        x = mm(ox + c * (cw_mm + GAP_X))
        y = mm(oy + r * (ch_mm + LABEL_H + GAP_Y))
        vertical = card["layout"] == "vertical"
        page.paste(face_of(card, vertical), (x, y))
        crop_marks(d, x, y, cw, ch)
        cap = f"{card['id']} · {ORIENT[card['layout']]} · {FACE[card['quality']]}"
        d.text((x + cw / 2, y + ch + lh * 0.5), cap, font=F_CAP,
               fill=(48, 48, 48), anchor="mm")
    return page


def main() -> int:
    cards = json.loads(
        (REPO / "testcards" / "ground_truth.json").read_text(encoding="utf-8"))["cards"]

    # 自检：所有用到的字符（卡面 + 页面文案）都要有真实字形，防豆腐块
    charset = set("".join(ORIENT.values()) + "".join(FACE.values()))
    charset.update("CamCardClone 测试名片打印件第页横竖版请用A4实际大小不要缩放沿四角裁切标记裁下卡面为虚构数据"
                   "：·、（）0123456789/")
    charset.update(c["id"] for c in cards)
    missing = gen.check_font_coverage(gen.FONT_CJK, charset)
    if missing:
        print(f"[自检失败] 缺字形: {''.join(missing)}", file=sys.stderr)
        return 1

    horiz = [c for c in cards if c["layout"] != "vertical"]
    vert = [c for c in cards if c["layout"] == "vertical"]
    per_page = 8
    total = -(-len(horiz) // per_page) + (1 if vert else 0)

    pages: list[Image.Image] = []
    n = 0
    for i in range(0, len(horiz), per_page):
        n += 1
        pages.append(layout_page(
            horiz[i:i + per_page], CARD_W, CARD_H, 2,
            f"CamCardClone 测试名片打印件 · 第 {n}/{total} 页（横版）",
            "打印：A4 · 实际大小 100% · 不要缩放；裁下后为 90×54 mm · 卡面为虚构数据"))
    if vert:
        n += 1
        pages.append(layout_page(
            vert, VERT_W, VERT_H, 3,
            f"CamCardClone 测试名片打印件 · 第 {n}/{total} 页（竖版）",
            "打印：A4 · 实际大小 100% · 不要缩放；裁下后为 54×90 mm · 卡面为虚构数据"))

    pages[0].save(OUT, "PDF", resolution=DPI, save_all=True, append_images=pages[1:])

    print(f"[自检通过] 字体覆盖 {len(charset)} 个字符，无豆腐块")
    print(f"横版 {len(horiz)} 张 / 竖版 {len(vert)} 张，共 {len(pages)} 页")
    for i, p in enumerate(pages, 1):
        print(f"  第 {i} 页  {p.width}×{p.height} px  "
              f"({p.width / DPI * 25.4:.1f}×{p.height / DPI * 25.4:.1f} mm)")
    print(f"已写出 {OUT}  ({OUT.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
