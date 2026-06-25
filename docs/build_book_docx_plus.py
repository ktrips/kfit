#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cursor-claude-code-ios-app-book-plus.md → Kindle対応 .docx 生成スクリプト

特徴:
- Heading 1/2/3 スタイル → KDP ナビゲーション目次を自動生成
- Plus テーマカラー（パープル × オレンジ × グリーン）
- コードブロック / テーブル / 引用 / 画像 対応
- `[プロンプト例]:` ラベル付きコードブロックを枠付きで強調

pip install python-docx Pillow
"""

import os
import re
import tempfile

from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from PIL import Image

SRC = os.path.join(os.path.dirname(__file__), "cursor-claude-code-ios-app-book-plus.md")
OUT = os.path.join(os.path.dirname(__file__), "cursor-claude-code-ios-app-book-plus.docx")
BASE_DIR = os.path.dirname(__file__)

# ── 配色パレット（Fitingo Plus テーマ）────────────────────────
GREEN      = "58CC02"   # Fitingo グリーン（H1・章タイトル）
GREEN_DK   = "3E8F00"
GREEN_LT   = "EDFAD4"
ORANGE     = "FF8C00"   # Fitingo オレンジ（Plus カラー・H2）
ORANGE_DK  = "CC6F00"
ORANGE_LT  = "FFF4E0"
PURPLE     = "9747E8"   # Plus パープル（H3）
PURPLE_DK  = "7228C0"
PURPLE_LT  = "F3EBFE"
BLUE_DK    = "3B8AB8"
INK        = "37474F"   # 本文
GRAY_LT    = "F2F3F4"   # コードブロック背景
CODE_HINT  = "FFF8EC"   # プロンプト例背景（薄いオレンジ）
JP_FONT    = "Hiragino Sans"

_bm_id = [2000]


# ── XML ヘルパー ──────────────────────────────────────────────
def set_style_font(style, *, name=JP_FONT, size=None, color=None, bold=None):
    style.font.name = name
    rpr = style.element.get_or_add_rPr()
    rfonts = rpr.get_or_add_rFonts()
    rfonts.set(qn("w:ascii"), name)
    rfonts.set(qn("w:hAnsi"), name)
    rfonts.set(qn("w:eastAsia"), name)
    if size is not None:
        style.font.size = Pt(size)
    if color is not None:
        style.font.color.rgb = RGBColor.from_string(color)
    if bold is not None:
        style.font.bold = bold


def shade_paragraph(p, fill):
    pPr = p._p.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), fill)
    pPr.append(shd)


def para_border(p, *, edges=("left",), color=GREEN, sz="18", space="10"):
    pPr = p._p.get_or_add_pPr()
    pBdr = OxmlElement("w:pBdr")
    for edge in edges:
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "single")
        el.set(qn("w:sz"), sz)
        el.set(qn("w:space"), space)
        el.set(qn("w:color"), color)
        pBdr.append(el)
    pPr.append(pBdr)


def shade_cell(cell, fill):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), fill)
    tcPr.append(shd)


def add_bookmark(p, name):
    _bm_id[0] += 1
    bid = str(_bm_id[0])
    start = OxmlElement("w:bookmarkStart")
    start.set(qn("w:id"), bid)
    start.set(qn("w:name"), name)
    end = OxmlElement("w:bookmarkEnd")
    end.set(qn("w:id"), bid)
    p._p.insert(0, start)
    p._p.append(end)


def add_internal_hyperlink(p, anchor, text, *, color=BLUE_DK, bold=False):
    hyperlink = OxmlElement("w:hyperlink")
    hyperlink.set(qn("w:anchor"), anchor)
    run = OxmlElement("w:r")
    rPr = OxmlElement("w:rPr")
    rfonts = OxmlElement("w:rFonts")
    rfonts.set(qn("w:eastAsia"), JP_FONT)
    rPr.append(rfonts)
    c = OxmlElement("w:color"); c.set(qn("w:val"), color); rPr.append(c)
    u = OxmlElement("w:u"); u.set(qn("w:val"), "single"); rPr.append(u)
    if bold:
        rPr.append(OxmlElement("w:b"))
    run.append(rPr)
    t = OxmlElement("w:t"); t.set(qn("xml:space"), "preserve"); t.text = text
    run.append(t)
    hyperlink.append(run)
    p._p.append(hyperlink)


def anchor_to_bm(anchor):
    return "bm_" + anchor.strip().lstrip("#").replace("-", "_")


# ── インライン記法 ────────────────────────────────────────────
INLINE_RE = re.compile(r"(\*\*.+?\*\*|\*[^*]+?\*|`[^`]+`|\[[^\]]+\]\([^)]+\))")


def add_inline(p, text, *, base_color=INK):
    for tok in INLINE_RE.split(text):
        if not tok:
            continue
        if tok.startswith("**") and tok.endswith("**"):
            r = p.add_run(tok[2:-2]); r.bold = True
            r.font.color.rgb = RGBColor.from_string(base_color)
        elif tok.startswith("*") and tok.endswith("*"):
            r = p.add_run(tok[1:-1]); r.italic = True
            r.font.color.rgb = RGBColor.from_string(base_color)
        elif tok.startswith("`") and tok.endswith("`"):
            r = p.add_run(tok[1:-1])
            r.font.name = "Menlo"
            r.font.color.rgb = RGBColor.from_string(PURPLE_DK)
        elif tok.startswith("[") and "](" in tok:
            label = tok[1:tok.index("](")]
            target = tok[tok.index("](") + 2:-1]
            if target.startswith("#"):
                add_internal_hyperlink(p, anchor_to_bm(target), label)
            else:
                r = p.add_run(label)
                r.font.color.rgb = RGBColor.from_string(BLUE_DK)
        else:
            r = p.add_run(tok)
            r.font.color.rgb = RGBColor.from_string(base_color)


# ── 画像縮小キャッシュ ────────────────────────────────────────
_tmpdir = tempfile.mkdtemp(prefix="plus_book_imgs_")
_img_cache = {}


def prep_image(rel_path):
    if rel_path in _img_cache:
        return _img_cache[rel_path]
    src = os.path.join(BASE_DIR, rel_path)
    if not os.path.isfile(src):
        print(f"  ⚠️  画像が見つかりません: {rel_path}")
        _img_cache[rel_path] = None
        return None
    try:
        im = Image.open(src).convert("RGB")
        long_side = 1100
        w, h = im.size
        scale = min(1.0, long_side / max(w, h))
        if scale < 1.0:
            im = im.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
        out = os.path.join(_tmpdir, f"img_{len(_img_cache)}.jpg")
        im.save(out, "JPEG", quality=82, optimize=True)
        result = (out, im.size)
        _img_cache[rel_path] = result
        return result
    except Exception as e:
        print(f"  ⚠️  画像スキップ: {rel_path} ({e})")
        _img_cache[rel_path] = None
        return None


def add_image(doc, rel_path, alt=""):
    prepped = prep_image(rel_path)
    if not prepped:
        return
    path, (w, h) = prepped
    max_w, max_h = 3.8, 3.4
    if (w / max_w) >= (h / max_h):
        kwargs = {"width": Inches(max_w)}
    else:
        kwargs = {"height": Inches(max_h)}
    shape = doc.add_picture(path, **kwargs)
    if alt:
        docPr = shape._inline.find(qn("wp:docPr"))
        if docPr is not None:
            docPr.set("descr", alt)
            docPr.set("title", alt)
    doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER
    doc.paragraphs[-1].paragraph_format.space_before = Pt(4)
    doc.paragraphs[-1].paragraph_format.space_after = Pt(8)
    if alt:
        cap = doc.add_paragraph(alt)
        cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
        cap.paragraph_format.space_after = Pt(10)
        for r in cap.runs:
            r.font.size = Pt(9)
            r.font.color.rgb = RGBColor.from_string("888888")
            r.italic = True


# ── TOC プリスキャン ──────────────────────────────────────────
def prescan_toc(lines):
    entries = []
    in_toc = False
    in_code = False
    counter = 0
    for raw in lines:
        s = raw.strip()
        if s.startswith("```"):
            in_code = not in_code
            continue
        if in_code:
            continue
        hm = re.match(r"^(#{1,6})\s+(.*)$", s)
        if not hm:
            continue
        level = min(len(hm.group(1)), 4)
        text = hm.group(2).strip()
        if level == 2 and text == "目次":
            in_toc = True
            continue
        if level <= 2 and text != "目次":
            in_toc = False
        if in_toc and level == 3:
            continue
        if level in (2, 3) and text != "目次":
            counter += 1
            entries.append((level, _strip_inline(text), f"_Toc{91000000 + counter}"))
    return entries


def _strip_inline(text):
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    return text.replace("**", "").replace("*", "").replace("`", "").strip()


def _toc_field_run(parent_par, char_type=None, instr=None):
    r = parent_par.add_run()
    if char_type:
        fc = OxmlElement("w:fldChar")
        fc.set(qn("w:fldCharType"), char_type)
        r._r.append(fc)
    if instr is not None:
        it = OxmlElement("w:instrText")
        it.set(qn("xml:space"), "preserve")
        it.text = instr
        r._r.append(it)
    return r


def emit_toc_field(doc, entries):
    if not entries:
        return
    last = len(entries) - 1
    for idx, (level, text, tocname) in enumerate(entries):
        ep = doc.add_paragraph()
        ep.paragraph_format.left_indent = Pt(0 if level == 2 else 20)
        ep.paragraph_format.space_after = Pt(3)
        ep.paragraph_format.line_spacing = 1.1
        if idx == 0:
            _toc_field_run(ep, char_type="begin")
            _toc_field_run(ep, instr=' TOC \\h \\z \\u ')
            _toc_field_run(ep, char_type="separate")
        hl = OxmlElement("w:hyperlink")
        hl.set(qn("w:anchor"), tocname)
        hl.set(qn("w:history"), "1")
        run = OxmlElement("w:r")
        rPr = OxmlElement("w:rPr")
        rf = OxmlElement("w:rFonts"); rf.set(qn("w:eastAsia"), JP_FONT); rPr.append(rf)
        col = OxmlElement("w:color")
        col.set(qn("w:val"), GREEN_DK if level == 2 else INK)
        rPr.append(col)
        if level == 2:
            rPr.append(OxmlElement("w:b"))
        sz = OxmlElement("w:sz"); sz.set(qn("w:val"), "26" if level == 2 else "22"); rPr.append(sz)
        run.append(rPr)
        t = OxmlElement("w:t"); t.set(qn("xml:space"), "preserve"); t.text = text
        run.append(t)
        hl.append(run)
        ep._p.append(hl)
        if idx == last:
            _toc_field_run(ep, char_type="end")


# ── ブロックビルダー ──────────────────────────────────────────
def add_heading(doc, level, text, pending_anchor, page_break=False, toc_bookmark=None):
    style_map = {1: "Title", 2: "Heading 1", 3: "Heading 2", 4: "Heading 3"}
    p = doc.add_paragraph(style=style_map[level])
    if page_break:
        p.paragraph_format.page_break_before = True
    color_map = {1: GREEN_DK, 2: GREEN_DK, 3: ORANGE_DK, 4: PURPLE_DK}
    add_inline(p, text, base_color=color_map[level])
    if level == 2:
        para_border(p, edges=("bottom",), color=GREEN, sz="8", space="6")
    if toc_bookmark:
        add_bookmark(p, toc_bookmark)
    if pending_anchor:
        add_bookmark(p, anchor_to_bm(pending_anchor))
    return None


def add_blockquote(doc, lines):
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Pt(12)
    p.paragraph_format.space_before = Pt(6)
    p.paragraph_format.space_after = Pt(10)
    shade_paragraph(p, ORANGE_LT)
    para_border(p, edges=("left",), color=ORANGE, sz="24", space="10")
    for i, ln in enumerate(lines):
        if i > 0:
            p.add_run().add_break()
        add_inline(p, ln, base_color=INK)


def add_bullet(doc, text, indent=0):
    p = doc.add_paragraph(style="List Bullet")
    p.paragraph_format.space_after = Pt(2)
    if indent > 0:
        p.paragraph_format.left_indent = Pt(indent * 18)
    add_inline(p, text, base_color=INK)


def add_numbered(doc, num, text):
    p = doc.add_paragraph(style="List Number")
    p.paragraph_format.space_after = Pt(3)
    add_inline(p, text, base_color=INK)


def add_paragraph_text(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(8)
    p.paragraph_format.line_spacing = 1.3
    add_inline(p, text, base_color=INK)


def add_divider(doc):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after = Pt(4)
    para_border(p, edges=("bottom",), color=GREEN, sz="6", space="1")


def add_code_block(doc, lines, is_prompt=False):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(6)
    p.paragraph_format.space_after = Pt(10)
    p.paragraph_format.left_indent = Pt(8)
    shade_paragraph(p, CODE_HINT if is_prompt else GRAY_LT)
    border_color = ORANGE if is_prompt else GREEN
    para_border(p, edges=("left",), color=border_color, sz="18", space="10")
    for i, ln in enumerate(lines):
        if i > 0:
            p.add_run().add_break()
        r = p.add_run(ln)
        r.font.name = "Menlo"
        r.font.size = Pt(9)
        r.font.color.rgb = RGBColor.from_string(ORANGE_DK if is_prompt else "455A64")
        rpr = r._element.get_or_add_rPr()
        rf = rpr.get_or_add_rFonts()
        rf.set(qn("w:ascii"), "Menlo")
        rf.set(qn("w:hAnsi"), "Menlo")


def add_table(doc, rows):
    header = rows[0]
    body = rows[1:]
    ncol = len(header)
    table = doc.add_table(rows=1 + len(body), cols=ncol)
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    for j, cell_text in enumerate(header):
        cell = table.rows[0].cells[j]
        shade_cell(cell, ORANGE)
        cell.paragraphs[0].text = ""
        run = cell.paragraphs[0].add_run(cell_text.strip())
        run.bold = True
        run.font.color.rgb = RGBColor.from_string("FFFFFF")
        run.font.size = Pt(10)
    for i, brow in enumerate(body):
        for j in range(ncol):
            cell = table.rows[i + 1].cells[j]
            shade_cell(cell, ORANGE_LT if i % 2 == 0 else "FFFFFF")
            cell.paragraphs[0].text = ""
            txt = brow[j].strip() if j < len(brow) else ""
            add_inline(cell.paragraphs[0], txt, base_color=INK)
            if cell.paragraphs[0].runs:
                cell.paragraphs[0].runs[0].font.size = Pt(9.5)
    doc.add_paragraph().paragraph_format.space_after = Pt(6)


def split_table_row(line):
    s = line.strip()
    if s.startswith("|"): s = s[1:]
    if s.endswith("|"):   s = s[:-1]
    return [c for c in s.split("|")]


def add_prompt_label(doc, label_text):
    """[プロンプト例]: などのラベル行をオレンジ強調で追加"""
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(12)
    p.paragraph_format.space_after = Pt(2)
    r = p.add_run(label_text)
    r.bold = True
    r.font.size = Pt(10.5)
    r.font.color.rgb = RGBColor.from_string(ORANGE_DK)


# ── メイン処理 ────────────────────────────────────────────────
def build():
    with open(SRC, encoding="utf-8") as f:
        lines = f.read().split("\n")

    doc = Document()

    # ベーススタイル設定
    set_style_font(doc.styles["Normal"],    name=JP_FONT, size=10.5, color=INK)
    set_style_font(doc.styles["Title"],     name=JP_FONT, size=24,   color=GREEN_DK,  bold=True)
    set_style_font(doc.styles["Heading 1"], name=JP_FONT, size=18,   color=GREEN_DK,  bold=True)
    set_style_font(doc.styles["Heading 2"], name=JP_FONT, size=14,   color=ORANGE_DK, bold=True)
    set_style_font(doc.styles["Heading 3"], name=JP_FONT, size=12,   color=PURPLE_DK, bold=True)
    for sname in ("List Bullet", "List Number"):
        try:
            set_style_font(doc.styles[sname], name=JP_FONT, size=10.5, color=INK)
        except KeyError:
            pass

    toc_entries = prescan_toc(lines)
    toc_queue = [e[2] for e in toc_entries]

    pending_anchor = None
    in_toc = False
    in_code = False
    code_lines = []
    next_code_is_prompt = False

    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        stripped = line.strip()

        # コードフェンス
        if stripped.startswith("```"):
            if in_code:
                add_code_block(doc, code_lines, is_prompt=next_code_is_prompt)
                code_lines = []
                in_code = False
                next_code_is_prompt = False
            else:
                in_code = True
            i += 1
            continue
        if in_code:
            code_lines.append(line)
            i += 1
            continue

        # HTML タグ系（スキップ or ページ区切り）
        if stripped.startswith("<div") or stripped.startswith("</div") or stripped.startswith("<small") or stripped.startswith("</small"):
            i += 1
            continue

        # アンカー
        m = re.match(r'<a id="([^"]+)"></a>', stripped)
        if m:
            pending_anchor = m.group(1)
            i += 1
            continue

        # 見出し
        hm = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if hm:
            level = min(len(hm.group(1)), 4)
            text = hm.group(2).strip()
            if level == 2 and text == "目次":
                in_toc = True
                add_heading(doc, level, text, pending_anchor)
                emit_toc_field(doc, toc_entries)
                pending_anchor = None
                i += 1
                continue
            if level <= 2 and text != "目次":
                in_toc = False
            if in_toc and level == 3:
                pending_anchor = None
                i += 1
                continue
            # 第X章ヘッダー（## 第X章）は改ページ
            is_chapter = (level == 2 and re.match(r"^第[一二三四五六七八九十]+章", text))
            toc_bm = None
            if level in (2, 3) and text != "目次":
                toc_bm = toc_queue.pop(0) if toc_queue else None
            add_heading(doc, level, text, pending_anchor,
                        page_break=bool(is_chapter), toc_bookmark=toc_bm)
            pending_anchor = None
            i += 1
            continue

        # 空行
        if stripped == "":
            i += 1
            continue

        # 目次領域の本文はスキップ
        if in_toc:
            i += 1
            continue

        # 水平線
        if stripped == "---":
            add_divider(doc)
            i += 1
            continue

        # [プロンプト例]: ラベル付き行の検出
        label_m = re.match(r"^(\[プロンプト例\][^\:]*):?\s*(.*)$", stripped)
        if label_m:
            label_text = label_m.group(1) + (": " + label_m.group(2) if label_m.group(2) else "")
            add_prompt_label(doc, label_text.strip(": "))
            next_code_is_prompt = True
            i += 1
            continue

        # 画像
        im = re.match(r"^!\[([^\]]*)\]\(([^)]+)\)\s*$", stripped)
        if im:
            add_image(doc, im.group(2), im.group(1))
            i += 1
            continue

        # テーブル
        if stripped.startswith("|"):
            tbl = []
            while i < n and lines[i].strip().startswith("|"):
                tbl.append(lines[i])
                i += 1
            parsed = [split_table_row(r) for r in tbl]
            parsed = [r for r in parsed if not all(set(c.strip()) <= set("-: ") and c.strip() for c in r)]
            if parsed:
                add_table(doc, parsed)
            continue

        # 引用
        if stripped.startswith(">"):
            quote = []
            while i < n and lines[i].strip().startswith(">"):
                q = lines[i].strip()[1:].strip()
                quote.append(q.rstrip())
                i += 1
            add_blockquote(doc, quote)
            continue

        # 箇条書き（インデント対応）
        bm = re.match(r"^(\s*)[-•]\s+(.+)$", line)
        if bm:
            indent = len(bm.group(1)) // 2
            add_bullet(doc, bm.group(2).strip(), indent=indent)
            i += 1
            continue

        # 番号付きリスト
        nm = re.match(r"^\d+\.\s+(.+)$", stripped)
        if nm:
            add_numbered(doc, 0, nm.group(1).strip())
            i += 1
            continue

        # 通常段落
        add_paragraph_text(doc, stripped)
        i += 1

    doc.save(OUT)
    size_mb = os.path.getsize(OUT) / 1048576
    print(f"✅ 保存完了: {OUT}  ({size_mb:.1f} MB)")


if __name__ == "__main__":
    build()
