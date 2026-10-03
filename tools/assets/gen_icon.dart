// E听说助手 图标生成器：dart run tool/gen_icon.dart
// 生成 Android mipmap、Windows ico 和作者头像占位 assets/TX.png
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final logo = _drawLogo(1024);
  _writeLogoSizes(logo);
  _writeIco();
  _writeAvatar();
  stdout.writeln('图标生成完成');
}

img.Image _drawLogo(int size) {
  final image = img.Image(width: size, height: size);
  final s = size.toDouble();

  // 圆角矩形蒙版 + 对角渐变（蓝紫 -> 青）
  final c1 = [0x5B, 0x7C, 0xFF]; // #5B7CFF
  final c2 = [0x22, 0xD3, 0xEE]; // #22D3EE
  final radius = s * 0.22;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = _edgeDist(x, size);
      final dy = _edgeDist(y, size);
      var inside = true;
      if (dx < radius && dy < radius) {
        final ddx = radius - dx;
        final ddy = radius - dy;
        inside = ddx * ddx + ddy * ddy <= radius * radius;
      }
      if (!inside) continue;
      final t = ((x + y) / (2 * size)).clamp(0.0, 1.0);
      final r = (c1[0] + (c2[0] - c1[0]) * t).round();
      final g = (c1[1] + (c2[1] - c1[1]) * t).round();
      final b = (c1[2] + (c2[2] - c1[2]) * t).round();
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // 顶部玻璃高光
  for (var y = 0; y < size * 0.45; y++) {
    for (var x = 0; x < size; x++) {
      final px = image.getPixel(x, y);
      if (px.a == 0) continue;
      final k = 1 - y / (size * 0.45);
      image.setPixelRgba(
          x,
          y,
          (px.r + 26 * k).round().clamp(0, 255),
          (px.g + 26 * k).round().clamp(0, 255),
          (px.b + 34 * k).round().clamp(0, 255),
          px.a);
    }
  }

  // 中央白色几何 "E"（三条横 + 一竖）
  final white = img.ColorRgba8(255, 255, 255, 255);
  final ex0 = s * 0.22, ex1 = s * 0.54;
  final ey0 = s * 0.26, ey1 = s * 0.74;
  final bar = s * 0.08;
  void rect(double x0, double y0, double x1, double y1) {
    for (var y = y0.round(); y < y1.round(); y++) {
      for (var x = x0.round(); x < x1.round(); x++) {
        image.setPixel(x, y, white);
      }
    }
  }

  rect(ex0, ey0, ex1, ey0 + bar); // 上横
  rect(ex0, (ey0 + ey1) / 2 - bar / 2, ex0 + (ex1 - ex0) * 0.78, (ey0 + ey1) / 2 + bar / 2); // 中横
  rect(ex0, ey1 - bar, ex1, ey1); // 下横
  rect(ex0, ey0, ex0 + bar, ey1); // 竖

  // 右侧三条声波弧（听力意象，与 E 保持间距）
  _arc(image, s, cx: s * 0.66, cy: s * 0.5, r: s * 0.11, w: bar * 0.4, from: -0.85, to: 0.85);
  _arc(image, s, cx: s * 0.66, cy: s * 0.5, r: s * 0.185, w: bar * 0.4, from: -0.8, to: 0.8);
  _arc(image, s, cx: s * 0.66, cy: s * 0.5, r: s * 0.26, w: bar * 0.4, from: -0.72, to: 0.72);

  return image;
}

/// 像素到最近水平/垂直边的距离（圆角判定用）
double _edgeDist(int v, int size) {
  final d = v < size / 2 ? v.toDouble() : (size - 1 - v).toDouble();
  return d;
}

/// 绘制以竖直方向为对称的弧线（角度 -from..to，0 指向右）
void _arc(img.Image image, double s,
    {required double cx, required double cy, required double r, required double w, required double from, required double to}) {
  final steps = (s * 1.2).round();
  for (var i = 0; i <= steps; i++) {
    final t = from + (to - from) * i / steps;
    final px = cx + r * _cos(t);
    final py = cy + r * _sin(t);
    _dot(image, px, py, w / 2);
  }
}

double _cos(double t) => _cosImpl(t);
double _sin(double t) => _sinImpl(t);

double _cosImpl(double x) {
  const pi = 3.141592653589793;
  x = x % (2 * pi);
  var term = 1.0, sum = 1.0;
  for (var n = 1; n <= 12; n++) {
    term *= -x * x / ((2 * n - 1) * (2 * n));
    sum += term;
  }
  return sum;
}

double _sinImpl(double x) {
  var term = x, sum = x;
  for (var n = 1; n <= 10; n++) {
    term *= -x * x / ((2 * n) * (2 * n + 1));
    sum += term;
  }
  return sum;
}

void _dot(img.Image image, double cx, double cy, double radius) {
  for (var y = (cy - radius).floor(); y <= (cy + radius).ceil(); y++) {
    for (var x = (cx - radius).floor(); x <= (cx + radius).ceil(); x++) {
      if (x < 0 || y < 0 || x >= image.width || y >= image.height) continue;
      final dx = x - cx, dy = y - cy;
      if (dx * dx + dy * dy <= radius * radius) {
        image.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
      }
    }
  }
}

void _writeLogoSizes(img.Image logo) {
  final sizes = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final e in sizes.entries) {
    final dir = Directory(
        'android/app/src/main/res/mipmap-${e.key}');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final resized = img.copyResize(logo, width: e.value, height: e.value,
        interpolation: img.Interpolation.cubic);
    File('${dir.path}/ic_launcher.png').writeAsBytesSync(img.encodePng(resized));
  }
}

void _writeIco() {
  final logo = _drawLogo(256);
  final encoder = img.IcoEncoder();
  final bytes = encoder.encode(logo);
  final f = File('windows/runner/resources/runner.exe.ico');
  if (!f.parent.existsSync()) f.parent.createSync(recursive: true);
  f.writeAsBytesSync(bytes);
}

void _writeAvatar() {
  final size = 256;
  final image = img.Image(width: size, height: size);
  final radius = size / 2;
  final c1 = [0x5B, 0x7C, 0xFF];
  final c2 = [0x22, 0xD3, 0xEE];
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x - radius + 0.5, dy = y - radius + 0.5;
      if (dx * dx + dy * dy <= radius * radius) {
        final t = ((x + y) / (2 * size)).clamp(0.0, 1.0);
        image.setPixelRgba(
            x,
            y,
            (c1[0] + (c2[0] - c1[0]) * t).round(),
            (c1[1] + (c2[1] - c1[1]) * t).round(),
            (c1[2] + (c2[2] - c1[2]) * t).round(),
            255);
      }
    }
  }
  // 头像主体：五条声波柱
  final white = img.ColorRgba8(255, 255, 255, 255);
  final bars = [0.28, 0.46, 0.62, 0.46, 0.28]; // 高度比例
  final barW = size * 0.09;
  final gap = size * 0.055;
  final totalW = bars.length * barW + (bars.length - 1) * gap;
  var x0 = (size - totalW) / 2;
  for (final h in bars) {
    final y0 = size / 2 - size * h / 2;
    for (var y = y0.round(); y < (y0 + size * h).round(); y++) {
      for (var x = x0.round(); x < (x0 + barW).round(); x++) {
        image.setPixel(x, y, white);
      }
    }
    x0 += barW + gap;
  }
  final dir = Directory('assets');
  if (!dir.existsSync()) dir.createSync();
  File('assets/TX.png').writeAsBytesSync(img.encodePng(image));
}
