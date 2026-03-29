"""Fix listening_screen.dart:
1. Add _preferOnDevice variable
2. Replace listen() with onDevice fallback loop
3. Fix _processResult for no-reading scoring
"""
import sys

path = r'D:\PROJECT\JapaneseLearn\mobile\lib\screens\listening\listening_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

changes = 0

# 1. Add _preferOnDevice after _toggling
old1 = "  bool _toggling = false;\n  DateTime? _listenStartTime;"
new1 = "  bool _toggling = false;\n  bool _preferOnDevice = true; // 优先本地识别，失败后回退到在线\n  DateTime? _listenStartTime;"
if old1 in content:
    content = content.replace(old1, new1, 1)
    changes += 1
    print("1. Added _preferOnDevice")
else:
    print("1. SKIP - _preferOnDevice might already exist")

# 2. Replace the listen() block with fallback loop
old2_start = "      final dynamic listenResult = await _speech.listen(\n        localeId: _speechLocaleId ?? 'ja-JP',\n        onDevice: true,"
old2_end = "      if (!started) {"

if old2_start in content:
    start_idx = content.find(old2_start)
    end_idx = content.find(old2_end, start_idx)
    if end_idx > start_idx:
        old_block = content[start_idx:end_idx]
        new_block = """      // onResult 回调（onDevice 回退共用）
      void onSttResult(stt.SpeechRecognitionResult result) {
          _lastRecognized = result.recognizedWords;
          if (mounted) {
            setState(() {
              _debugPartial = result.recognizedWords.isEmpty ? '(empty)' : result.recognizedWords;
            });
          }
          if (result.finalResult && !_attemptFinalized) {
            _finalizeAttempt();
            return;
          }
          _resultDebounce?.cancel();
          if (_lastRecognized.trim().isNotEmpty) {
            _resultDebounce = Timer(const Duration(seconds: 2), () {
              if (!_attemptFinalized && _listening) {
                _finalizeAttempt();
              }
            });
          }
      }

      // 优先本地识别，失败后自动回退到在线模式（兼容不支持 onDevice 的设备）
      bool listenStarted = false;
      final modesToTry = _preferOnDevice ? [true, false] : [false];
      for (final tryOnDevice in modesToTry) {
        try {
          final dynamic listenResult = await _speech.listen(
            localeId: _speechLocaleId ?? 'ja-JP',
            onDevice: tryOnDevice,
            onResult: onSttResult,
            listenFor: const Duration(seconds: 15),
            pauseFor: const Duration(seconds: 3),
          );
          final started = listenResult is bool ? listenResult : true;
          debugPrint('listen(onDevice: $tryOnDevice) => $listenResult');
          if (started) {
            if (!tryOnDevice && _preferOnDevice) {
              _preferOnDevice = false;
              debugPrint('Falling back to online STT for this device');
            }
            listenStarted = true;
            if (mounted) setState(() => _debugListenStarted = 'ok(onDevice=$tryOnDevice)');
            break;
          }
          try { await _speech.stop(); } catch (_) {}
        } catch (e) {
          debugPrint('listen(onDevice: $tryOnDevice) error: $e');
          if (mounted) setState(() => _debugLastError = '$e');
          try { await _speech.stop(); } catch (_) {}
          continue;
        }
      }

      if (!listenStarted) {
"""
        content = content.replace(old_block, new_block, 1)
        changes += 1
        print("2. Replaced listen() with fallback loop")
    else:
        print("2. ERROR - could not find end marker")
        sys.exit(1)
else:
    print("2. SKIP - listen block already changed")

# 3. Replace the old "if (!started)" error handling block
old3 = """      if (!listenStarted) {
        if (mounted) {
          final offlineError = _isOfflineSttError(_debugLastError);
          setState(() {
            _listening = false;
            _feedback = offlineError ? '本地识别不可用：请安装日语离线语音包后重试' : '语音识别未启动，请重试';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                offlineError
                    ? '请在系统语音服务中下载"日语(日本)"离线语音包'
                    : '语音识别未启动，请检查系统语音服务',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }"""
new3 = """      if (!listenStarted) {
        if (mounted) {
          setState(() {
            _listening = false;
            _feedback = '语音识别未启动，请检查系统语音服务';
            _debugListenStarted = 'failed';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('语音识别未启动，请检查麦克风权限和系统语音服务'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }"""
if old3 in content:
    content = content.replace(old3, new3, 1)
    changes += 1
    print("3. Fixed error handling block")
else:
    print("3. SKIP - error block already changed or not found")

