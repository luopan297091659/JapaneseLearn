#!/usr/bin/env python3
import json
import re
from pathlib import Path

import fitz
import pytesseract
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
LAUNCH_FILE = ROOT / "temp_jlpt_json_all" / "_launch_recommendation.json"
OUT_DIR = ROOT / "temp_jlpt_json_ocr3"
TESSERACT_CMD = Path(r"C:\Program Files\Tesseract-OCR\tesseract.exe")
TESSDATA_DIR = ROOT / "tools" / "tessdata"


def sanitize_slug_part(value: str) -> str:
    value = (value or "").lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    value = value.strip("-")
    return value[:80]


def normalize_text(text: str) -> str:
    text = (text or "").replace("\x00", "")
    text = text.replace("\r", "")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def split_lines(text: str):
    return [line.strip() for line in text.split("\n") if line.strip()]


def detect_section(line: str):
    if re.search(r"語彙|文字|文法|ことば|語法", line):
        return "vocabulary_grammar"
    if re.search(r"読解|文章|長文|短文", line):
        return "reading"
    if re.search(r"聴解|听解|会話|話を聞いて", line):
        return "listening"
    return None


def extract_question_blocks(lines):
    blocks = []
    current_section = "vocabulary_grammar"
    current = None
    start_regex = re.compile(r"^(?:問題|問|Q)\s*([0-9０-９]+)")

    for line in lines:
        section = detect_section(line)
        if section:
            current_section = section

        start = start_regex.search(line)
        if start:
            if current:
                blocks.append(current)
            question_no = start.group(1).translate(str.maketrans("０１２３４５６７８９", "0123456789"))
            current = {
                "section_type": current_section,
                "question_no": question_no,
                "lines": [line],
            }
            continue

        if current:
            current["lines"].append(line)

    if current:
        blocks.append(current)
    return blocks


def guess_options(block_text: str):
    options = []
    option_regex = re.compile(r"(?:^|\n)\s*([1-4①-④Ａ-ＤA-D])[\.\)）\s]+([^\n]+)")
    key_map = {
        "①": "1", "②": "2", "③": "3", "④": "4",
        "A": "1", "B": "2", "C": "3", "D": "4",
        "Ａ": "1", "Ｂ": "2", "Ｃ": "3", "Ｄ": "4",
    }

    for m in option_regex.finditer(block_text):
        raw_key = m.group(1)
        key = key_map.get(raw_key, raw_key)
        options.append({"key": str(key), "text": m.group(2).strip()})

    if len(options) >= 2:
        return options

    return [
        {"key": "1", "text": "Option 1 (needs manual cleanup)"},
        {"key": "2", "text": "Option 2 (needs manual cleanup)"},
        {"key": "3", "text": "Option 3 (needs manual cleanup)"},
        {"key": "4", "text": "Option 4 (needs manual cleanup)"},
    ]


def to_questions(blocks, full_text):
    if not blocks:
        return [{
            "section_type": "reading",
            "section_title": "needs-manual-cleanup",
            "question_group": "ocr-draft",
            "question_no": "1",
            "sort_order": 1,
            "prompt": full_text[:1200] or "OCR extracted text could not be structured automatically.",
            "passage": full_text[:2600],
            "transcript": "",
            "options": [
                {"key": "1", "text": "Option 1 (needs manual cleanup)"},
                {"key": "2", "text": "Option 2 (needs manual cleanup)"},
                {"key": "3", "text": "Option 3 (needs manual cleanup)"},
                {"key": "4", "text": "Option 4 (needs manual cleanup)"},
            ],
            "answer": "1",
            "explanation": "OCR draft. Please manually verify answers and explanations.",
            "explanation_zh": "OCR草稿，请人工核对答案与解析。",
            "knowledge_points": ["ocr-draft"],
            "score": 1,
        }]

    questions = []
    for idx, block in enumerate(blocks):
        content = "\n".join(block["lines"])
        section_type = block["section_type"]
        section_title = "文字・語彙・文法"
        if section_type == "reading":
            section_title = "読解"
        elif section_type == "listening":
            section_title = "聴解"

        questions.append({
            "section_type": section_type,
            "section_title": section_title,
            "question_group": "ocr-auto",
            "question_no": str(block.get("question_no") or idx + 1),
            "sort_order": idx + 1,
            "prompt": content[:1300],
            "passage": content[:2600] if section_type == "reading" else "",
            "transcript": content[:2600] if section_type == "listening" else "",
            "options": guess_options(content),
            "answer": "1",
            "explanation": "OCR draft. Please manually verify answers and explanations.",
            "explanation_zh": "OCR草稿，请人工核对答案与解析。",
            "knowledge_points": ["ocr-auto"],
            "score": 1,
        })
    return questions


