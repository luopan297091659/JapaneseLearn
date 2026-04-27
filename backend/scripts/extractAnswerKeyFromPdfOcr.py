#!/usr/bin/env python3
import json
import re
from pathlib import Path

import fitz
import pytesseract
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INPUT = ROOT / 'temp_jlpt_json_ocr3'
TESSERACT_CMD = Path(r'C:\Program Files\Tesseract-OCR\tesseract.exe')
TESSDATA_DIR = ROOT / 'tools' / 'tessdata'

FULLWIDTH = str.maketrans('０１２３４５６７８９', '0123456789')
DIGIT_FIX = str.maketrans({
    '@': '6',
    'O': '0',
    'o': '0',
    'I': '1',
    'l': '1',
    '|': '1',
    '!': '1',
    'S': '5',
    'B': '8',
    'G': '6',
    'q': '9',
})
ANSWER_MAP = {
    '①': '1', '②': '2', '③': '3', '④': '4',
    'A': '1', 'B': '2', 'C': '3', 'D': '4',
    'Ａ': '1', 'Ｂ': '2', 'Ｃ': '3', 'Ｄ': '4',
}


def normalize_number_token(token: str):
    token = str(token or '').translate(FULLWIDTH).translate(DIGIT_FIX)
    token = re.sub(r'[^0-9]', '', token)
    if not token:
        return None
    value = int(token)
    if 0 < value <= 99:
        return value
    if len(token) >= 2:
        tail = int(token[-2:])
        if 0 < tail <= 99:
            return tail
    return value


def normalize_answer_token(token: str):
    token = str(token or '').strip()
    token = ANSWER_MAP.get(token, token)
    m = re.search(r'[1-4]', token)
    return m.group(0) if m else None


def compact_text(text: str):
    text = str(text or '').replace('\x00', '').replace('\r', '')
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def ocr_answer_pages(pdf_path: Path):
    doc = fitz.open(pdf_path)
    texts = []
    start = max(0, doc.page_count - 10)
    try:
        for i in range(start, doc.page_count):
            page = doc[i]
            pix = page.get_pixmap(matrix=fitz.Matrix(2, 2), alpha=False)
            img = Image.frombytes('RGB', [pix.width, pix.height], pix.samples)
            text = pytesseract.image_to_string(
                img,
                lang='jpn',
                config=f'--oem 1 --psm 6 --tessdata-dir {TESSDATA_DIR}',
            )
            texts.append(f'---P{i + 1}---\n{text}')
    finally:
        doc.close()
    return compact_text('\n'.join(texts))


def extract_answer_pairs(text: str):
    pairs = {}
    patterns = [
        re.compile(r'[\(（]\s*([0-9@OoIl|!SBGq０-９]{1,3})\s*[\)）]\s*[\.,，。]*\s*正解\s*[:：,，。]*\s*([1-4①-④Ａ-ＤA-D])', re.U),
        re.compile(r'問題\s*([0-9@OoIl|!SBGq０-９]{1,3})\s*[\(（]\s*([0-9@OoIl|!SBGq０-９]{1,3})\s*[\)）]\s*[\.,，。]*\s*正解\s*[:：,，。]*\s*([1-4①-④Ａ-ＤA-D])', re.U),
        re.compile(r'([0-9@OoIl|!SBGq０-９]{1,2})\s*番\s*[:：]?[^\n]{0,120}?正解\s*[:：,，]?\s*([1-4①-④Ａ-ＤA-D])', re.U),
    ]

    for m in patterns[0].finditer(text):
        q_no = normalize_number_token(m.group(1))
        answer = normalize_answer_token(m.group(2))
        if q_no and answer:
            pairs[q_no] = answer

    for m in patterns[1].finditer(text):
        q_no = normalize_number_token(m.group(2))
        answer = normalize_answer_token(m.group(3))
        if q_no and answer:
            pairs[q_no] = answer

    listening = {}
    for m in patterns[2].finditer(text):
        q_no = normalize_number_token(m.group(1))
        answer = normalize_answer_token(m.group(2))
        if q_no and answer:
            listening[q_no] = answer

    return pairs, listening


def extract_source_number(question: dict):
    source = '\n'.join([
        str(question.get('prompt') or ''),
        str(question.get('passage') or ''),
        str(question.get('transcript') or ''),
    ])

    patterns = [
        re.compile(r'問題\s*[0-9@OoIl|!SBGq０-９]+\s*[\(（]\s*([0-9@OoIl|!SBGq０-９]{1,3})', re.U),
        re.compile(r'[\(（]\s*([0-9@OoIl|!SBGq０-９]{1,3})\s*[\)）]\s*正解', re.U),
        re.compile(r'([0-9@OoIl|!SBGq０-９]{1,2})\s*番', re.U),
    ]

    for idx, pattern in enumerate(patterns):
        m = pattern.search(source)
        if m:
            value = normalize_number_token(m.group(1))
            if value:
                return value, 'listening' if idx == 2 else 'regular'
    return None, None


def apply_answer_map(json_path: Path):
    data = json.loads(json_path.read_text(encoding='utf-8'))
    source_pdf = Path((data.get('parse_meta') or {}).get('source_pdf') or '')
    if not source_pdf.exists():
        raise FileNotFoundError(f'source pdf not found for {json_path.name}: {source_pdf}')

    answer_text = ocr_answer_pages(source_pdf)
    regular_map, listening_map = extract_answer_pairs(answer_text)

    updated = 0
    resolved = 0
    for question in data.get('questions', []):
        source_no, source_kind = extract_source_number(question)
        if not source_no:
            continue
        resolved += 1
        answer = None
        if question.get('section_type') == 'listening' and source_kind == 'listening':
            answer = listening_map.get(source_no)
        if not answer:
            answer = regular_map.get(source_no)
        if not answer and question.get('section_type') == 'listening':
            answer = listening_map.get(source_no)

        if answer:
            question['answer'] = answer
            meta_json = question.get('meta_json') or {}
            meta_json['answer_source'] = 'answer-page-ocr'
            meta_json['source_question_no'] = source_no
            question['meta_json'] = meta_json
            updated += 1

    parse_meta = data.get('parse_meta') or {}
    parse_meta['answer_page_pair_count'] = len(regular_map)
    parse_meta['answer_page_listening_pair_count'] = len(listening_map)
    parse_meta['answer_page_apply_resolved'] = resolved
    parse_meta['answer_page_apply_updated'] = updated
    data['parse_meta'] = parse_meta

    json_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    return {
        'file': json_path.name,
        'regular_pairs': len(regular_map),
        'listening_pairs': len(listening_map),
        'resolved': resolved,
        'updated': updated,
    }


def main():
    if not TESSERACT_CMD.exists():
        raise RuntimeError('tesseract not found')
    if not (TESSDATA_DIR / 'jpn.traineddata').exists():
        raise RuntimeError('jpn.traineddata not found')

    pytesseract.pytesseract.tesseract_cmd = str(TESSERACT_CMD)

    input_dir = DEFAULT_INPUT
    files = sorted([p for p in input_dir.glob('*.json') if not p.name.startswith('_')])
    if not files:
        raise RuntimeError(f'no json files found in {input_dir}')

    for file in files:
        result = apply_answer_map(file)
        print(f"[answer-page-ocr] {result['file']} regular={result['regular_pairs']} listening={result['listening_pairs']} updated={result['updated']} resolved={result['resolved']}")


if __name__ == '__main__':
    main()
