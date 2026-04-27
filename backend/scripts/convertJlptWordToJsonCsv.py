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


def norm(s: str) -> str:
    if s is None:
        return ""
    s = str(s)
    s = s.replace("\u3000", " ")
    s = re.sub(r"[ \t]+", " ", s)
    return s.strip()


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


def parse_question_start(line: str):
    line = norm(line)
    m = re.match(r"^(?:第\s*)?(?:問題|问题|問)\s*([0-9]{1,3})\b[\.:：、\)）]?\s*(.*)$", line)
    if m:
        return int(m.group(1)), norm(m.group(2))
    # Support "1番" format used in listening (聴解) sections
    m = re.match(r"^([0-9]{1,3})\s*(?:番|[\.:：、\)）])\s*(.*)$", line)
    if m:
        return int(m.group(1)), norm(m.group(2))
    return None


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

    def flush_current():
        nonlocal current
        if not current:
            return
        # option fallback
        if len(current["options"]) < 2:
            while len(current["options"]) < 2:
                idx = len(current["options"]) + 1
                current["options"].append({"key": str(idx), "text": f"选项{idx}（待校对）"})
        keys = {o["key"] for o in current["options"]}
        if current["answer"] not in keys:
            current["answer"] = current["options"][0]["key"]
        current["prompt"] = norm("\n".join(current["prompt_lines"]))
        current["passage"] = norm("\n".join(current["passage_lines"])) if current["passage_lines"] else ""
        if current.get("transcript_lines"):
            existing = current.get("transcript", "").strip()
            merged = norm("\n".join(current["transcript_lines"]))
            current["transcript"] = (merged + "\n" + existing).strip() if existing else merged
        del current["prompt_lines"]
        del current["passage_lines"]
        del current["transcript_lines"]
        questions.append(current)
        current = None

    for line in question_lines:
        sec = detect_section(line)
        if sec:
            section_type = sec
            continue

        qstart = parse_question_start(line)
        if qstart:
            flush_current()
            qno, text = qstart
            current = {
                "section_type": section_type,
                "section_title": {
                    SECTION_VG: "文字・語彙・文法",
                    SECTION_RD: "読解",
                    SECTION_LS: "聴解",
                }.get(section_type, "読解"),
                "question_group": None,
                "question_no": str(qno),
                "sort_order": len(questions) + 1,
                "prompt_lines": [text] if text else [],
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
            continue

        if not current:
            continue

        opt = parse_option_line(line)
        if opt:
            if opt["key"] not in {o["key"] for o in current["options"]}:
                current["options"].append(opt)
            continue

        # heuristics: treat long content as passage for reading context; listening content goes to transcript
        if current["section_type"] == SECTION_LS and not current["options"]:
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

        qno_match = re.search(r"(?:第\s*([0-9]{1,3})\s*题|問題\s*([0-9]{1,3})|\(([0-9]{1,3})\))", line)
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

    explain_map = {k: norm("\n".join(v)) for k, v in explain_map.items() if v}
    transcript_map = {k: norm("\n".join(v)) for k, v in transcript_map.items() if v}
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
    with open(csv_path, "w", encoding="utf-8-sig", newline="") as f:
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
    lines = [norm(p.text) for p in doc.paragraphs if norm(p.text)]

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

    write_csv(paper, args.output_csv)

    print(f"[done] questions={len(questions)} vg={paper['parse_meta']['section_counts'][SECTION_VG]} rd={paper['parse_meta']['section_counts'][SECTION_RD]} ls={paper['parse_meta']['section_counts'][SECTION_LS]}")
    print(f"[json] {os.path.abspath(args.output_json)}")
    print(f"[csv ] {os.path.abspath(args.output_csv)}")


if __name__ == "__main__":
    main()
