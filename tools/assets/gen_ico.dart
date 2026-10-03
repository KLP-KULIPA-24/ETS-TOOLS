// 生成多尺寸透明 ICO（Windows 快捷方式图标）——dart run tool/gen_ico.dart
// 之前 package:image 的 IcoEncoder 生成的 ico 可能是单尺寸/格式不被 Windows 接受，
// 这里手工组装标准 ICO：6 字节头 + 16 字节/项的目录 + PNG 数据
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

void main() {
  final base = img.decodePng(
      File('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png')
          .readAsBytesSync())!;

  const sizes = [16, 24, 32, 48, 64, 128, 256];
  final pngs = <List<int>>[];
  for (final s in sizes) {
    final r = img.copyResize(base, width: s, height: s,
        interpolation: img.Interpolation.cubic);
    pngs.add(img.encodePng(r));
  }

  final out = BytesBuilder();
  final head = ByteData(6);
  head.setUint16(0, 0, Endian.little); // reserved
  head.setUint16(2, 1, Endian.little); // type = icon
  head.setUint16(4, sizes.length, Endian.little);
  out.add(head.buffer.asUint8List());

  var offset = 6 + sizes.length * 16;
  for (var i = 0; i < sizes.length; i++) {
    final e = ByteData(16);
    e.setUint8(0, sizes[i] >= 256 ? 0 : sizes[i]); // width
    e.setUint8(1, sizes[i] >= 256 ? 0 : sizes[i]); // height
    e.setUint8(2, 0); // 调色板数
    e.setUint8(3, 0); // reserved
    e.setUint16(4, 1, Endian.little); // color planes
    e.setUint16(6, 32, Endian.little); // bits per pixel
    e.setUint32(8, pngs[i].length, Endian.little);
    e.setUint32(12, offset, Endian.little);
    out.add(e.buffer.asUint8List());
    offset += pngs[i].length;
  }
  for (final p in pngs) {
    out.add(p);
  }

  final ico = File('windows/runner/resources/runner.exe.ico');
  ico.writeAsBytesSync(out.toBytes());
  stdout.writeln('ICO 已生成：${ico.path}（${sizes.length} 尺寸，${out.length} 字节）');
}
