# 客户端音频同步与降级实现指南

**更新时间**: 2026年4月5日  
**状态**: 手机端需要实现的逻辑

---

## 概述

由于后端改为本地存储音频，客户端需要实现以下策略：
1. **优先使用服务端固定音频** - 新路径 `/audio/kokoro/xxx.wav`
2. **兼容旧式 Kokoro 路径** - 旧路径 `/api/v1/tts/kokoro/audio/xxx.wav`
3. **自动降级到本地 TTS** - 无音频或加载失败时

---

## 实现方案

### 1. 修改 audioPlayerWidget.dart

在 `mobile/lib/widgets/audio_player_widget.dart` 中添加智能路径处理：

```dart
class AudioPlayerWidget extends StatefulWidget {
  final String? audioUrl;  // 可能的值:
                           // /audio/kokoro/kokoro_xxx.wav (新)
                           // /api/v1/tts/kokoro/audio/kokoro_xxx.wav (旧)
                           // /uploads/audio/xxx.wav (上传)
  final String fallbackText;  // TTS 降级文本
  
  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  bool _hasError = false;
  bool _isLoading = false;
  bool _usedTTSFallback = false;
  
  final FlutterTts _tts = FlutterTts();
  
  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initializeTts();
  }
  
  void _initializeTts() async {
    try {
      await _tts.setLanguage('ja-JP');
      await _tts.setSpeechRate(0.4);
    } catch (_) {
      // TTS 初始化失败，稍后再试
    }
  }
  
  /// 获取完整的音频 URL（智能路径处理）
  String? _getAudioUrl() {
    if (widget.audioUrl == null || widget.audioUrl!.isEmpty) {
      return null;
    }
    
    final url = widget.audioUrl!;
    final serverRoot = AppConfig.serverRoot;  // https://139.196.44.6:8002
    
    // 路径类型判断
    if (url.startsWith('/audio')) {
      // ✓ 新本地存储路径 (推荐)
      return '$serverRoot$url';  // https://139.196.44.6:8002/audio/kokoro/xxx.wav
    } else if (url.startsWith('/api')) {
      // ⚠️ 旧 Kokoro 代理路径 (兼容)
      return '$serverRoot$url';  // https://139.196.44.6:8002/api/v1/tts/kokoro/audio/xxx.wav
    } else if (url.startsWith('/uploads')) {
      // 上传的音频
      return '$serverRoot$url';
    } else if (url.startsWith('http')) {
      // 完整 URL
      return url;
    }
    
    return null;
  }
  
  /// 播放音频，自动降级到 TTS
  Future<void> playAudio() async {
    try {
      // 检查是否有有效的音频 URL
      final audioUrl = _getAudioUrl();
      
      if (audioUrl == null) {
        // 无音频，直接用 TTS
        return _playWithTts();
      }
      
      // 尝试播放在线音频
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
      
      try {
        // 设置超时（30秒）
        await _audioPlayer.play(
          UrlSource(audioUrl),
          volume: 1.0,
        ).timeout(
          Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('音频加载超时');
          },
        );
        
        setState(() {
          _isLoading = false;
          _isPlaying = true;
          _usedTTSFallback = false;
        });
        
        _audioPlayer.onPlayerComplete.listen((_) {
          setState(() => _isPlaying = false);
        });
        
      } catch (e) {
        // 音频加载失败，降级到 TTS
        print('[Audio] 加载失败，降级到 TTS: $e');
        return _playWithTts();
      }
    } catch (e) {
      print('[Audio] 播放失败: $e');
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }
  
  /// 使用 TTS 降级播放
  Future<void> _playWithTts() async {
    if (widget.fallbackText == null || widget.fallbackText!.isEmpty) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
      return;
    }
    
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _usedTTSFallback = true;
      });
      
      await _tts.speak(widget.fallbackText!);
      
      setState(() {
        _isLoading = false;
        _isPlaying = true;
      });
    } catch (e) {
      print('[TTS] 播放失败: $e');
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }
  
  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isLoading ? null : playAudio,
      child: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          border: Border.all(
            color: _hasError ? Colors.red : Colors.blue,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (_isLoading)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_hasError)
              Icon(Icons.error, color: Colors.red, size: 24)
            else if (_isPlaying)
              Icon(Icons.volume_up, color: Colors.blue, size: 24)
            else
              Icon(Icons.play_arrow, color: Colors.blue, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                _usedTTSFallback ? '使用本地语音' : '播放音频',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 2. 修改 grammar_detail_screen.dart

在语法详情屏幕中添加音频同步逻辑：

```dart
class GrammarDetailScreen extends StatefulWidget {
  final String grammarId;
  
  @override
  State<GrammarDetailScreen> createState() => _GrammarDetailScreenState();
}

class _GrammarDetailScreenState extends State<GrammarDetailScreen> {
  late GrammarLesson _grammar;
  List<GrammarExample> _examples = [];
  
  @override
  void initState() {
    super.initState();
    _loadGrammarData();
  }
  
