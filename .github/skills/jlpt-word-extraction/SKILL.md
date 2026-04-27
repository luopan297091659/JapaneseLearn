---
name: jlpt-word-extraction
description: 'Extract JLPT papers from corrected Word (.docx) into admin-ready JSON and CSV. Use when document contains question sections (第一部分語彙・文法, 第二部分読解, 第三部分聴解), an answer-key block to skip, and explanation blocks (真题详解, 词汇语法, 読解, 听力原文).'
argument-hint: 'Input docx path, jlpt level, year/session, output directory'
user-invocable: true
---

# JLPT Word Extraction

## Purpose
Build a repeatable pipeline to parse manually corrected JLPT Word files and generate:
- exam JSON for import script compatibility
- CSV exports for admin-side bulk operations and auditing

## When To Use
Use this skill when the source is a corrected .docx and follows this structure:
1. Question sections:
- 第一部分 語彙・文法
- 第二部分 読解
- 第三部分 聴解
2. An answer block like:
- 2021年12月日语能力考试 N3 真题答案
- This block must be fully ignored.
3. Explanation sections (some content may be image-based):
- 2021年12月日语能力考试 N3 真题详解
- 词汇/语法部分
- 読解部分
- 听力原文

## Inputs
- docxPath: source Word file path
- level: N1/N2/N3/N4/N5
- year: exam year
- session: 07/12/other
- title/slug metadata
- outputDir

## Core Strategy
1. Parse Word by ordered blocks, not plain text only.
- Read paragraphs + tables in original order.
- Keep block type metadata: paragraph/table/image-placeholder.

2. Segment document into three logical zones.
- Zone A: questions (from first section header until answer-key header)
- Zone B: answer-key area (must be dropped)
- Zone C: explanations/transcripts (from 真题详解 header to end)

3. Extract questions from Zone A by section.
- Map section headers to:
  - vocabulary_grammar
  - reading
  - listening
- Split question blocks by stable anchors: 問題\d+, 問\d+, or normalized number headings.
- Parse options into normalized array:
  - [{ key: '1', text: '...' }, { key: '2', text: '...' }, ...]
- Enforce minimum 2 options; auto-fill placeholder options only if source is incomplete.

4. Ignore Zone B entirely.
- Do not read or merge any answer-key content from the 真题答案 block.
- Prevent accidental answer contamination.

5. Extract explanations from Zone C.
- Build explanation map keyed by source question number.
- Parse sub-sections:
  - 词汇语法详解
  - 読解详解
  - 听力原文
- If image-only block exists, emit review placeholder and keep unresolved flag.

6. Merge question + explanation.
- For each question:
  - fill explanation/explanation_zh/transcript when matched
  - preserve source_question_no in meta_json

7. Export two output formats.
- JSON (import-ready):
  - paper metadata + questions[] compatible with importJlptJsonToDb.js
- CSV (admin-compatible):
  - required columns:
    - paper_slug,paper_title,level,year,session
    - section_type,question_no,question_group,prompt,passage,transcript
    - option_1,option_2,option_3,option_4
    - answer,explanation,explanation_zh,score,source_question_no

## Decision Points
- If section header variants are inconsistent:
  - apply normalized fuzzy matching (remove spaces/punctuation, full-width conversion).
- If options are not explicitly 1/2/3/4:
  - infer by line order and assign keys 1..n.
- If explanation cannot map to question:
  - keep unmatched bucket in parse_meta.unmatched_explanations.
- If answer appears only in filtered Zone B:
  - keep default answer and mark answer_source=unresolved (no import of Zone B answer key).

## Quality Gates (Completion Checks)
- Question counts by section are non-zero and plausible.
- Every question has:
  - section_type
  - question_no
  - prompt
  - options array with >=2 items
- No content from 真题答案 block appears in final prompt/explanation/transcript.
- CSV row count equals JSON question count.
- parse_meta includes:
  - source_docx
  - extracted_at
  - section_counts
  - unresolved_items summary

## Integration Targets
- Python extraction script: extend or create a Word-first parser (docx -> normalized structure).
- Existing import path compatibility:
  - backend/scripts/importJlptJsonToDb.js
- Admin upload compatibility:
  - support CSV import using the defined flat columns.

## Suggested Prompt Examples
- 从这个 N3 docx 提取试题，过滤真题答案区，输出 JSON+CSV。
- 解析 Word 真题详解并回填到 questions，未匹配项写到 parse_meta。
- 生成管理员可导入 CSV，确保字段和 section_type 标准化。
