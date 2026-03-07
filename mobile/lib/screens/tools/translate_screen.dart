import 'package:flutter/material.dart';

class TranslateScreen extends StatelessWidget {
  const TranslateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('翻译/解析'),
      ),
      body: Center(
        child: Text(
          '翻译、OCR图像识别、TTS朗读功能即将上线',
          style: TextStyle(fontSize: 18, color: Colors.grey[700]),
        ),
      ),
    );
  }
}
