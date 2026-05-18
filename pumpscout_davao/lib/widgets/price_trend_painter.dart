part of '../main.dart';

class PriceTrendPainter extends CustomPainter {
  const PriceTrendPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, ui.Size size) {
    if (values.length < 2) return;

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = (maxValue - minValue).abs() < 0.01 ? 1 : maxValue - minValue;
    final path = Path();
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = const Color(0xFF00C853)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = const Color(0xFF00C853)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 3; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : size.width * i / (values.length - 1);
      final y = size.height - ((values[i] - minValue) / range * size.height);
      final point = Offset(x, y);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    canvas.drawPath(path, linePaint);

    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : size.width * i / (values.length - 1);
      final y = size.height - ((values[i] - minValue) / range * size.height);
      canvas.drawCircle(Offset(x, y), 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PriceTrendPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}
