import fitz
import pytesseract
from pathlib import Path
from PIL import Image

pdf = Path(r'D:\JLPT\N2\N2 2019年7月真题+答案+详解+听力原文_.pdf')
out = Path(r'D:\PROJECT\JapaneseLearn\temp_jlpt_json_ocr3\_probe_n2_answers.txt')
pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'
tess = r'D:\PROJECT\JapaneseLearn\tools\tessdata'

doc = fitz.open(pdf)
start = max(0, doc.page_count - 10)
parts = []
for i in range(start, doc.page_count):
    page = doc[i]
    pix = page.get_pixmap(matrix=fitz.Matrix(2, 2), alpha=False)
    img = Image.frombytes('RGB', [pix.width, pix.height], pix.samples)
    txt = pytesseract.image_to_string(img, lang='jpn', config=f'--oem 1 --psm 6 --tessdata-dir {tess}')
    parts.append(f'---P{i+1}---\n' + txt)
out.write_text('\n'.join(parts), encoding='utf-8')
