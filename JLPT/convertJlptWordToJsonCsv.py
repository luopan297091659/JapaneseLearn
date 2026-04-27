#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Convert JLPT corrected Word (.docx) to import-ready JSON + CSV.

Key rules:
1) Questions are parsed from section blocks:
   - 第一部分 语彙・文法
   - 第二部分 読解
   - 第三部分 聴解
2) Answer-key block (e.g. "2021年12月日语能力考试 N3 真题答案") is fully ignored.
3) Explanations/transcript are parsed from "真题详解" area and mapped back to questions.
"""

import argparse
import csv
import json
import os
import re
import sys
from datetime import datetime

try:
    from docx import Document
except Exception:
    print("[error] python-docx is required. install: pip install python-docx", file=sys.stderr)
    raise

SECTION_VG = "vocabulary_grammar"
SECTION_RD = "reading"
SECTION_LS = "listening"

FULLWIDTH_TRANS = str.maketrans({
    "０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
    "５": "5", "６": "6", "７": "7", "８": "8", "９": "9",
    "．": ".", "，": ",", "：": ":", "（": "(", "）": ")", "＿": "_",
})


def norm(s: str) -> str:
    if s is None:
        return ""
    s = str(s)
    s = s.translate(FULLWIDTH_TRANS)
    s = s.replace("\u3000", " ")
    s = s.replace("\r", "")
    return s.strip("\n").strip()


def compact(s: str) -> str:
    return re.sub(r"[\s\.。·・、，,:：\-—_]+", "", norm(s)).lower()


def detect_section(line: str):
    c = compact(line)
    if ("第一部分" in c and ("語彙" in c or "语汇" in c or "词汇" in c or "文法" in c or "语法" in c)) or "語彙文法" in c or "词汇语法" in c:
        return SECTION_VG
    if ("第二部分" in c and ("読解" in c or "阅读" in c)) or "読解" in c or "阅读" in c:
        return SECTION_RD
    if ("第三部分" in c and ("聴解" in c or "听解" in c or "听力" in c)) or "聴解" in c or "听解" in c:
        return SECTION_LS
    return None


def is_answer_block_header(line: str) -> bool:
    c = compact(line)
    return ("真题答案" in c) or ("真題答案" in c) or ("能力考试" in c and "答案" in c)


def is_explain_block_header(line: str) -> bool:
    c = compact(line)
    return ("真题详解" in c) or ("真題詳解" in c) or ("答案详解" in c)


def normalize_u_tags(text: str) -> str:
    """Normalize <u> tags and auto-close dangling underline tags."""
    s = norm(text)
    if not s:
        return s

    token_pattern = re.compile(r"(<\s*/?\s*u\s*>)", flags=re.IGNORECASE)
    parts = token_pattern.split(s)
    out = []
    depth = 0

    for part in parts:
        if not part:
            continue
        low = part.lower()
        if re.fullmatch(r"<\s*u\s*>", low):
            out.append("<u>")
            depth += 1
            continue
        if re.fullmatch(r"<\s*/\s*u\s*>", low):
            if depth > 0:
                out.append("</u>")
                depth -= 1
            continue
        out.append(part)

    if depth > 0:
        out.append("</u>" * depth)

    return "".join(out)


def is_explain_subsection_header(line: str) -> bool:
    c = compact(line)
    return (
        "词汇语法部分" in c
        or "語彙文法部分" in c
        or "読解部分" in c
        or "阅读部分" in c
        or "听力原文" in c
        or "聴解原文" in c
    )


def parse_question_start(line: str):
    line = norm(line)
    # Support "1番" format used in listening (聴解) sections
    m = re.match(r"^([0-9]{1,3})\s*(?:番|[\.:：、\)）]|\s)\s*(.*)$", line)
    if m:
        return int(m.group(1)), norm(m.group(2))
    return None


def parse_question_group_title(line: str):
    """Detect subgroup title like 問題 1 / 問 題 3 / 问题 2 and return remainder text."""
    line = norm(line)
    m = re.match(r"^(?:問題|问題|问题|問\s*題)\s*([0-9]{1,2})(.*)$", line)
    if m:
        title = f"問題 {m.group(1)}"
        remainder = norm(m.group(2))
        return title, remainder
    return None


def is_pure_question_group_title(line: str) -> bool:
    """Standalone group header like '問題 1' should be ignored directly."""
    line = norm(line)
    return bool(re.match(r"^(?:問題|问題|问题|問\s*題)\s*[0-9]{1,2}\s*$", line))


def paragraph_to_text(paragraph):
    parts = []
    for run in paragraph.runs:
        txt = (run.text or "").replace("\u3000", " ").translate(FULLWIDTH_TRANS)
        if run.underline:
            if txt and txt.strip() == "":
                # Word 中“只有下划线没有文字”的空白占位，转成可见下划线长度。
                count = len(txt)
                parts.append(f"<u>{'_' * max(3, count)}</u>")
            elif txt:
                # 保留下划线文字，用于前端渲染（管理员端/官网）。
                parts.append(f"<u>{txt}</u>")
            continue

        parts.append(txt)
    text = "".join(parts)
    if not text:
        text = paragraph.text or ""
    return normalize_u_tags(text)


def normalize_answer_token(token: str) -> str:
    t = norm(token)
    mapping = {
        "①": "1", "❶": "1", "Ａ": "1", "A": "1",
        "②": "2", "❷": "2", "Ｂ": "2", "B": "2",
        "③": "3", "❸": "3", "Ｃ": "3", "C": "3",
        "④": "4", "❹": "4", "Ｄ": "4", "D": "4",
    }
    return mapping.get(t, t)


def parse_option_line(line: str):
    s = norm(line)
    m = re.match(r"^(?:\(?([1-4])\)?|([①②③④])|([Ａ-ＤA-D]))[\.:：、\)）\s]+(.+)$", s)
    if not m:
        return None
    key = m.group(1) or m.group(2) or m.group(3)
    key = normalize_answer_token(key)
    text = norm(m.group(4))
    if not text:
        return None
    return {"key": key, "text": text}


def parse_inline_options(line: str):
    """
    Parse inline options in one line, e.g.:
    1. ...    2. ...    3. ...    4. ...
    """
    s = norm(line)
    pattern = re.compile(r"(?:(?<=^)|(?<=\s))([1-4])[\.|．、:：\)）]\s*")
    matches = list(pattern.finditer(s))
    if len(matches) < 2:
        return []

    options = []
    # If first option marker is not 1, keep preamble as option 1 text.
    first_start = matches[0].start()
    if first_start > 0:
        preamble = s[:first_start].strip()
        first_key = normalize_answer_token(matches[0].group(1))
        if preamble and first_key != "1":
            options.append({"key": "1", "text": preamble})

    for i, m in enumerate(matches):
        key = normalize_answer_token(m.group(1))
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(s)
        text = s[start:end].strip()
        if text:
            options.append({"key": key, "text": text})
    return options


def split_embedded_group_headers(line: str):
    """Split if a group header appears in the middle of a line."""
    line = norm(line)
    pattern = re.compile(r"(?=(?:問\s*題|問題|问题|问\s*题)\s*\d{1,2})")
    chunks = [c.strip() for c in pattern.split(line) if c.strip()]
    return chunks or [line]


def split_by_expected_question(line: str, expected_qno: int):
    """Split line when next expected question number appears in the middle."""
    if expected_qno < 5:
        return [line]
    s = norm(line)
    # Also match "N番" format used in listening sections
    pattern = re.compile(rf"(?<!\d){expected_qno}\s*(?:番|[\.|、])\s*")
    m = pattern.search(s)
    if m and m.start() > 0:
        left = s[:m.start()].strip()
        right = s[m.start():].strip()
        parts = []
        if left:
            parts.append(left)
        if right:
            parts.append(right)
        return parts
    return [s]


def split_doc_zones(lines):
    zone = "before_questions"
    zones = {
        "questions": [],
        "answers": [],
        "explain": [],
    }
    for raw in lines:
        line = norm(raw)
        if not line:
            continue

        if is_answer_block_header(line):
            zone = "answers"
            continue

        if is_explain_block_header(line):
            zone = "explain"
            continue

        if zone == "before_questions":
            # start collecting when first section appears
            if detect_section(line):
                zone = "questions"
                zones["questions"].append(line)
            continue

        zones[zone].append(line)

    return zones


def parse_questions(question_lines):
    questions = []
    current = None
    section_type = SECTION_VG
    current_group_title = None
    expected_question_no = 1
    pending_inferred_stem = None
    pending_group_instruction = None

    def flush_current():
        nonlocal current
        if not current:
            return
        if len(current["options"]) < 2:
            while len(current["options"]) < 2:
                idx = len(current["options"]) + 1
                current["options"].append({"key": str(idx), "text": f"选项{idx}（待校对）"})
        keys = {o["key"] for o in current["options"]}
        if current["answer"] not in keys:
            current["answer"] = current["options"][0]["key"]
        current["prompt"] = "\n".join(current["prompt_lines"]).strip()
        current["passage"] = "\n".join(current["passage_lines"]).strip() if current["passage_lines"] else ""
        # Listening section: pre-option text goes to transcript; don't overwrite if already set from explanation zone
        if current.get("transcript_lines"):
            existing = current.get("transcript", "").strip()
            merged = "\n".join(current["transcript_lines"]).strip()
            current["transcript"] = (merged + "\n" + existing).strip() if existing else merged
        del current["prompt_lines"]
        del current["passage_lines"]
        del current["transcript_lines"]
        questions.append(current)
        current = None

    def start_new_question(qno: int, text: str):
        nonlocal current, expected_question_no, pending_inferred_stem, pending_group_instruction
        flush_current()
        pending_inferred_stem = None
        initial_prompt_lines = []
        if pending_group_instruction:
            initial_prompt_lines.append(pending_group_instruction)
            pending_group_instruction = None
        if text:
            initial_prompt_lines.append(text)
        current = {
            "section_type": section_type,
            "section_title": {
                SECTION_VG: "文字・語彙・文法",
                SECTION_RD: "読解",
                SECTION_LS: "聴解",
            }.get(section_type, "読解"),
            "question_group": current_group_title,
            "question_no": str(qno),
            "sort_order": len(questions) + 1,
            "prompt_lines": initial_prompt_lines,
            "passage_lines": [],
            "transcript_lines": [],
            "transcript": "",
            "options": [],
            "answer": "1",
            "explanation": "",
            "explanation_zh": "",
            "knowledge_points": [],
            "score": 1,
            "meta_json": {"source_question_no": str(qno)},
        }
        expected_question_no = qno + 1

    for original_line in question_lines:
        segments = []
        for chunk in split_embedded_group_headers(original_line):
            segments.extend(split_by_expected_question(chunk, expected_question_no))

        for line in segments:
            sec = detect_section(line)
            if sec:
                section_type = sec
                pending_inferred_stem = None
                continue

            # Treat standalone '問題 + number' as pure type description and skip.
            if is_pure_question_group_title(line):
                continue

            group_title = parse_question_group_title(line)
            if group_title:
                current_group_title, remainder = group_title
                pending_inferred_stem = None
                if not remainder:
                    continue
                maybe_q = parse_question_start(remainder)
                if maybe_q and maybe_q[0] == expected_question_no:
                    line = remainder
                else:
                    pending_group_instruction = remainder
                    continue

            qstart = parse_question_start(line)
            if qstart and qstart[0] == expected_question_no:
                qno, text = qstart
                start_new_question(qno, text)
                continue

            if not current:
                continue

            inline_options = parse_inline_options(line)

            # Recover missing question number only when a pending stem is
            # immediately followed by option-1 style line.
            if pending_inferred_stem and len(current["options"]) >= 4:
                starts_with_opt1 = False
                if inline_options:
                    starts_with_opt1 = any(opt.get("key") == "1" for opt in inline_options)
                else:
                    single = parse_option_line(line)
                    starts_with_opt1 = bool(single and single.get("key") == "1")
                if starts_with_opt1:
                    start_new_question(expected_question_no, pending_inferred_stem)
                    inline_options = parse_inline_options(line)

            if inline_options:
                seen = {o["key"] for o in current["options"]}
                for opt in inline_options:
                    if opt["key"] not in seen:
                        current["options"].append(opt)
                        seen.add(opt["key"])
                continue

            opt = parse_option_line(line)
            if opt:
                if opt["key"] not in {o["key"] for o in current["options"]}:
                    current["options"].append(opt)
                continue

            # Cache possible missing-number stem and wait for next option line.
            if len(current["options"]) >= 4 and expected_question_no <= 60 and len(line) >= 2:
                pending_inferred_stem = line
                continue

            if current["section_type"] == SECTION_LS and not current["options"]:
                # Listening: pre-option text is audio transcript, not passage/prompt
                current["transcript_lines"].append(line)
            elif current["section_type"] == SECTION_RD and len(line) >= 24 and not current["options"]:
                current["passage_lines"].append(line)
            else:
                current["prompt_lines"].append(line)

    flush_current()

    # resequence sort_order
    for idx, q in enumerate(questions, start=1):
        q["sort_order"] = idx

    return questions


def parse_explanations(explain_lines):
    answer_map = {}
    explain_map = {}
    transcript_map = {}

    current_q = None
    transcript_mode = False

    for line in explain_lines:
        c = compact(line)
        if "听力原文" in c or "聴解原文" in c:
            transcript_mode = True
            continue
        if ("词汇" in c and "语法" in c) or ("語彙" in c and "文法" in c) or ("読解" in c):
            transcript_mode = False
        if is_explain_subsection_header(line):
            continue

        qno_match = re.search(
            r"(?:^\(\s*([0-9]{1,3})\s*\)|第\s*([0-9]{1,3})\s*题|\(([0-9]{1,3})\))",
            line,
        )
        if qno_match:
            current_q = next((g for g in qno_match.groups() if g), None)

        ans_match = re.search(r"(?:正解|答案|解答)\s*[:：]\s*([1-4①②③④Ａ-ＤA-D])", line)
        if ans_match and current_q:
            answer_map[current_q] = normalize_answer_token(ans_match.group(1))

        if current_q:
            if transcript_mode:
                transcript_map.setdefault(current_q, []).append(line)
            else:
                explain_map.setdefault(current_q, []).append(line)

    explain_map = {k: "\n".join(v).strip() for k, v in explain_map.items() if v}
    transcript_map = {k: "\n".join(v).strip() for k, v in transcript_map.items() if v}
    return answer_map, explain_map, transcript_map


def apply_explanation_to_questions(questions, answer_map, explain_map, transcript_map):
    for q in questions:
        qno = str(q.get("meta_json", {}).get("source_question_no") or q.get("question_no"))
        if qno in answer_map:
            cand = answer_map[qno]
            keys = {o["key"] for o in q["options"]}
            if cand in keys:
                q["answer"] = cand
                q.setdefault("meta_json", {})["answer_source"] = "word-explanation"
        if qno in explain_map:
            q["explanation"] = explain_map[qno]
            q["explanation_zh"] = explain_map[qno]
        if qno in transcript_map:
            q["transcript"] = transcript_map[qno]


def build_paper(args, questions, source_path):
    return {
        "title": args.title,
        "slug": args.slug,
        "level": args.level,
        "year": int(args.year),
        "session": args.session,
        "description": args.description,
        "duration_minutes": args.duration,
        "source_label": args.source_label,
        "sort_order": args.sort_order,
        "is_published": bool(args.publish),
        "tags": [t.strip() for t in (args.tags or "").split(",") if t.strip()],
        "parse_meta": {
            "source_docx": os.path.abspath(source_path),
            "extracted_at": datetime.now().isoformat(timespec="seconds"),
            "section_counts": {
                SECTION_VG: sum(1 for q in questions if q["section_type"] == SECTION_VG),
                SECTION_RD: sum(1 for q in questions if q["section_type"] == SECTION_RD),
                SECTION_LS: sum(1 for q in questions if q["section_type"] == SECTION_LS),
            },
            "total_questions": len(questions),
        },
        "questions": questions,
    }


def write_csv(paper, csv_path):
    columns = [
        "paper_slug", "paper_title", "level", "year", "session",
        "section_type", "section_title", "question_group", "question_no", "sort_order",
        "prompt", "passage", "transcript",
        "option_1", "option_2", "option_3", "option_4",
        "answer", "explanation", "explanation_zh",
        "score", "source_question_no",
        "paper_description", "source_label", "paper_tags", "is_published",
    ]

    os.makedirs(os.path.dirname(os.path.abspath(csv_path)), exist_ok=True)
    def _write(target_path):
        with open(target_path, "w", encoding="utf-8-sig", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=columns)
            writer.writeheader()
            for q in paper["questions"]:
                option_map = {o["key"]: o["text"] for o in q.get("options", [])}
                writer.writerow({
                    "paper_slug": paper["slug"],
                    "paper_title": paper["title"],
                    "level": paper["level"],
                    "year": paper["year"],
                    "session": paper["session"],
                    "section_type": q.get("section_type", ""),
                    "section_title": q.get("section_title", ""),
                    "question_group": q.get("question_group", ""),
                    "question_no": q.get("question_no", ""),
                    "sort_order": q.get("sort_order", ""),
                    "prompt": q.get("prompt", ""),
                    "passage": q.get("passage", ""),
                    "transcript": q.get("transcript", ""),
                    "option_1": option_map.get("1", ""),
                    "option_2": option_map.get("2", ""),
                    "option_3": option_map.get("3", ""),
                    "option_4": option_map.get("4", ""),
                    "answer": q.get("answer", ""),
                    "explanation": q.get("explanation", ""),
                    "explanation_zh": q.get("explanation_zh", ""),
                    "score": q.get("score", 1),
                    "source_question_no": q.get("meta_json", {}).get("source_question_no", ""),
                    "paper_description": paper.get("description", ""),
                    "source_label": paper.get("source_label", ""),
                    "paper_tags": ",".join(paper.get("tags", [])),
                    "is_published": "1" if paper.get("is_published") else "0",
                })

    try:
        _write(csv_path)
        return csv_path
    except PermissionError:
        base, ext = os.path.splitext(csv_path)
        fallback = f"{base}_{datetime.now().strftime('%Y%m%d_%H%M%S')}{ext}"
        _write(fallback)
        return fallback


def derive_slug(docx_path, level, year, session):
    name = os.path.splitext(os.path.basename(docx_path))[0]
    s = re.sub(r"[^a-zA-Z0-9]+", "-", name).strip("-").lower()
    if not s:
        s = f"{level.lower()}-{year}-{session}"
    return s[:120]


def main():
    parser = argparse.ArgumentParser(description="Convert JLPT corrected Word to JSON/CSV")
    parser.add_argument("--input", required=True, help="Path to .docx file")
    parser.add_argument("--output-json", required=True, help="Output json path")
    parser.add_argument("--output-csv", required=True, help="Output csv path")
    parser.add_argument("--level", required=True, choices=["N1", "N2", "N3", "N4", "N5"])
    parser.add_argument("--year", required=True, type=int)
    parser.add_argument("--session", default="other", choices=["07", "12", "other"])
    parser.add_argument("--title", default="")
    parser.add_argument("--slug", default="")
    parser.add_argument("--description", default="")
    parser.add_argument("--duration", default=0, type=int)
    parser.add_argument("--source-label", default="Word人工校对")
    parser.add_argument("--tags", default="word,manual-reviewed")
    parser.add_argument("--sort-order", default=0, type=int)
    parser.add_argument("--publish", action="store_true")
    args = parser.parse_args()

    if not os.path.exists(args.input):
        raise FileNotFoundError(f"input not found: {args.input}")

    doc = Document(args.input)
    lines = [paragraph_to_text(p) for p in doc.paragraphs if paragraph_to_text(p)]

    zones = split_doc_zones(lines)
    questions = parse_questions(zones["questions"])

    if not questions:
        raise RuntimeError("No questions parsed from question section")

    answer_map, explain_map, transcript_map = parse_explanations(zones["explain"])
    apply_explanation_to_questions(questions, answer_map, explain_map, transcript_map)

    slug = args.slug or derive_slug(args.input, args.level, args.year, args.session)
    title = args.title or f"{args.level} {args.year}-{args.session} 模拟测验"
    args.slug = slug
    args.title = title

    paper = build_paper(args, questions, args.input)

    os.makedirs(os.path.dirname(os.path.abspath(args.output_json)), exist_ok=True)
    with open(args.output_json, "w", encoding="utf-8") as f:
        json.dump(paper, f, ensure_ascii=False, indent=2)

    csv_written = write_csv(paper, args.output_csv)

    print(f"[done] questions={len(questions)} vg={paper['parse_meta']['section_counts'][SECTION_VG]} rd={paper['parse_meta']['section_counts'][SECTION_RD]} ls={paper['parse_meta']['section_counts'][SECTION_LS]}")
    print(f"[json] {os.path.abspath(args.output_json)}")
    print(f"[csv ] {os.path.abspath(csv_written)}")


if __name__ == "__main__":
    main()
