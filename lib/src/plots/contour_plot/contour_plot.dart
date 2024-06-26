import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:pretty_charts/src/axes/axes.dart';
import 'package:pretty_charts/src/axes/plot_framework.dart';
import 'package:pretty_charts/src/plots/contour_plot/contour_plot_data.dart';
import 'package:pretty_charts/src/shared/chart_viewer.dart';
import 'package:pretty_charts/src/shared/color_maps/continuous_color_map.dart';

class ContourPlot extends StatefulWidget {
  const ContourPlot({
    super.key,
    required this.axes,
    required this.data,
    this.animationDuration = Durations.extralong1,
    this.animationCurve = Curves.easeInOut,
  });

  final CartesianAxes axes;
  final List<ContourPlotData> data;
  final Duration animationDuration;
  final Curve animationCurve;

  @override
  State<ContourPlot> createState() => _ContourPlotState();
}

class _ContourPlotState extends State<ContourPlot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;

  double _scaleFactor = 1.0;
  Offset _offset = Offset.zero;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    )..addListener(() {
        setState(() {});
      });

    _progressAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: widget.animationCurve,
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChartViewer(
      initialScale: 1.0,
      onScale: (double scaleFactor, Offset offset) {
        setState(() {
          _scaleFactor = scaleFactor;
          _offset = offset;
        });
      },
      child: LayoutBuilder(
        builder: (context, constraints) => ClipRect(
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: ContourPlotPainter(
              scaleFactor: _scaleFactor,
              axes: widget.axes,
              animationProgress: _progressAnimation.value,
              offset: _offset,
              data: widget.data,
            ),
            foregroundPainter: PlotFrameworkPainter(
              scaleFactor: _scaleFactor,
              axes: widget.axes,
              offset: _offset,
            ),
          ),
        ),
      ),
    );
  }
}

class ContourPlotPainter extends CustomPainter {
  ContourPlotPainter({
    super.repaint,
    required this.axes,
    required this.animationProgress,
    required this.scaleFactor,
    required this.offset,
    required this.data,
  });

  final CartesianAxes axes;
  final double scaleFactor;
  final Offset offset;
  final List<ContourPlotData> data;

  /// progress value of the animation
  /// 0 is the start || 1 is the end
  /// interval of value : [0, 1]
  final double animationProgress;