# 4. Replace the catch block
old4_marker = "Speech listen error"
idx = content.find(old4_marker)
if idx > 0:
    catch_start = content.rfind('} catch (e) {', 0, idx)
    # find from catch_start to the closing of the try-catch
    block_end = content.find('    }\n  }\n\n  Future<void> _processResult', catch_start)
    if block_end > 0:
        old_catch = content[catch_start:block_end + len('    }\n  }')]
        # Check if it still has offlineError logic
        if 'offlineError' in old_catch or 'errText' in old_catch:
            new_catch = """    } catch (e) {
      debugPrint('Speech listen error: $e');
      if (mounted) {
        setState(() {
          _listening = false;
          _feedback = '录音启动失败，请重试';
          _debugLastError = '$e';
        });
      }
    }
  }"""
            content = content.replace(old_catch, new_catch, 1)
            changes += 1
            print("4. Simplified catch block")
        else:
            print("4. SKIP - catch block already simplified")
    else:
        print("4. SKIP - could not find block end")
else:
    print("4. SKIP - catch block not found")

# 5. Fix _processResult for no-reading scoring (listening screen uses sentence + reading)
old5 = """  Future<void> _processResult(String recognized) async {
    final s = _sentences[_index];
    final sentence = (s['sentence'] as String).trim();
    final reading = (s['reading'] as String).trim();
    final rec = recognized.trim();

    final scores = [
      _calcScore(sentence, rec),
      if (reading.isNotEmpty) _calcScore(reading, rec),
    ];
    final score = scores.reduce(max);
    _scores.add(score);

    String feedback;
    if (score >= 90) {
      feedback = '🎉 完美！';
    } else if (score >= 70) {
      feedback = '👍 不错！识别:「$recognized」';
    } else if (score >= 40) {
      feedback = '💪 继续努力！识别:「$recognized」';
    } else {
      feedback = '🔄 再试一次！识别:「$recognized」';
    }

    setState(() { _score = score; _recognized = recognized; _feedback = feedback; _listening = false; _showSentence = true; _aiScoring = true; });

    try {
      final ai = await apiService.scoreSpeechRecognition(
        targetText: sentence,
        recognizedText: rec,
        referenceReading: reading.isNotEmpty ? reading : null,
        mode: 'listening',
      );
      if (mounted) {
        final aiScore = (ai['score'] as num?)?.toInt();
        final aiFeedback = (ai['feedback'] as String?)?.trim();
        if (aiScore != null) {
          setState(() {
            _score = aiScore.clamp(0, 100);
            _aiScoring = false;
            if (aiFeedback != null && aiFeedback.isNotEmpty) {
              _feedback = '🤖 $aiFeedback';
            }
          });
        } else {
          if (mounted) setState(() => _aiScoring = false);
        }
      }
    } catch (e) {
      debugPrint('AI scoring failed: $e');
      if (mounted) setState(() => _aiScoring = false);
    }

    final finalScore = _score ?? score;"""

new5 = """  Future<void> _processResult(String recognized) async {
    final s = _sentences[_index];
    final sentence = (s['sentence'] as String).trim();
    final reading = (s['reading'] as String).trim();
    final rec = recognized.trim();

    // 有 reading 时做本地快速评分；没有时只显示识别结果等 AI
    final hasReading = reading.isNotEmpty;
    int? localScore;
    if (hasReading) {
      final scores = [
        _calcScore(sentence, rec),
        _calcScore(reading, rec),
      ];
      localScore = scores.reduce(max);
    } else {
      // 没有 reading，仅用 sentence 比较（可能不准，以 AI 为准）
      localScore = _calcScore(sentence, rec);
    }

    String feedback;
    if (localScore >= 90) {
      feedback = '🎉 完美！';
    } else if (localScore >= 70) {
      feedback = '👍 不错！识别:「$recognized」';
    } else if (localScore >= 40) {
      feedback = '💪 继续努力！识别:「$recognized」';
    } else {
      feedback = '🔄 再试一次！识别:「$recognized」';
    }

    setState(() { _score = localScore; _recognized = recognized; _feedback = feedback; _listening = false; _showSentence = true; _aiScoring = true; });

    try {
      final ai = await apiService.scoreSpeechRecognition(
        targetText: sentence,
        recognizedText: rec,
        referenceReading: hasReading ? reading : null,
        mode: 'listening',
      );
      if (mounted) {
        final aiScore = (ai['score'] as num?)?.toInt();
        final aiFeedback = (ai['feedback'] as String?)?.trim();
        if (aiScore != null) {
          final finalAiScore = aiScore.clamp(0, 100);
          _scores.add(finalAiScore);
          setState(() {
            _score = finalAiScore;
            _aiScoring = false;
            if (aiFeedback != null && aiFeedback.isNotEmpty) {
              _feedback = '🤖 $aiFeedback';
            }
          });
        } else {
          _scores.add(localScore);
          if (mounted) setState(() => _aiScoring = false);
        }
      }
    } catch (e) {
      debugPrint('AI scoring failed: $e');
      _scores.add(localScore);
      if (mounted) setState(() => _aiScoring = false);
    }

    final finalScore = _score ?? localScore;"""

if old5 in content:
    content = content.replace(old5, new5, 1)
    changes += 1
    print("5. Fixed _processResult scoring")
else:
    print("5. SKIP - _processResult already changed or mismatch")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f"\nDone: {changes} changes applied")
