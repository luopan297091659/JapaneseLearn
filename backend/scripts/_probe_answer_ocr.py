import fitz
import pytesseract
import re
from pathlib import Path
from PIL import Image

out = Path(r'D:\PROJECT\JapaneseLearn\temp_jlpt_json_ocr3\_probe_n1_answers.txt')

p = Path(r'D:\JLPT\N1\N1 2019年7月真题+答案+详解+听力原文.pdf')
pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'
tess = r'D:\PROJECT\JapaneseLearn\tools\tessdata'

doc = fitz.open(p)
start = max(0, doc.page_count - 8)
parts = []
for i in range(start, doc.page_count):
    page = doc[i]
    pix = page.get_pixmap(matrix=fitz.Matrix(2, 2), alpha=False)
    img = Image.frombytes('RGB', [pix.width, pix.height], pix.samples)
    txt = pytesseract.image_to_string(img, lang='jpn', config=f'--oem 1 --psm 6 --tessdata-dir {tess}')
    parts.append(f'---P{i+1}---\n' + txt)

text = '\n'.join(parts)
summary = []
summary.append(text[:12000])
summary.append('\nTOKENS: ' + str(re.findall(r'(?<!\d)[1-4](?!\d)', text)[:120]))
summary.append('COUNT=' + str(len(re.findall(r'(?<!\d)[1-4](?!\d)', text))))
out.write_text('\n'.join(summary), encoding='utf-8')
