#!/bin/bash
mysql -u root -p6586156 japanese_learn -e "
SELECT gl.title, gl.pattern, gl.jlpt_level, ge.sentence, ge.meaning_zh 
FROM grammar_lessons gl 
JOIN grammar_examples ge ON ge.grammar_lesson_id = gl.id 
WHERE gl.jlpt_level = 'N5' 
ORDER BY gl.order_index 
LIMIT 20;
"