  @override
  void paint(Canvas canvas, Size size) {
    const double internalPadding = 50.0;
    const int points = 300;
    final xAxesRange =
        axes.xLimits.translate(-offset.dx / 100).scale(scaleFactor);
    final yAxesRange =
        axes.yLimits.translate(-offset.dy / 100).scale(scaleFactor);

    final width = size.width;

    final paddedWidth = size.width - 2 * internalPadding;
    final paddedHeight = size.height - 2 * internalPadding;

    const paddedTopLeftCorner = Offset(internalPadding, internalPadding);

    // draw a curve
    for (var d in data) {
      final contourPainter = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      final xSpacing = xAxesRange.getDiff() / points;
      final ySpacing = xAxesRange.getDiff() / points;

      final values = Float64List(points * points);
      double minValue = double.infinity;
      double maxValue = double.minPositive;

      var iYSpacing = 0.0;
      var iPoints = 0;
      for (var i = 0; i < points; i++) {
        var jXSpacing = 0.0;
        for (var j = 0; j < points; j++) {
          final x = xAxesRange.minLimit + jXSpacing;
          final y = yAxesRange.minLimit + iYSpacing;

          final value = d.onGenerate(x, y);
          minValue = min(minValue, value);
          maxValue = max(maxValue, value);
          values[j + iPoints] = value;

          jXSpacing += xSpacing;
        }
        iYSpacing += ySpacing;
        iPoints += points;
      }

      for (var i = 0; i < d.nbLines; i++) {
        final isoValue = (maxValue - minValue) / d.nbLines * (i);
        contourPainter.color = blueGreenRedSquential
            .getColor((isoValue + minValue) / (maxValue - minValue));

        final binaryImage = Uint8List(values.length);

        for (var i = 0; i < values.length; i++) {
          final a = values[i];
          if (a > isoValue) {
            binaryImage[i] = 1;
          } else {
            binaryImage[i] = 0;
          }
        }

        const lim = points - 1;
        final contouringGrid = Uint8List(lim * lim);
        final widthCell = paddedWidth / points;
        final heightCell = paddedHeight / points;

        final halfWidthCell = widthCell / 2;
        final halfHeightCell = heightCell / 2;

        for (var i = 0; i < lim * lim; i++) {
          final firstIndex = i + i ~/ lim;
          final topLeftCorner = binaryImage[firstIndex];
          final topRightCorner = binaryImage[firstIndex + 1];
          final bottomRightCorner = binaryImage[firstIndex + points + 1];
          final bottomLeftCorner = binaryImage[firstIndex + points];

          final a = topLeftCorner << 3 |
              topRightCorner << 2 |
              bottomRightCorner << 1 |
              bottomLeftCorner;
          contouringGrid[i] = a;
        }

        // draw the contour
        final path = Path();
        for (var i = 0; i < contouringGrid.length; i++) {
          final v = contouringGrid[i];
          if (v == 0 && v == 15) {
            continue;
          }
          final x = i % lim;
          final y = i ~/ lim;

          final o = paddedTopLeftCorner.translate(
              widthCell * (x + 0.5), (heightCell * (0.5 + y)));

          switch (v) {
            case 0:
            case 15:
              break;
            case 1:
            case 14:
              path.moveTo(o.dx, o.dy + halfHeightCell);
              path.relativeLineTo(halfWidthCell, heightCell);

              break;
            case 2:
            case 13:
              path.moveTo(o.dx + halfWidthCell, o.dy + heightCell);
              path.relativeLineTo(widthCell, halfHeightCell);
              break;
            case 3:
            case 12:
              path.moveTo(o.dx, o.dy + halfHeightCell);
              path.relativeLineTo(widthCell, halfHeightCell);
              break;
            case 4:
            case 11:
              path.moveTo(o.dx + halfWidthCell, o.dy);
              path.relativeLineTo(widthCell, halfHeightCell);
              break;
            case 5:
              path.moveTo(o.dx, o.dy + halfHeightCell);
              path.relativeLineTo(halfWidthCell, 0);

              path.moveTo(o.dx + halfWidthCell, o.dy + heightCell);
              path.relativeLineTo(widthCell, halfHeightCell);
              break;
            case 6:
            case 9:
              path.moveTo(o.dx + halfWidthCell, o.dy);
              path.relativeLineTo(halfWidthCell, heightCell);
              break;
            case 7:
            case 8:
              path.moveTo(o.dx, o.dy + halfHeightCell);
              path.relativeLineTo(halfWidthCell, 0);
              break;
            case 10:
              path.moveTo(o.dx, o.dy + halfHeightCell);
              path.relativeLineTo(halfWidthCell, heightCell);

              path.moveTo(o.dx + halfWidthCell, o.dy);
              path.relativeLineTo(widthCell, halfHeightCell);

              break;
            default:
              break;
          }
        }

        canvas.drawPath(path, contourPainter);
      }

      drawColorMap(canvas, Offset(width - 30, internalPadding), paddedHeight,
          minValue, maxValue, blueGreenRedSquential);
    }
  }

  void drawColorMap(
    Canvas canvas,
    Offset colorMapOrigin,
    double height,
    double minValue,
    double maxValue,
    ContinuousColorMap colorMap,
  ) {
    const rectangleWidth = 30 / 2;
    final painter = Paint()
      ..shader = ui.Gradient.linear(
        Offset(rectangleWidth, height),
        const Offset(rectangleWidth, 0),
        colorMap.colors,
        List.generate(
            colorMap.colors.length, (i) => i * (1 / colorMap.colors.length)),
      );

    canvas.drawRect(
        Rect.fromLTWH(colorMapOrigin.dx, colorMapOrigin.dy, 30, height),
        painter);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

Path extractPathUntilLength(
  Path originalPath,
  double length,
) {
  var currentLength = 0.0;

  final path = Path();

  var metricsIterator = originalPath.computeMetrics().iterator;

  while (metricsIterator.moveNext()) {
    var metric = metricsIterator.current;

    var nextLength = currentLength + metric.length;

    final isLastSegment = nextLength > length;
    if (isLastSegment) {
      final remainingLength = length - currentLength;
      final pathSegment = metric.extractPath(0.0, remainingLength);

      path.addPath(pathSegment, Offset.zero);
      break;
    } else {
      // There might be a more efficient way of extracting an entire path
      final pathSegment = metric.extractPath(0.0, metric.length);
      path.addPath(pathSegment, Offset.zero);
    }

    currentLength = nextLength;
  }

  return path;
}
