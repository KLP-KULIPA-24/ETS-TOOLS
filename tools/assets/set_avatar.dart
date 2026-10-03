// 用作者真实头像（圆形压缩版）替换 assets/TX.png —— dart run tool/set_avatar.dart
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  const srcs = [
    'C:/Users/Admin/Pictures/头像/苦力怕.KULIPA头像【圆形】.png',
    'C:/Users/Admin/Pictures/头像/苦力怕.KULIPA头像【圆形】{压缩版}.jpg',
    'C:/Users/Admin/Pictures/头像/苦力怕.KULIPA头像【方形】.png',
  ];
  img.Image? decoded;
  for (final s in srcs) {
    final f = File(s);
    if (!f.existsSync()) continue;
    decoded = img.decodePng(f.readAsBytesSync()) ??
        img.decodeJpg(f.readAsBytesSync());
    if (decoded != null) break;
  }
  if (decoded == null) {
    stdout.writeln('未找到头像源文件，保留现有 assets/TX.png');
    return;
  }
  // 圆形蒙版 + 512px
  final size = 512;
  final r = img.copyResize(decoded, width: size, height: size,
      interpolation: img.Interpolation.cubic);
  final out = img.Image(width: size, height: size);
  final radius = size / 2;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x - radius + 0.5, dy = y - radius + 0.5;
      if (dx * dx + dy * dy <= radius * radius) {
        out.setPixel(x, y, r.getPixel(x, y));
      }
    }
  }
  File('assets/TX.png').writeAsBytesSync(img.encodePng(out));
  stdout.writeln('assets/TX.png 已更新为作者真实头像（圆形 512px）');
}
