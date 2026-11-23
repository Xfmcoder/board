import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';
import 'node_card.dart';
import 'theme.dart';

/// Renders a plan straight from the model (not a screenshot), so the JPG and
/// PDF come out vector-crisp, correctly framed, and at any plan size.
class ExportService {
  /// Render scale: everything is laid out in logical units, then rasterised at
  /// this factor so text stays sharp when the page is zoomed or printed.
  static const double _scale = 1.9;
  static const double _pad = 54;
  static const double _headerH = 154;
  static const double _footerH = 60;
  static const double _gapAfterHeader = 10;

  static Future<Uint8List> build({
    required BoardPlan plan,
    required bool asPdf,
  }) async {
    final Rect b = contentBounds(plan, pad: 34);
    final double cw = math.max(b.width, 470);
    final double ch = math.max(b.height, 300);
    final double outW = cw + _pad * 2;
    final double outH = _headerH + _gapAfterHeader + ch + _footerH + _pad;

    final double ox = _pad + (cw - b.width) / 2 - b.left;
    final double oy = _headerH + _gapAfterHeader + (ch - b.height) / 2 - b.top;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas =
        Canvas(recorder, Rect.fromLTWH(0, 0, outW * _scale, outH * _scale));
    canvas.scale(_scale);

    canvas.drawRect(Rect.fromLTWH(0, 0, outW, outH), Paint()..color = C.bg);

    _text(
      canvas,
      'প্রজেক্ট প্লেন  •  বোর্ড',
      hand(17, color: C.accent, weight: 600),
      const Offset(_pad, 24),
      maxWidth: outW - _pad * 2 - 120,
    );
    _text(
      canvas,
      plan.name,
      hand(44, color: C.text, height: 1.08),
      const Offset(_pad, 46),
      maxWidth: outW - _pad * 2 - 30,
      maxLines: 2,
    );
    _text(
      canvas,
      '${banglaNumber(plan.nodes.length)} ধাপ  •  ${banglaNumber(plan.doneCount)} সম্পন্ন  •  ${_dateLabel(plan.updatedAt)}',
      hand(22, color: C.muted, weight: 500),
      const Offset(_pad, 108),
      maxWidth: outW - _pad * 2,
    );

    final Rect panel = Rect.fromLTWH(
      _pad - 18,
      _headerH + _gapAfterHeader - 18,
      outW - (_pad - 18) * 2,
      outH - _headerH - _gapAfterHeader - _footerH - _pad + 26,
    );
    final RRect panelRR =
        RRect.fromRectAndRadius(panel, const Radius.circular(22));
    canvas.drawRRect(panelRR, Paint()..color = C.bg);
    _dots(canvas, panel);
    canvas.drawRRect(
      panelRR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = C.border,
    );

    canvas.save();
    canvas.clipRRect(panelRR);
    final Map<String, PlanNode> byId = <String, PlanNode>{
      for (final PlanNode n in plan.nodes) n.id: n,
    };
    for (final PlanEdge e in plan.edges) {
      final PlanNode? a = byId[e.from];
      final PlanNode? c = byId[e.to];
      if (a == null || c == null) continue;
      _edge(canvas, a, c, ox, oy, highlight: a.done || c.done);
    }
    for (int i = 0; i < plan.nodes.length; i++) {
      _node(canvas, plan.nodes[i], i + 1, ox, oy);
    }
    canvas.restore();

    final double footY = outH - _footerH + 14;
    _text(
      canvas,
      'বোর্ড  •  প্রজেক্ট প্লেনার',
      hand(19, color: C.muted, weight: 500),
      Offset(_pad, footY),
      maxWidth: outW - _pad * 2,
    );

    final ui.Picture picture = recorder.endRecording();
    final ui.Image composed =
        await picture.toImage((outW * _scale).round(), (outH * _scale).round());
    final ByteData? png =
        await composed.toByteData(format: ui.ImageByteFormat.png);
    composed.dispose();
    if (png == null) throw StateError('render failed');
    final Uint8List pngBytes = png.buffer.asUint8List();

    final img.Image? decoded = img.decodePng(pngBytes);
    if (decoded == null) throw StateError('encode failed');

    if (asPdf) {
      // A4 portrait, sliced so a tall plan prints on several readable pages
      // instead of one page shrunk to illegibility.
      final PdfPageFormat page = PdfPageFormat.a4;
      final double fitW = page.width - 24;
      final double fitH = page.height - 24;
      final img.Image scaled = img.copyResize(
        decoded,
        width: fitW.round(),
        maintainAspect: true,
        interpolation: img.Interpolation.linear,
      );
      final double pxPerUnit = fitW / outW;
      // Preferred cut rows: the empty gaps between cards, so a page never
      // slices through a step.
      final List<double> gaps = <double>[];
      for (int i = 0; i < plan.nodes.length - 1; i++) {
        final double bottom =
            (plan.nodes[i].y + oy + PlanNode.h) * pxPerUnit;
        final double top = (plan.nodes[i + 1].y + oy) * pxPerUnit;
        if (top > bottom) gaps.add((bottom + top) / 2);
      }
      gaps.sort();

      final int sliceH = fitH.round();
      final pw.Document doc = pw.Document();
      int y = 0;
      while (y < scaled.height) {
        int h = math.min(sliceH, scaled.height - y);
        if (y + h >= scaled.height) {
          // last page: keep the remainder
        } else {
          final double limit = (y + sliceH).toDouble();
          final Iterable<double> fitting = gaps.where(
            (double g) => g > y + sliceH * 0.45 && g <= limit,
          );
          if (fitting.isNotEmpty) {
            h = fitting.last.round() - y;
          }
        }
        if (h < 40) break;
        final img.Image slice = img.copyCrop(
          scaled,
          x: 0,
          y: y,
          width: scaled.width,
          height: h,
        );
        final Uint8List sliceBytes =
            Uint8List.fromList(img.encodePng(slice));
        doc.addPage(
          pw.Page(
            pageFormat: page,
            margin: const pw.EdgeInsets.all(12),
            build: (pw.Context ctx) => pw.Align(
              alignment: pw.Alignment.topCenter,
              child: pw.Image(pw.MemoryImage(sliceBytes)),
            ),
          ),
        );
        y += sliceH;
      }
      return doc.save();
    }
    final img.Image flat = img.Image(
      width: decoded.width,
      height: decoded.height,
      numChannels: 3,
    );
    img.fill(flat, color: img.ColorRgb8(14, 15, 19));
    img.compositeImage(flat, decoded);
    return Uint8List.fromList(img.encodeJpg(flat, quality: 92));
  }

