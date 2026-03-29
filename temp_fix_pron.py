import sys

path = r'D:\PROJECT\JapaneseLearn\mobile\lib\screens\study\pronunciation_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix the broken catch block - find it by the broken pattern
old = """        } catch (e) {
      debugPrint('Speech listen error: ');
      if (mounted) {
        setState(() {
          _listening = false;
          _feedback = '录音启动失败，请重试';
          _debugLastError = '';
        });
      }
    }
  }"""

new = """    } catch (e) {
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

if old in content:
    content = content.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('Fixed pronunciation_screen.dart catch block')
else:
    print('ERROR: Could not find the broken catch block')
    # Show context around 'Speech listen error'
    idx = content.find('Speech listen error')
    if idx > 0:
        print(repr(content[idx-50:idx+200]))
    sys.exit(1)
