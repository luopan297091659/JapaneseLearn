"""
语法例句TTS音频生成工具
使用edge-tts生成日语音频，输出UUID->sentence映射和音频文件
"""

import asyncio
import json
import os
import sys
import uuid
from pathlib import Path

import edge_tts

VOICE = "ja-JP-NanamiNeural"  # 高质量日语女声
PROJECT_ROOT = Path(__file__).parent.parent.parent  # d:\PROJECT\JapaneseLearn
OUTPUT_DIR = PROJECT_ROOT / "temp_grammar_audio"
MAPPING_FILE = PROJECT_ROOT / "temp_grammar_audio_map.json"
SQL_UPDATE_FILE = PROJECT_ROOT / "temp_grammar_audio_update.sql"

# 从SQL文件中提取例句ID和句子
def load_examples_from_sql():
    """从导入SQL中提取grammar_examples的id和sentence"""
    sql_file = PROJECT_ROOT / "temp_grammar_import.sql"
    examples = []
    with open(sql_file, 'r', encoding='utf-8') as f:
        for line in f:
            if line.startswith("INSERT INTO grammar_examples"):
                # 解析 VALUES ('id', 'lesson_id', 'sentence', 'reading', 'meaning_zh', NULL, NOW(), NOW());
                try:
                    vals_start = line.index("VALUES (") + 8
                    vals_end = line.rindex(");")
                    vals_str = line[vals_start:vals_end]
                    
                    # 解析SQL值 - 提取id和sentence
                    parts = parse_sql_values(vals_str)
                    if len(parts) >= 3:
                        ex_id = parts[0]
                        sentence = parts[2]
                        if sentence and sentence != 'NULL':
                            examples.append({
                                'id': ex_id,
                                'sentence': sentence
                            })
                except Exception as e:
                    pass
    return examples


def parse_sql_values(vals_str):
    """解析SQL VALUES中的值，处理转义引号"""
    parts = []
    i = 0
    while i < len(vals_str):
        # 跳过空格和逗号
        while i < len(vals_str) and vals_str[i] in (' ', ','):
            i += 1
        if i >= len(vals_str):
            break
            
        if vals_str[i] == "'":
            # 字符串值
            i += 1  # 跳过开始引号
            val = []
            while i < len(vals_str):
                if vals_str[i] == '\\' and i + 1 < len(vals_str):
                    val.append(vals_str[i+1])
                    i += 2
                elif vals_str[i] == "'":
                    i += 1  # 跳过结束引号
                    break
                else:
                    val.append(vals_str[i])
                    i += 1
            parts.append(''.join(val))
        elif vals_str[i:i+4] == 'NULL':
            parts.append(None)
            i += 4
        elif vals_str[i:i+5] == 'NOW()':
            parts.append('NOW()')
            i += 5
        else:
            # 数字或其他
            j = i
            while j < len(vals_str) and vals_str[j] not in (',', ')'):
                j += 1
            parts.append(vals_str[i:j].strip())
            i = j
    return parts


async def generate_audio(text, output_path, voice=VOICE):
    """生成单个TTS音频"""
    communicate = edge_tts.Communicate(text, voice)
    await communicate.save(str(output_path))


async def main():
    print("=== 语法例句TTS音频生成工具 ===\n")
    
    # 1. 加载例句
    print("1. 加载例句数据...")
    examples = load_examples_from_sql()
    print(f"   共 {len(examples)} 条例句需要生成TTS")
    
    # 2. 创建输出目录
    OUTPUT_DIR.mkdir(exist_ok=True)
    
    # 3. 检查已生成的文件（支持断点续传）
    existing = set()
    mapping = {}
    if MAPPING_FILE.exists():
        with open(MAPPING_FILE, 'r', encoding='utf-8') as f:
            mapping = json.load(f)
        existing = set(mapping.keys())
        print(f"   已有 {len(existing)} 条已生成，跳过")
    
    # 筛选需要生成的
    to_generate = [ex for ex in examples if ex['id'] not in existing]
    print(f"   待生成: {len(to_generate)} 条\n")
    
    if not to_generate:
        print("   所有音频已生成！")
    else:
        # 4. 批量生成TTS
        print("2. 生成TTS音频...")
        success = 0
        failed = 0
        
        for i, ex in enumerate(to_generate):
            audio_filename = f"{ex['id']}.mp3"
            output_path = OUTPUT_DIR / audio_filename
            
            try:
                await generate_audio(ex['sentence'], output_path)
                mapping[ex['id']] = {
                    'filename': audio_filename,
                    'sentence': ex['sentence'],
                    'audio_url': f"/uploads/audio/grammar/{audio_filename}"
                }
                success += 1
            except Exception as e:
                print(f"   ✗ 失败: {ex['sentence'][:30]}... - {e}")
                failed += 1
            
            # 每50条进度报告 + 保存映射（断点续传）
            if (i + 1) % 50 == 0:
                print(f"   进度: {i+1}/{len(to_generate)} (成功: {success}, 失败: {failed})")
                # 保存映射文件
                with open(MAPPING_FILE, 'w', encoding='utf-8') as f:
                    json.dump(mapping, f, ensure_ascii=False, indent=2)
        
        # 最终保存
        with open(MAPPING_FILE, 'w', encoding='utf-8') as f:
            json.dump(mapping, f, ensure_ascii=False, indent=2)
        
        print(f"\n   ✓ 生成完成: 成功 {success}, 失败 {failed}")
    
    # 5. 生成SQL更新语句
    print("\n3. 生成音频URL更新SQL...")
    sql_lines = ["SET NAMES utf8mb4;", ""]
    for ex_id, info in mapping.items():
        audio_url = info['audio_url'].replace("'", "\\'")
        sql_lines.append(
            f"UPDATE grammar_examples SET audio_url = '{audio_url}' WHERE id = '{ex_id}';"
        )
    
    with open(SQL_UPDATE_FILE, 'w', encoding='utf-8') as f:
        f.write('\n'.join(sql_lines))
    
    print(f"   ✓ SQL更新文件: {SQL_UPDATE_FILE}")
    
    # 统计
    total_size = sum(f.stat().st_size for f in OUTPUT_DIR.iterdir() if f.suffix == '.mp3')
    print(f"\n=== 完成 ===")
    print(f"音频文件: {len(mapping)} 个")
    print(f"总大小: {total_size / 1024 / 1024:.1f} MB")
    print(f"音频目录: {OUTPUT_DIR}")
    print(f"映射文件: {MAPPING_FILE}")
    print(f"SQL更新: {SQL_UPDATE_FILE}")


if __name__ == "__main__":
    asyncio.run(main())