  static void _dots(Canvas canvas, Rect area) {
    final Paint p = Paint()..color = const Color(0xFF1C202A);
    for (double y = area.top + 26; y < area.bottom - 10; y += 30) {
      for (double x = area.left + 26; x < area.right - 10; x += 30) {
        canvas.drawCircle(Offset(x, y), 1.5, p);
      }
    }
  }

  static void _edge(
    Canvas canvas,
    PlanNode a,
    PlanNode b,
    double ox,
    double oy, {
    bool highlight = false,
  }) {
    final Rect ra = Rect.fromLTWH(a.x + ox, a.y + oy, PlanNode.w, PlanNode.h);
    final Rect rb = Rect.fromLTWH(b.x + ox, b.y + oy, PlanNode.w, PlanNode.h);
    final Color col =
        highlight ? C.accent.withValues(alpha: 0.5) : const Color(0xFF3C4252);

    final bool vertical = (rb.center.dy - ra.center.dy).abs() >=
        (rb.center.dx - ra.center.dx).abs();
    final Offset p1;
    final Offset p2;
    final Path path;
    final Offset u;
    if (vertical) {
      final bool down = rb.center.dy >= ra.center.dy;
      p1 = Offset(ra.center.dx, down ? ra.bottom : ra.top);
      p2 = Offset(rb.center.dx, down ? rb.top : rb.bottom);
      final double bend =
          math.max(46.0, (p2.dy - p1.dy).abs() * 0.42) * (down ? 1 : -1);
      path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(p1.dx, p1.dy + bend, p2.dx, p2.dy - bend, p2.dx, p2.dy);
      u = Offset(0, down ? 1 : -1);
    } else {
      final bool rightward = rb.center.dx >= ra.center.dx;
      p1 = Offset(rightward ? ra.right : ra.left, ra.center.dy);
      p2 = Offset(rightward ? rb.left : rb.right, rb.center.dy);
      final double bend =
          math.max(56.0, (p2.dx - p1.dx).abs() * 0.45) * (rightward ? 1 : -1);
      path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(p1.dx + bend, p1.dy, p2.dx - bend, p2.dy, p2.dx, p2.dy);
      u = Offset(rightward ? 1 : -1, 0);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..color = col,
    );

    final Offset tip = p2;
    final Offset hl =
        Offset(tip.dx - u.dx * 10 - u.dy * 5.5, tip.dy - u.dy * 10 + u.dx * 5.5);
    final Offset hr =
        Offset(tip.dx - u.dx * 10 + u.dy * 5.5, tip.dy - u.dy * 10 - u.dx * 5.5);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(hl.dx, hl.dy)
        ..lineTo(hr.dx, hr.dy)
        ..close(),
      Paint()..color = col,
    );
  }

  static void _node(
    Canvas canvas,
    PlanNode node,
    int step,
    double ox,
    double oy,
  ) {
    final Color kc = kindColor(node.kind);
    final Rect r =
        Rect.fromLTWH(node.x + ox, node.y + oy, PlanNode.w, PlanNode.h);
    final RRect rr = RRect.fromRectAndRadius(r, const Radius.circular(18));

    canvas.drawRRect(rr, Paint()..color = C.surface);

    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width, 4), Paint()..color = kc);
    canvas.restore();

    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = C.border,
    );

    final Rect ic = Rect.fromLTWH(r.left + 14, r.top + 18, 34, 34);
    canvas.drawRRect(
      RRect.fromRectAndRadius(ic, const Radius.circular(11)),
      Paint()..color = kc.withValues(alpha: 0.16),
    );
    _glyph(
      canvas,
      node.done ? Icons.check_rounded : kindIcon(node.kind),
      ic.center,
      19,
      kc,
    );

    final double titleH = _text(
      canvas,
      node.title.isEmpty ? 'শিরোনামহীন ধাপ' : node.title,
      hand(18, color: C.text, height: 1.15, weight: 700),
      Offset(r.left + 58, r.top + 20),
      maxWidth: r.width - 74,
      maxLines: 2,
    );

    if (node.note.trim().isNotEmpty) {
      _text(
        canvas,
        node.note,
        hand(13.5, color: C.muted, height: 1.5, weight: 500),
        Offset(r.left + 58, r.top + 24 + titleH),
        maxWidth: r.width - 74,
        maxLines: 2,
      );
    }

    final String badge = 'ধাপ ${banglaNumber(step)}';
    double chipX = r.left + 14;
    chipX += _pill(canvas, badge, Offset(chipX, r.bottom - 38), kc) + 8;
    if (node.kind != NodeKind.step) {
      chipX += _pill(canvas, node.kind.label, Offset(chipX, r.bottom - 38), kc) + 8;
    }
    if (node.done) {
      _pill(canvas, 'সম্পন্ন', Offset(chipX, r.bottom - 38), C.green);
    }
  }

  static double _pillWidth(String text) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: hand(12.5, weight: 600, height: 1.0)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width + 20;
  }

  static double _pill(Canvas canvas, String text, Offset at, Color color) {
    final double w = _pillWidth(text);
    final Rect r = Rect.fromLTWH(at.dx, at.dy, w, 24);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(8)),
      Paint()..color = color.withValues(alpha: 0.14),
    );
    _text(
      canvas,
      text,
      hand(12.5, color: color, weight: 600, height: 1.0),
      Offset(r.left + 10, r.top + 4),
      maxWidth: w,
    );
    return w;
  }

  static void _glyph(
    Canvas canvas,
    IconData icon,
    Offset center,
    double size,
    Color color,
  ) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: color,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  /// Paints [text] and returns the height it occupied.
  static double _text(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset at, {
    required double maxWidth,
    int maxLines = 1,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: math.max(40, maxWidth));
    tp.paint(canvas, at);
    return tp.height;
  }

  static String _dateLabel(DateTime d) {
    const List<String> bnMonths = <String>[
      'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
      'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
    ];
    return '${banglaNumber(d.day)} ${bnMonths[d.month - 1]} ${banglaNumber(d.year)}';
  }
}

String banglaNumber(int n) {
  const List<String> bnDigits = <String>['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
  return n
      .toString()
      .split('')
      .map((String c) => int.tryParse(c) != null ? bnDigits[int.parse(c)] : c)
      .join();
}