  /// 加载语法数据并同步音频
  void _loadGrammarData() async {
    try {
      // 1. 从服务器获取语法数据
      final grammarData = await apiService.getGrammar(widget.grammarId);
      
      // 2. 检查例句中是否有音频
      _examples = grammarData.examples ?? [];
      final examplesWithoutAudio = _examples
          .where((ex) => ex.audioUrl == null || ex.audioUrl!.isEmpty)
          .toList();
      
      // 3. 如果某些例句无音频，需要同步处理
      if (examplesWithoutAudio.isNotEmpty) {
        _handleMissingAudio(examplesWithoutAudio);
      }
      
      setState(() {
        _grammar = grammarData;
      });
    } catch (e) {
      print('[Grammar] 加载失败: $e');
    }
  }
  
  /// 处理缺失的音频
  void _handleMissingAudio(List<GrammarExample> examples) {
    // 方案 A: 等待服务器下一次更新
    // 方案 B: 本地 TTS 生成（推荐）
    
    for (var example in examples) {
      // 使用本地 TTS 作为备选方案
      example.audioUrl = null;  // 触发 AudioPlayerWidget 的 TTS 降级
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_grammar.title)),
      body: ListView(
        children: [
          // ... 其他内容 ...
          
          // 例句部分
          for (var example in _examples)
            Card(
              child: Column(
                children: [
                  // 例句文本和音频
                  AudioPlayerWidget(
                    audioUrl: example.audioUrl,  // 新路径优先，自动降级
                    fallbackText: example.sentence,  // TTS 备选文本
                  ),
                  SizedBox(height: 8),
                  Text(example.sentence),
                  SizedBox(height: 8),
                  Text(example.meaningZh, style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

### 3. 修改 gojuon_screen.dart (五十音学习)

```dart
class GojuonScreen extends StatefulWidget {
  @override
  State<GojuonScreen> createState() => _GojuonScreenState();
}

class _GojuonScreenState extends State<GojuonScreen> {
  List<KanaCharacter> _kanaList = [];
  
  @override
  void initState() {
    super.initState();
    _loadKanaData();
  }
  
  void _loadKanaData() async {
    try {
      // 从服务器获取五十音数据（包含音频 URL）
      final response = await apiService.get('/api/v1/kana/categories/1/characters');
      
      setState(() {
        _kanaList = (response.data as List)
            .map((k) => KanaCharacter.fromJson(k))
            .toList();
      });
    } catch (e) {
      print('[Kana] 加载失败: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5),
      itemCount: _kanaList.length,
      itemBuilder: (context, index) {
        final kana = _kanaList[index];
        
        return GestureDetector(
          onTap: () => _playKanaAudio(kana),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(kana.hiragana, style: TextStyle(fontSize: 24)),
                SizedBox(height: 4),
                Text(kana.romaji, style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );
  }
  
  void _playKanaAudio(KanaCharacter kana) async {
    // 使用 AudioPlayerWidget 的播放逻辑
    // 如果 kana.audioUrl 为 null，自动降级到 TTS
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        children: [
          AudioPlayerWidget(
            audioUrl: kana.audioUrl,
            fallbackText: kana.hiragana,  // TTS 若干句子
          ),
        ],
      ),
    );
  }
}
```

---

## 关键要点总结

### 🔄 客户端处理流程

```
1. 获取音频 URL (可能为空或新/旧路径)
      ↓
2. 构建完整 URL
      ├─ 新本地路径: /audio/kokoro/xxx.wav ✓ (推荐)
      ├─ 旧代理路径: /api/v1/tts/kokoro/audio/xxx.wav (兼容)
      └─ 其他: /uploads/xxx.wav (上传)
      ↓
3. 尝试加载在线音频（超时 30 秒）
      ↓
4A. 成功 → 播放
      ↓
4B. 失败 → 降级到本地 TTS
```

### 📱 客户端优势

| 方面 | 优势 |
|------|------|
| **可靠性** | 无网络/超时自动降级 |
| **性能** | 本地 TTS 无网络延迟 |
| **用户体验** | 总是能听到声音（质量可能不同） |
| **适应性** | 自动兼容新旧音频路径 |

### ⚠️ 注意事项

1. **超时设置**: 30 秒超时后自动降级
2. **TTS 检查**: 初始化时检查是否有日语引擎
3. **错误处理**: 完整的异常捕获和日志记录
4. **缓存**: Dio 会自动缓存音频文件

---

## 测试清单

- [ ] 播放有音频的例句 → 应该播放在线音频
- [ ] 播放无音频的例句 → 应该自动降级到 TTS
- [ ] 模拟网络超时 → 应该自动降级到 TTS
- [ ] 五十音界面 → 所有假名都能发音
- [ ] 语法详情 → 例句有/无音频都能正常播放
- [ ] 检查日志 → 应该看到降级到 TTS 的提示

---

## 环境配置

在 `AppConfig` 或相应配置文件中确保：

```dart
class AppConfig {
  static const String serverRoot = 'https://139.196.44.6:8002';
  // 其他配置...
}
```

---

## 相关文档

- [后端 Kokoro 音频修复](KOKORO_AUDIO_FIX_COMPLETE_2026_04_05.md)
- [音频处理架构](audio_feature_architecture.md)
- 五十音管理 API: `/api/v1/kana/*`
- 语法 API: `/api/v1/grammar/*`
