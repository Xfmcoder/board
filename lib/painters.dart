import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

/// Dotted canvas background, like n8n's workflow grid.
class GridPainter extends CustomPainter {
  const GridPainter({this.gap = 30, this.color = const Color(0xFF222634)});

  final double gap;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    final List<Offset> points = <Offset>[];
    for (double x = gap; x < size.width; x += gap) {
      for (double y = gap; y < size.height; y += gap) {
        points.add(Offset(x, y));
      }
    }
    canvas.drawPoints(ui.PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) =>
      oldDelegate.gap != gap || oldDelegate.color != color;
}

/// Bezier connectors with arrow heads and a travelling dot on the live step.
class EdgePainter extends CustomPainter {
  EdgePainter({
    required this.nodes,
    required this.edges,
    required this.highlight,
    required this.phase,
  });

  final Map<String, PlanNode> nodes;
  final List<PlanEdge> edges;
  final Set<String> highlight;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    for (final PlanEdge e in edges) {
      final PlanNode? a = nodes[e.from];
      final PlanNode? b = nodes[e.to];
      if (a == null || b == null) continue;

      // Direction-aware connectors: vertical when the nodes are stacked,
      // horizontal when they sit side by side (matches the plan layout).
      final bool vertical = (b.y - a.y).abs() >= (b.x - a.x).abs();
      final Offset p1;
      final Offset p2;
      final Path path;
      final Offset u;
      if (vertical) {
        final bool down = b.y >= a.y;
        p1 = Offset(a.x + PlanNode.w / 2, down ? a.y + PlanNode.h : a.y);
        p2 = Offset(b.x + PlanNode.w / 2, down ? b.y : b.y + PlanNode.h);
        final double bend =
            math.max(56.0, (p2.dy - p1.dy).abs() * 0.42) * (down ? 1 : -1);
        path = Path()
          ..moveTo(p1.dx, p1.dy)
          ..cubicTo(p1.dx, p1.dy + bend, p2.dx, p2.dy - bend, p2.dx,
              p2.dy - (down ? 1 : -1));
        u = Offset(0, down ? 1 : -1);
      } else {
        final bool rightward = b.x >= a.x;
        p1 = Offset(rightward ? a.x + PlanNode.w : a.x, a.y + PlanNode.h / 2);
        p2 = Offset(rightward ? b.x : b.x + PlanNode.w, b.y + PlanNode.h / 2);
        final double bend =
            math.max(70.0, (p2.dx - p1.dx).abs() * 0.45) * (rightward ? 1 : -1);
        path = Path()
          ..moveTo(p1.dx, p1.dy)
          ..cubicTo(p1.dx + bend, p1.dy, p2.dx - bend, p2.dy,
              p2.dx - (rightward ? 1 : -1), p2.dy);
        u = Offset(rightward ? 1 : -1, 0);
      }

      final bool live = highlight.contains(a.id) && highlight.contains(b.id);
      if (live) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..color = C.accent.withValues(alpha: 0.16)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = live ? 2.6 : 2.0
          ..strokeCap = StrokeCap.round
          ..color = live ? C.accent : const Color(0xFF3C4252),
      );

      // Arrow head
      final Offset tip = p2;
      final Offset headL =
          Offset(tip.dx - u.dx * 11 - u.dy * 6, tip.dy - u.dy * 11 + u.dx * 6);
      final Offset headR =
          Offset(tip.dx - u.dx * 11 + u.dy * 6, tip.dy - u.dy * 11 - u.dx * 6);
      final Path head = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(headL.dx, headL.dy)
        ..lineTo(headR.dx, headR.dy)
        ..close();
      canvas.drawPath(
        head,
        Paint()..color = live ? C.accent : const Color(0xFF4A5164),
      );
      if (live) {
        final ui.PathMetric metric = path.computeMetrics().first;
        final double d = (phase % 1) * metric.length;
        final ui.Tangent? tangent = metric.getTangentForOffset(d);
        if (tangent != null) {
          canvas.drawCircle(
            tangent.position,
            6,
            Paint()..color = C.accent.withValues(alpha: 0.25),
          );
          canvas.drawCircle(tangent.position, 3.2, Paint()..color = C.accent);
        }
      }
    }
  }

  @override
  bool shouldRepaint(EdgePainter oldDelegate) => true;
}

/// Dashed halo around the node the step-runner is currently on.
class ActiveHaloPainter extends CustomPainter {
  const ActiveHaloPainter({required this.node});

  final PlanNode node;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Rect.fromLTWH(node.x - 8, node.y - 8, PlanNode.w + 16, PlanNode.h + 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(22)),
      Paint()..color = C.accent.withValues(alpha: 0.10),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(22)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = C.accent.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(ActiveHaloPainter oldDelegate) => false;
}