def ocr_pdf(pdf_path: Path) -> tuple[str, int]:
    doc = fitz.open(pdf_path)
    pages_text = []
    try:
        for i, page in enumerate(doc):
            mat = fitz.Matrix(2.0, 2.0)
            pix = page.get_pixmap(matrix=mat, alpha=False)
            img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
            text = pytesseract.image_to_string(
                img,
                lang="jpn",
                config=f'--oem 1 --psm 6 --tessdata-dir {str(TESSDATA_DIR)}',
            )
            pages_text.append(f"-- page {i + 1} --\n{text}")
    finally:
        doc.close()

    combined = normalize_text("\n\n".join(pages_text))
    return combined, len(pages_text)


def build_paper(rec: dict, ocr_text: str, page_count: int):
    level = rec["level"]
    year = int(rec["year"])
    session = rec["session"]
    slug = sanitize_slug_part(rec["slug"]) or sanitize_slug_part(f"{level}-{year}-{session}")

    lines = split_lines(ocr_text)
    blocks = extract_question_blocks(lines)
    questions = to_questions(blocks, ocr_text)

    return {
        "level": level,
        "year": year,
        "session": session,
        "title": f"{level} Mock Exam {year}-{session}",
        "slug": slug,
        "source_label": Path(rec["source_pdf"]).name,
        "description": "OCR converted draft from PDF. Requires admin proofreading before publish.",
        "duration_minutes": None,
        "is_published": False,
        "sort_order": 0,
        "tags": ["ocr-converted", level],
        "parse_meta": {
            "source_pdf": rec["source_pdf"],
            "pages": page_count,
            "ocr_engine": "tesseract",
            "ocr_lang": "jpn",
            "text_length": len(ocr_text),
            "detected_blocks": len(blocks),
            "requires_ocr": False,
        },
        "questions": questions,
    }


def main():
    if not TESSERACT_CMD.exists():
        raise RuntimeError("tesseract executable not found")
    if not (TESSDATA_DIR / "jpn.traineddata").exists():
        raise RuntimeError("jpn.traineddata not found")

    pytesseract.pytesseract.tesseract_cmd = str(TESSERACT_CMD)

    launch = json.loads(LAUNCH_FILE.read_text(encoding="utf-8"))
    recs = launch.get("recommended", [])
    if len(recs) < 3:
        raise RuntimeError("launch recommendation does not contain three papers")

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    index = []
    for rec in recs[:3]:
        pdf = Path(rec["source_pdf"])
        if not pdf.exists():
            raise FileNotFoundError(f"PDF not found: {pdf}")

        text, pages = ocr_pdf(pdf)
        paper = build_paper(rec, text, pages)

        out_file = OUT_DIR / f"{paper['slug']}.json"
        out_file.write_text(json.dumps(paper, ensure_ascii=False, indent=2), encoding="utf-8")

        index.append({
            "slug": paper["slug"],
            "level": paper["level"],
            "year": paper["year"],
            "session": paper["session"],
            "source_pdf": rec["source_pdf"],
            "output_json": str(out_file),
            "questions": len(paper["questions"]),
            "ocr": True,
        })
        print(f"[ocr:jlpt] done -> {out_file.name}")

    index_file = OUT_DIR / "_index.json"
    index_file.write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[ocr:jlpt] index -> {index_file}")


if __name__ == "__main__":
    main()
