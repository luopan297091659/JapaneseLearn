import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// 助词消除型俄罗斯方块小游戏
/// 每次下落前必须做出助词判断，答错生成垃圾块，答对消除
class TetrisGrammarGame extends StatefulWidget {
  const TetrisGrammarGame({super.key});

  @override
  State<TetrisGrammarGame> createState() => _TetrisGrammarGameState();
}

class _TetrisGrammarGameState extends State<TetrisGrammarGame> {
  // 题库（可扩展为后端/本地json）
  final List<_GrammarQuestion> _questions = [
    _GrammarQuestion(
      sentence: '東京＿＿行きます。',
      correct: 'に',
      options: ['に', 'を', 'で'],
      explanation: '「に」表示目的地，去东京。',
      tag: '助词',
    ),
    _GrammarQuestion(
      sentence: '電車＿＿乗ります。',
      correct: 'に',
      options: ['に', 'を', 'で'],
      explanation: '「に」表示乘坐交通工具。',
      tag: '助词',
    ),
    _GrammarQuestion(
      sentence: '水＿＿飲みます。',
      correct: 'を',
      options: ['を', 'に', 'で'],
      explanation: '「を」表示动作对象。',
      tag: '助词',
    ),
    _GrammarQuestion(
      sentence: '図書館＿＿勉強します。',
      correct: 'で',
      options: ['で', 'に', 'を'],
      explanation: '「で」表示动作发生场所。',
      tag: '助词',
    ),
    // ...可继续扩展
  ];

  static const int maxRows = 12;
  static const int maxCols = 6;
  List<List<_Block?>> _board = List.generate(maxRows, (_) => List.filled(maxCols, null));
  int _score = 0;
  int _combo = 0;
  int _wrongCount = 0;
  int _currentRow = 0;
  int _currentCol = 2;
  int _currentQ = 0;
  int _selected = 0;
  bool _isDropping = false;
  bool _gameOver = false;
  Timer? _timer;
  Duration _dropSpeed = const Duration(milliseconds: 1200);
  final List<_Block> _garbageBlocks = [];
  final List<_WrongLog> _wrongLog = [];

  @override
  void initState() {
    super.initState();
    _startGame();
  }

  void _startGame() {
    _score = 0;
    _combo = 0;
    _wrongCount = 0;
    _currentRow = 0;
    _currentCol = 2;
    _currentQ = 0;
    _selected = 0;
    _isDropping = false;
    _gameOver = false;
    _board = List.generate(maxRows, (_) => List.filled(maxCols, null));
    _wrongLog.clear();
    _nextQuestion();
  }

  void _nextQuestion() {
    setState(() {
      _currentQ = Random().nextInt(_questions.length);
      _selected = 0;
      _currentRow = 0;
      _currentCol = 2;
      _isDropping = true;
    });
    _timer?.cancel();
    _timer = Timer(_dropSpeed, _autoDrop);
  }

  void _autoDrop() {
    if (!_isDropping || _gameOver) return;
    _confirm();
  }

  void _moveLeft() {
    if (_selected > 0) setState(() => _selected--);
  }
  void _moveRight() {
    if (_selected < _questions[_currentQ].options.length - 1) setState(() => _selected++);
  }
  void _showExplanation() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('用法解释'),
        content: Text(_questions[_currentQ].explanation),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    );
  }
  void _confirm() {
    if (!_isDropping || _gameOver) return;
    final q = _questions[_currentQ];
    final ans = q.options[_selected];
    final isCorrect = ans == q.correct;
    setState(() {
      if (isCorrect) {
        _score++;
        _combo++;
        _dropSpeed = Duration(milliseconds: max(400, 1200 - _combo * 80));
        _placeBlock(_currentRow, _currentCol, _Block(ans, Colors.blueAccent));
        _clearFullRows();
      } else {
        _wrongCount++;
        _combo = 0;
        _dropSpeed = Duration(milliseconds: max(400, 1200 - _combo * 80));
        _placeBlock(_currentRow, _currentCol, _Block(ans, Colors.grey));
        _wrongLog.add(_WrongLog(q.sentence, ans, q.correct));
      }
      _isDropping = false;
      if (_isBoardFull()) {
        _gameOver = true;
        _timer?.cancel();
        Future.delayed(const Duration(milliseconds: 600), _showReport);
      } else {
        Future.delayed(const Duration(milliseconds: 400), _nextQuestion);
      }
    });
  }

  void _placeBlock(int row, int col, _Block block) {
    for (int r = maxRows - 1; r >= 0; r--) {
      if (_board[r][col] == null) {
        _board[r][col] = block;
        break;
      }
    }
  }

  void _clearFullRows() {
    for (int r = 0; r < maxRows; r++) {
      if (_board[r].every((b) => b != null && b!.color != Colors.grey)) {
        setState(() {
          _score += 3;
          for (int rr = r; rr > 0; rr--) {
            _board[rr] = List.from(_board[rr - 1]);
          }
          _board[0] = List.filled(maxCols, null);
        });
      }
    }
  }

  bool _isBoardFull() {
    return _board[0].any((b) => b != null);
  }

  void _showReport() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('学习报告'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('答题数：$_score'),
            Text('错误数：$_wrongCount'),
            if (_wrongLog.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('易错点：', style: TextStyle(fontWeight: FontWeight.bold)),
              ..._wrongLog.map((e) => Text('${e.sentence}\n你的答案：${e.wrong}，正确：${e.correct}')),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () {
            Navigator.pop(context);
            _startGame();
          }, child: const Text('再来一局')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _questions[_currentQ];
    return Scaffold(
      appBar: AppBar(title: const Text('助词方块 - 日语小游戏')),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Text(q.sentence, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(q.options.length, (i) => GestureDetector(
              onTap: () => setState(() => _selected = i),
              onLongPress: _showExplanation,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: i == _selected ? Colors.blueAccent : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: i == _selected ? Colors.blue : Colors.grey.shade400, width: 2),
                ),
                child: Text(q.options[i], style: TextStyle(fontSize: 18, color: i == _selected ? Colors.white : Colors.black)),
              ),
            )),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: AspectRatio(
                aspectRatio: maxCols / maxRows,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: maxCols,
                      mainAxisSpacing: 2,
                      crossAxisSpacing: 2,
                    ),
                    itemCount: maxRows * maxCols,
                    itemBuilder: (context, idx) {
                      final r = idx ~/ maxCols;
                      final c = idx % maxCols;
                      final b = _board[r][c];
                      return Container(
                        decoration: BoxDecoration(
                          color: b?.color ?? Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Center(
                          child: Text(b?.text ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_left, size: 32),
                  onPressed: _moveLeft,
                ),
                GestureDetector(
                  onVerticalDragEnd: (_) => _confirm(),
                  onLongPress: _showExplanation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text('下落/确认', style: TextStyle(color: Colors.white, fontSize: 18)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_right, size: 32),
                  onPressed: _moveRight,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('分数：$_score  连击：$_combo', style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _GrammarQuestion {
  final String sentence;
  final String correct;
  final List<String> options;
  final String explanation;
  final String tag;
  const _GrammarQuestion({required this.sentence, required this.correct, required this.options, required this.explanation, required this.tag});
}

class _Block {
  final String text;
  final Color color;
  const _Block(this.text, this.color);
}

class _WrongLog {
  final String sentence;
  final String wrong;
  final String correct;
  _WrongLog(this.sentence, this.wrong, this.correct);
}
