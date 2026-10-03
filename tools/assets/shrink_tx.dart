// 压缩作者头像到 assets/TX.png（512px）
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final src = File('TX.png');
  if (!src.existsSync()) {
    stdout.writeln('根目录无 TX.png，跳过');
    return;
  }
  final decoded = img.decodePng(src.readAsBytesSync());
  final resized = img.copyResize(decoded!, width: 512, height: 512,
      interpolation: img.Interpolation.cubic);
  File('assets/TX.png').writeAsBytesSync(img.encodePng(resized));
  stdout.writeln('TX.png 已压缩至 assets（512px）');
}
