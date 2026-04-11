import re

def process_file(path, is_pronunciation=True):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 1. Remove _concurrentRecording related variables and methods
    content = re.sub(r'\s*// concurrent recording \(alongside speech recognition\)\s*bool _concurrentRecording = false;\s*', '\n', content)
    content = re.sub(r'\s*bool _concurrentRecording = false;\s*', '\n', content)
    content = re.sub(r'\s*/// 启动与语音识别并行的音频录制.*?\n  Future<void> _stopConcurrentRecording\(\) async {.*?}\s*', '\n\n', content, flags=re.DOTALL)
    
    # 2. Add new variables for press-and-hold
    if '_wantSpeechRecording' not in content:
        content = content.replace("String _lastRecognized = '';", "String _lastRecognized = '';\n  bool _wantSpeechRecording = false;")

    # 3. Replace _toggleRecord with _startSpeechRecording and _stopSpeechRecording
    if '_toggleRecord' in content:
        start_rec = '''
  Future<void> _startSpeechRecording() async {
    if (_listening) return;
    _wantSpeechRecording = true;

    if (_isRecordingPlayback || await _recorder.isRecording()) {
      _wantSpeechRecording = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先停止“录制回放”后再进行语音识别')),
        );
      }
      return;
    }

    final micGranted = await PermissionService.requestMicrophonePermission();
    if (!micGranted) {
      _wantSpeechRecording = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能录音，请在设置中允许')),
        );
      }
      return;
    }

    await _speech.stop();
    await _speech.cancel();
    _speechAvailable = await _speech.initialize(
      onError: (error) => debugPrint('Speech init error: $error'),
      onStatus: (status) => debugPrint('Speech status: $status'),
    );
    if (!_speechAvailable) {
      _wantSpeechRecording = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音识别不可用，请检查系统设置')),
        );
      }
      return;
    }
    _lastRecognized = '';
    _attemptFinalized = false;
    setState(() { _listening = true; _score = null; _recognized = ''; _feedback = ''; _recordingPath = null; });

    try {
      _speech.statusListener = (status) {
        if ((status == 'done' || status == 'notListening') && !_attemptFinalized) {
          _finalizeRecognitionAttempt();
        }
      };

      await _speech.listen(
        localeId: 'ja_JP',
        onResult: (result) {
          _lastRecognized = result.recognizedWords;
          if (result.finalResult) {
            _processResult(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
      );
      
      if (!_wantSpeechRecording && _listening) {
        await _stopSpeechRecording();
      }
    } catch (e) {
      _wantSpeechRecording = false;
      debugPrint('Speech listen error: $e');
      if (mounted) {
        setState(() { _listening = false; _feedback = '录音启动失败，请重试'; });
      }
    }
  }

  Future<void> _stopSpeechRecording() async {
    _wantSpeechRecording = false;
    if (!_listening) return;
    await _speech.stop();
    await _finalizeRecognitionAttempt();
  }
'''
        if not is_pronunciation:
            start_rec = start_rec.replace("if (_isRecordingPlayback || await _recorder.isRecording()) {", "if (await _recorder.isRecording()) {")

        # Replace the whole _toggleRecord block
        content = re.sub(r'\s*Future<void> _toggleRecord\(\) async {.*?}\n\s*Future<void> _finalizeRecognitionAttempt', '\n' + start_rec + '\n  Future<void> _finalizeRecognitionAttempt', content, flags=re.DOTALL)

    # 4. Clean up _stopConcurrentRecording inside _finalizeRecognitionAttempt
    content = re.sub(r'//\s*确保并行录制已停止\s*await _stopConcurrentRecording\(\);', '', content)
    
    # 5. Fix UI button
    button_regex = r'\s*// Record button.*?FilledButton\.icon\(.*?backgroundColor: _listening \? Colors\.red : cs\.primary,\s*\),\s*\),' if is_pronunciation else r'\s*// 录音按钮.*?FilledButton\.icon\(.*?backgroundColor: _listening \? Colors\.red : cs\.primary,\s*\),\s*\),'
    
    ui_btn = '''
        // 主识别录音：按住录音，松开结束
        Listener(
          onPointerDown: (_) => _startSpeechRecording(),
          onPointerUp: (_) => _stopSpeechRecording(),
          onPointerCancel: (_) => _stopSpeechRecording(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              color: _listening ? Colors.red : cs.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  _listening ? '🔴 松开结束并识别' : '🎙️ 按住说话',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
'''
    content = re.sub(button_regex, '\n' + ui_btn, content, flags=re.DOTALL)

    # Listening screen specific cleanup for _stopConcurrentRecording remaining traces
    content = re.sub(r'\s*await _stopConcurrentRecording\(\);\s*', '\n', content)
    content = re.sub(r'_stopConcurrentRecording\(\)\.then\(\(_\) \{\s*_finalizeRecognitionAttempt\(\);\s*\}\);', '_finalizeRecognitionAttempt();', content, flags=re.DOTALL)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

process_file('D:/PROJECT/JapaneseLearn/mobile/lib/screens/study/pronunciation_screen.dart', True)
process_file('D:/PROJECT/JapaneseLearn/mobile/lib/screens/listening/listening_screen.dart', False)
print('Rewrite successful!')
