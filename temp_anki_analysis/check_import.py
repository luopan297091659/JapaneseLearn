import subprocess
result = subprocess.run(
    ['plink', '-batch', '-hostkey', 'SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg',
     '-pw', 'Xiaoyun@123', 'root@139.196.44.6',
     'mysql -uroot -p6586156 japanese_learn --default-character-set=utf8mb4 -e "SELECT word, reading, meaning_zh, example_sentence, example_meaning_zh FROM vocabulary WHERE jlpt_level=\'N4\' ORDER BY RAND() LIMIT 5"'],
    capture_output=True, text=True, encoding='utf-8'
)
print(result.stdout)
if result.stderr:
    print("STDERR:", result.stderr)
