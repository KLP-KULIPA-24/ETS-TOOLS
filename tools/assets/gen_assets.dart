// 生成演示作业数据（assets/demo）+ 图标 asset：dart run tool/gen_demo.dart
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  _writeIconAsset();
  _writeDemo();
  stdout.writeln('演示数据与图标 asset 生成完成');
}

void _writeBytes(String rel, List<int> bytes) {
  final f = File('assets/demo/$rel');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(bytes);
}

/// 把应用图标复制为 asset（AppBar/悬浮窗用）
void _writeIconAsset() {
  final logo = _readLogo();
  File('assets/icon.png').writeAsBytesSync(img.encodePng(logo));
}

img.Image _readLogo() {
  // 直接读取已生成的 192px 启动图标作为源
  final f = File('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png');
  return img.decodePng(f.readAsBytesSync())!;
}

/// 内置演示作业（新手教程用）
void _writeDemo() {
  _write('demo/Demo单词跟读/content.json', _wordJson);
  _writeBytes('demo/Demo单词跟读/material/content.wav', _wav());

  _write('demo/Demo三问五答/content.json', _q5aJson);
  _write('demo/Demo三问五答/info.json', _q5aInfo);
}

void _write(String rel, String content) {
  final f = File('assets/demo/$rel');
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(content);
}

const _wordJson = '{"structure_type":"collector.word","info":{'
    '"xh":"1","stid":"demo_word_1","value":"example",'
    '"translate":"n. 例子；示范；榜样","analyze":"","read_title":"",'
    '"audio":"content.wav","image":"","mpg":""}}';

const _q5aInfo = '[{"code_id":"value","code_type":"txt","code_value":"'
    'W: Hello! This is a demo dialogue for E听说助手.</br>'
    'M: Hi! You can explore answers, audio and AI features here.</br>'
    'W: Great. Let me show you how the helper works."},'
    '{"code_id":"pic1","code_type":"image","code_value":""}]';

const _q5aJson = '{"structure_type":"collector.3q5a","info":{'
    '"stid":"demo_q5a_1","image":"","video":"","audio":"",'
    '"value":"W: Hello! This is a demo dialogue for E听说助手.</br>'
    'M: Hi! You can explore answers, audio and AI features here.</br>'
    'W: Great. Let me show you how the helper works.",'
    '"question":['
    '{"xh":"1","role":"a","ask":"你能简单介绍一下这个软件吗？",'
    '"answer":"E听说助手 is a helper app for English listening and speaking practice.",'
    '"std":[{"value":"E听说助手 is a helper app for English listening and speaking practice.","ai":"","audio":""}],'
    '"keywords":"helper app|listening and speaking","askaudio":"","aswaudio":"","analyze":""},'
    '{"xh":"2","role":"b","ask":"What can you explore in this demo?",'
    '"answer":"",'
    '"std":[{"value":"Answers, audio and AI features.","ai":"","audio":""}],'
    '"keywords":"answers audio AI features","askaudio":"","aswaudio":"","analyze":""}'
    ']}}';

/// 生成 1 秒静音 WAV（16kHz 单声道 16bit）
List<int> _wav() {
  const sampleRate = 16000;
  const seconds = 1;
  final dataLen = sampleRate * seconds * 2;
  final out = <int>[];
  void str(String s) => out.addAll(s.codeUnits);
  void u32(int v) => out.addAll([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
  void u16(int v) => out.addAll([v & 255, (v >> 8) & 255]);
  str('RIFF');
  u32(36 + dataLen);
  str('WAVE');
  str('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  str('data');
  u32(dataLen);
  for (var i = 0; i < sampleRate * seconds; i++) {
    out.addAll([0, 0]);
  }
  return out;
}
