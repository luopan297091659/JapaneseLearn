"""Fix the broken section in listening_screen.dart after the partial replacement"""
path = r'D:\PROJECT\JapaneseLearn\mobile\lib\screens\listening\listening_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# The broken section: from "if (!listenStarted)" to the end of the method
old_broken = """      if (!listenStarted) {
      if (!started) {
        if (mounted) {
          final offlineError = _isOfflineSttError(_debugLastError);
          setState(() {
            _listening = false;
            _feedback = offlineError ? '\u672c\u5730\u8bc6\u522b\u4e0d\u53ef\u7528\uff1a\u8bf7\u5b89\u88c5\u65e5\u8bed\u79bb\u7ebf\u8bed\u97f3\u5305\u540e\u91cd\u8bd5' : '\u8bed\u97f3\u8bc6\u522b\u672a\u542f\u52a8\uff0c\u8bf7\u91cd\u8bd5';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                offlineError
                    ? '\u8bf7\u5728\u7cfb\u7edf\u8bed\u97f3\u670d\u52a1\u4e2d\u4e0b\u8f7d\u201c\u65e5\u8bed(\u65e5\u672c)\u201d\u79bb\u7ebf\u8bed\u97f3\u5305'
                    : '\u8bed\u97f3\u8bc6\u522b\u672a\u542f\u52a8\uff0c\u8bf7\u68c0\u67e5\u7cfb\u7edf\u8bed\u97f3\u670d\u52a1',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // \u5b89\u5168\u8d85\u65f6\uff1a\u65e0\u8bba\u5982\u4f55 18 \u79d2\u540e\u5f3a\u5236\u7ed3\u675f
      _safetyTimeout = Timer(const Duration(seconds: 18), () {
        if (!_attemptFinalized && _listening) {
          debugPrint('Safety timeout triggered');
          _finalizeAttempt();
        }
      });
        } catch (e) {
      debugPrint('Speech listen error: $e');
      if (mounted) {
        setState(() {
          _listening = false;
          _feedback = '\u5f55\u97f3\u542f\u52a8\u5931\u8d25\uff0c\u8bf7\u91cd\u8bd5';
          _debugLastError = '$e';
        });
      }
    }
  }"""

new_fixed = """      if (!listenStarted) {
        if (mounted) {
          setState(() {
            _listening = false;
            _feedback = '\u8bed\u97f3\u8bc6\u522b\u672a\u542f\u52a8\uff0c\u8bf7\u68c0\u67e5\u7cfb\u7edf\u8bed\u97f3\u670d\u52a1';
            _debugListenStarted = 'failed';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('\u8bed\u97f3\u8bc6\u522b\u672a\u542f\u52a8\uff0c\u8bf7\u68c0\u67e5\u9ea6\u514b\u98ce\u6743\u9650\u548c\u7cfb\u7edf\u8bed\u97f3\u670d\u52a1'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // \u5b89\u5168\u8d85\u65f6\uff1a\u65e0\u8bba\u5982\u4f55 18 \u79d2\u540e\u5f3a\u5236\u7ed3\u675f
      _safetyTimeout = Timer(const Duration(seconds: 18), () {
        if (!_attemptFinalized && _listening) {
          debugPrint('Safety timeout triggered');
          _finalizeAttempt();
        }
      });
    } catch (e) {
      debugPrint('Speech listen error: $e');
      if (mounted) {
        setState(() {
          _listening = false;
          _feedback = '\u5f55\u97f3\u542f\u52a8\u5931\u8d25\uff0c\u8bf7\u91cd\u8bd5';
          _debugLastError = '$e';
        });
      }
    }
  }"""

if old_broken in content:
    content = content.replace(old_broken, new_fixed, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Fixed broken section successfully")
else:
    # Debug: show context
    idx = content.find('if (!listenStarted)')
    if idx > 0:
        print("Found listenStarted at", idx)
        print(repr(content[idx:idx+400]))
    else:
        print("listenStarted not found")
        idx2 = content.find('if (!started)')
        if idx2 > 0:
            print("Found started at", idx2)
            print(repr(content[idx2:idx2+200]))
