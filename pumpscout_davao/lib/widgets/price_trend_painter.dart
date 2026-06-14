part of '../main.dart';

class PriceTrendPainter extends CustomPainter {
  const PriceTrendPainter(this.values, {this.predictedValue});

  final List<double> values;
  final double? predictedValue;

  @override
  void paint(Canvas canvas, ui.Size size) {
    if (values.length < 2) return;

    final allValues = [...values, ?predictedValue];
    final minValue = allValues.reduce(math.min);
    final maxValue = allValues.reduce(math.max);
    final range = (maxValue - minValue).abs() < 0.01 ? 1 : maxValue - minValue;
    final path = Path();
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;
    final forecastPaint = Paint()
      ..color = const Color(0xFFFFA000)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final forecastDotPaint = Paint()
      ..color = const Color(0xFFFFA000)
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

    final forecast = predictedValue;
    if (forecast != null) {
      final lastY =
          size.height - ((values.last - minValue) / range * size.height);
      final forecastY =
          size.height - ((forecast - minValue) / range * size.height);
      final start = Offset(size.width * 0.86, lastY);
      final end = Offset(size.width, forecastY);
      _drawDashedLine(canvas, start, end, forecastPaint);
      canvas.drawCircle(end, 5, forecastDotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PriceTrendPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.predictedValue != predictedValue;
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 7.0;
    const dashSpace = 5.0;
    final delta = end - start;
    final distance = delta.distance;
    if (distance == 0) return;
    final direction = delta / distance;
    var drawn = 0.0;

    while (drawn < distance) {
      final segmentStart = start + direction * drawn;
      final segmentEnd =
          start + direction * math.min(drawn + dashWidth, distance);
      canvas.drawLine(segmentStart, segmentEnd, paint);
      drawn += dashWidth + dashSpace;
    }
  }
}
