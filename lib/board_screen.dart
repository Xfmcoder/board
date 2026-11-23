import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import 'export_service.dart';
import 'models.dart';
import 'node_card.dart';
import 'painters.dart';
import 'storage.dart';
import 'theme.dart';

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, required this.plan});

  final BoardPlan plan;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> with SingleTickerProviderStateMixin {
  late BoardPlan plan;
  final TransformationController _tc = TransformationController();
  final GlobalKey _captureKey = GlobalKey();
  final PlanStore _store = PlanStore();
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  String? _selectedId;
  String? _connectFrom;
  bool _connectMode = false;
  int? _step;
  bool _exporting = false;
  Size _viewport = const Size(380, 640);

  @override
  void initState() {
    super.initState();
    plan = widget.plan;
    plan.touch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitView();
      _persist();
    });
  }

  @override
  void dispose() {
    _flow.dispose();
    _tc.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- helpers

  void _persist() {
    unawaited(_store.save(plan));
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: hand(16, weight: 600)),
          backgroundColor: C.surface2,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          duration: const Duration(milliseconds: 2200),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
  }

  Size _worldSize() {
    final Rect b = contentBounds(plan, pad: 0);
    return Size(
      math.max(1700, b.right + 280),
      math.max(1150, b.bottom + 280),
    );
  }

  double get _scale => _tc.value.getMaxScaleOnAxis();

  Matrix4 _matrix(double s, double tx, double ty) {
    final Matrix4 m = Matrix4.identity();
    m.setEntry(0, 0, s);
    m.setEntry(1, 1, s);
    m.setEntry(0, 3, tx);
    m.setEntry(1, 3, ty);
    return m;
  }

  bool _viewSet = false;

  /// Default view: full-size nodes (readable text) with the flow's head near
  /// the top of the screen — a phone can't fit a whole plan at 100%.
  void _homeView() {
    if (!mounted) return;
    final double s = 1.0;
    if (plan.nodes.isEmpty) {
      _tc.value = _matrix(s, 0, 0);
      return;
    }
    final PlanNode first = plan.nodes.first;
    final double tx = _viewport.width / 2 - (first.x + PlanNode.w / 2) * s;
    final double ty = 26 - first.y * s;
    _tc.value = _matrix(s, tx, ty);
  }

  void _fitView() {
    if (!mounted) return;
    final Rect b = contentBounds(plan, pad: 70);
    final double s = math
        .min(_viewport.width / b.width, _viewport.height / b.height)
        .clamp(0.28, 1.4);
    final double tx = _viewport.width / 2 - (b.left + b.width / 2) * s;
    final double ty = _viewport.height / 2 - (b.top + b.height / 2) * s;
    _tc.value = _matrix(s, tx, ty);
  }

  void _centerOn(PlanNode n) {
    final double s = math.min(1.0, math.max(0.95, _scale));
    final double tx = _viewport.width / 2 - (n.x + PlanNode.w / 2) * s;
    final double ty = _viewport.height / 2 - (n.y + PlanNode.h / 2) * s - 60;
    _tc.value = _matrix(s, tx, ty);
  }

  void _zoom(double factor) {
    final double s = _scale;
    final double ns = (s * factor).clamp(0.28, 2.4);
    final double k = ns / s;
    final Offset t = Offset(_tc.value.getTranslation().x, _tc.value.getTranslation().y);
    final Offset c = Offset(_viewport.width / 2, _viewport.height / 2);
    final double tx = c.dx - k * (c.dx - t.dx);
    final double ty = c.dy - k * (c.dy - t.dy);
    _tc.value = _matrix(ns, tx, ty);
  }

  // ---------------------------------------------------------------- actions

  void _addStep([NodeKind kind = NodeKind.step]) {
    final PlanNode n = plan.addStep(kind: kind, title: _defaultTitle(kind));
    setState(() {
      _selectedId = n.id;
      _step = null;
    });
    _persist();
    Future<void>.delayed(const Duration(milliseconds: 60), () {
      _centerOn(n);
      _openEditor(n, fresh: true);
    });
  }

  String _defaultTitle(NodeKind kind) => switch (kind) {
        NodeKind.start => 'শুরু করো',
        NodeKind.step => 'নতুন ধাপ',
        NodeKind.decision => 'শর্ত যাচাই',
        NodeKind.end => 'শেষ করো',
      };

  void _onNodeTap(PlanNode n) {
    if (_connectMode) {
      setState(() {
        if (_connectFrom == null) {
          _connectFrom = n.id;
        } else if (_connectFrom == n.id) {
          _connectFrom = null;
        } else {
          plan.connect(_connectFrom!, n.id);
          _connectFrom = null;
          _connectMode = false;
        }
      });
      _persist();
      return;
    }
    setState(() => _selectedId = n.id);
    _openEditor(n);
  }

  Future<void> _openEditor(PlanNode n, {bool fresh = false}) async {
    String title = n.title;
    String note = n.note;
    NodeKind kind = n.kind;
    bool done = n.done;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (BuildContext ctx, StateSetter setSheet) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: C.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('ধাপ সম্পাদনা', style: hand(26)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: TextEditingController(text: title),
                      autofocus: fresh,
                      style: hand(22, height: 1.2),
                      decoration: const InputDecoration(hintText: 'ধাপের নাম'),
                      onChanged: (String v) {
                        title = v;
                        n.title = v;
                        setSheet(() {});
                        setState(() {});
                        _persist();
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: TextEditingController(text: note),
                      maxLines: 3,
                      style: hand(17, weight: 500, height: 1.4),
                      decoration: const InputDecoration(hintText: 'কী করতে হবে, বিস্তারিত…'),
                      onChanged: (String v) {
                        note = v;
                        n.note = v;
                        setSheet(() {});
                        setState(() {});
                        _persist();
                      },
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: NodeKind.values.map((NodeKind k) {
                        final bool on = kind == k;
                        return GestureDetector(
                          onTap: () {
                            setSheet(() => kind = k);
                            n.kind = k;
                            setState(() {});
                            _persist();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: on ? kindColor(k).withValues(alpha: 0.16) : C.surface2,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: on ? kindColor(k) : C.border,
                                width: on ? 1.6 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(kindIcon(k), size: 15, color: kindColor(k)),
                                const SizedBox(width: 6),
                                Text(
                                  k.label,
                                  style: hand(15, color: on ? kindColor(k) : C.muted, weight: 600),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Switch(
                          value: done,
                          activeThumbColor: C.green,
                          onChanged: (bool v) {
                            setSheet(() => done = v);
                            n.done = v;
                            setState(() {});
                            _persist();
                          },
                        ),
                        Text('সম্পন্ন হিসেবে চিহ্নিত', style: hand(17, weight: 600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              setState(() {
                                plan.removeNode(n.id);
                                if (_selectedId == n.id) _selectedId = null;
                                if (_connectFrom == n.id) _connectFrom = null;
                                if (_step != null && _step! >= plan.nodes.length && plan.nodes.isNotEmpty) {
                                  _step = plan.nodes.length - 1;
                                }
                              });
                              _persist();
                            },
                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFFF7A7A)),
                            label: Text('মুছে ফেলো', style: hand(17, color: const Color(0xFFFF7A7A), weight: 600)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0x55FF7A7A)),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: FilledButton.styleFrom(
                              backgroundColor: C.accent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            child: Text('ঠিক আছে', style: hand(18, color: Colors.black)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    if (mounted) setState(() {});
  }

  void _startStepMode() {
    if (plan.nodes.isEmpty) {
      _toast('আগে অন্তত একটা ধাপ যোগ করো');
      return;
    }
    setState(() {
      _step = 0;
      _connectMode = false;
      _selectedId = null;
    });
    _centerOn(plan.nodes[0]);
  }

  void _goStep(int delta) {
    if (_step == null) return;
    final int next = (_step! + delta).clamp(0, plan.nodes.length - 1);
    setState(() => _step = next);
    _centerOn(plan.nodes[next]);
  }

  void _toggleDone() {
    if (_step == null) return;
    final PlanNode n = plan.nodes[_step!];
    setState(() => n.done = !n.done);
    _persist();
  }

  Future<void> _export({required bool asPdf}) async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _step = null;
      _selectedId = null;
      _connectMode = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 140));
    try {
      final Uint8List bytes = await ExportService.build(
        plan: plan,
        asPdf: asPdf,
      );

      final String name = _fileName(plan.name);
      final String path = await FileSaver.instance.saveFile(
        name: name,
        bytes: bytes,
        fileExtension: asPdf ? 'pdf' : 'jpg',
        mimeType: asPdf ? MimeType.pdf : MimeType.jpeg,
      );
      _toast('সেভ হয়েছে → $path');
    } catch (e) {
      _toast('এক্সপোর্ট ব্যর্থ: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _fileName(String raw) {
    final String cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '')
        .replaceAll(RegExp(r'\s+'), '-');
    return cleaned.isEmpty ? 'board-plan' : cleaned;
  }

  Future<void> _renamePlan() async {
    final TextEditingController c = TextEditingController(text: plan.name);
    final String? v = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('প্লেনের নাম', style: hand(24)),
        content: TextField(
          controller: c,
          autofocus: true,
          style: hand(20),
          decoration: const InputDecoration(hintText: 'নাম লিখো'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('বাতিল', style: hand(17, color: C.muted, weight: 600)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: C.accent,
              foregroundColor: Colors.black,
            ),
            child: Text('সেভ', style: hand(17, color: Colors.black)),
          ),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      setState(() {
        plan.name = v;
        plan.touch();
      });
      _persist();
    }
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _topBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext ctx, BoxConstraints cons) {
                  _viewport = Size(cons.maxWidth, cons.maxHeight);
                  if (!_viewSet) {
                    _viewSet = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) => _homeView());
                  }
                  return Stack(
                          children: <Widget>[
                            Positioned.fill(child: _canvas()),
                            if (plan.nodes.isEmpty) _emptyHint(),
                            if (_step != null)
                              Positioned(
                                left: 10,
                                right: 10,
                                bottom: 84,
                                child: _stepPanel(),
                              ),
                            Positioned(
                              bottom: 14,
                              left: 0,
                              right: 0,
                              child: Center(child: _dock()),
                            ),
                            if (_exporting)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        const CircularProgressIndicator(color: C.accent),
                                        const SizedBox(height: 14),
                                        Text('এক্সপোর্ট হচ্ছে…', style: hand(18, color: C.text)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: C.surface,
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'ফিরে যাও',
            onPressed: () async {
              await _store.save(plan);
              if (mounted) Navigator.of(context).pop(true);
            },
            icon: const Icon(Icons.arrow_back_rounded, color: C.muted),
          ),
          Expanded(
            child: GestureDetector(
              onTap: _renamePlan,
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    plan.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: hand(22, height: 1.1),
                  ),
                  Text(
                    '${banglaNumber(plan.nodes.length)} ধাপ • ${banglaNumber(plan.doneCount)} সম্পন্ন',
                    style: hand(13, color: C.muted, weight: 500),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'সেভ',
            onPressed: () async {
              plan.touch();
              await _store.save(plan);
              _toast('প্লেন সেভ হয়েছে');
            },
            icon: const Icon(Icons.save_rounded, color: C.green),
          ),
          PopupMenuButton<String>(
            color: C.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            icon: const Icon(Icons.more_vert_rounded, color: C.muted),
            onSelected: (String v) {
              switch (v) {
                case 'jpg':
                  _export(asPdf: false);
                case 'pdf':
                  _export(asPdf: true);
                case 'steps':
                  _startStepMode();
                case 'fit':
                  _fitView();
                case 'relayout':
                  setState(() => plan.relayout());
                  _persist();
              }
            },
            itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
              _menu('jpg', Icons.image_rounded, 'JPG ডাউনলোড'),
              _menu('pdf', Icons.picture_as_pdf_rounded, 'PDF ডাউনলোড'),
              const PopupMenuDivider(),
              _menu('steps', Icons.play_circle_outline_rounded, 'ধাপে ধাপে মোড'),
              _menu('relayout', Icons.auto_awesome_motion_rounded, 'সাজিয়ে দাও'),
              _menu('fit', Icons.center_focus_strong_rounded, 'পুরো প্লেন দেখাও'),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menu(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: C.muted),
          const SizedBox(width: 10),
          Text(label, style: hand(17, weight: 600)),
        ],
      ),
    );
  }

  Widget _rail() {
    return Container(
      width: 74,
      decoration: const BoxDecoration(
        color: C.surface,
        border: Border(right: BorderSide(color: C.border)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            const SizedBox(height: 10),
            _railLabel('নোড'),
            _railBtn(Icons.play_arrow_rounded, 'শুরু', C.green, () => _addStep(NodeKind.start)),
            _railBtn(Icons.check_box_outlined, 'ধাপ', C.blue, () => _addStep(NodeKind.step)),
            _railBtn(Icons.call_split_rounded, 'শর্ত', C.amber, () => _addStep(NodeKind.decision)),
            _railBtn(Icons.flag_rounded, 'শেষ', C.accent, () => _addStep(NodeKind.end)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Divider(color: C.border, height: 1),
            ),
            _railLabel('টুল'),
            _railBtn(
              Icons.timeline_rounded,
              'যোগ',
              _connectMode ? C.violet : C.muted,
              () {
                setState(() {
                  _connectMode = !_connectMode;
                  _connectFrom = null;
                });
                if (_connectMode) _toast('প্রথম নোড, তারপর পরের নোড ট্যাপ করো');
              },
              active: _connectMode,
            ),
            _railBtn(Icons.play_circle_outline_rounded, 'ধাপ', C.green, _startStepMode),
            _railBtn(Icons.ios_share_rounded, 'সেভ', C.muted, _exportSheet),
            _railBtn(Icons.fit_screen_rounded, 'ফিট', C.muted, _fitView),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  Widget _railLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Text(t, style: hand(12, color: C.muted.withValues(alpha: 0.7), weight: 500)),
      );

  Widget _railBtn(IconData icon, String label, Color color, VoidCallback onTap, {bool active = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 56,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? color.withValues(alpha: 0.6) : Colors.transparent),
        ),
        child: Column(
          children: <Widget>[
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 3),
            Text(label, style: hand(12.5, color: C.muted, weight: 600)),
          ],
        ),
      ),
    );
  }

  Widget _statPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: C.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: C.green, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '${banglaNumber(plan.nodes.length)} ধাপ • ${banglaNumber(plan.edges.length)} সংযোগ',
            style: hand(13, color: C.muted, weight: 600),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.add_box_outlined, size: 46, color: C.muted.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Text('ক্যানভাস খালি', style: hand(24, color: C.text)),
          const SizedBox(height: 4),
          Text(
            'বাঁ দিকের “ধাপ” চেপে প্রথম কাজ যোগ করো',
            style: hand(15, color: C.muted, weight: 500),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _addStep(),
            icon: const Icon(Icons.add_rounded, size: 18, color: Colors.black),
            label: Text('প্রথম ধাপ যোগ করো', style: hand(17, color: Colors.black)),
            style: FilledButton.styleFrom(
              backgroundColor: C.accent,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _canvas() {
    final Size world = _worldSize();
    final Map<String, PlanNode> byId = <String, PlanNode>{
      for (final PlanNode n in plan.nodes) n.id: n,
    };
    final Set<String> live = <String>{};
    if (_step != null && _step! < plan.nodes.length) {
      final PlanNode n = plan.nodes[_step!];
      live.add(n.id);
      for (final PlanEdge e in plan.edges) {
        if (e.from == n.id) live.add(e.to);
        if (e.to == n.id) live.add(e.from);
      }
    }

    return ClipRect(
      child: InteractiveViewer(
        transformationController: _tc,
        constrained: false,
        minScale: 0.28,
        maxScale: 2.4,
        panEnabled: true,
        scaleEnabled: true,
        boundaryMargin: const EdgeInsets.all(1200),
        child: RepaintBoundary(
          key: _captureKey,
          child: SizedBox(
            width: world.width,
            height: world.height,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(painter: const GridPainter()),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _flow,
                      builder: (BuildContext ctx, Widget? child) {
                        return CustomPaint(
                          painter: EdgePainter(
                            nodes: byId,
                            edges: plan.edges,
                            highlight: live,
                            phase: _flow.value,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (_step != null && _step! < plan.nodes.length)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: ActiveHaloPainter(node: plan.nodes[_step!])),
                    ),
                  ),
                for (int i = 0; i < plan.nodes.length; i++) _nodeWidget(plan.nodes[i], i, world),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _nodeWidget(PlanNode n, int i, Size world) {
    return Positioned(
      left: n.x,
      top: n.y,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onNodeTap(n),
        onPanStart: (_) => setState(() => _selectedId = n.id),
        onPanUpdate: (DragUpdateDetails d) {
          final double s = _scale;
          setState(() {
            n.x = (n.x + d.delta.dx / s).clamp(0.0, world.width - PlanNode.w - 30);
            n.y = (n.y + d.delta.dy / s).clamp(0.0, world.height - PlanNode.h - 30);
            plan.touch();
          });
        },
        onPanEnd: (_) => _persist(),
        child: NodeCard(
          node: n,
          index: i + 1,
          selected: _selectedId == n.id,
          active: _step == i,
          connectSource: _connectFrom == n.id,
        ),
      ),
    );
  }

  Widget _stepPanel() {
    final PlanNode n = plan.nodes[_step!];
    final bool last = _step == plan.nodes.length - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.accent.withValues(alpha: 0.5)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: C.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'ধাপ ${banglaNumber(_step! + 1)} / ${banglaNumber(plan.nodes.length)}',
                  style: hand(14, color: C.accent, weight: 600),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _step = null),
                child: const Icon(Icons.close_rounded, size: 20, color: C.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_step! + (n.done ? 1 : 0)) / plan.nodes.length,
              minHeight: 5,
              backgroundColor: C.surface2,
              valueColor: const AlwaysStoppedAnimation<Color>(C.accent),
            ),
          ),
          const SizedBox(height: 12),
          Text(n.title.isEmpty ? 'শিরোনামহীন ধাপ' : n.title, style: hand(25, height: 1.15)),
          if (n.note.isNotEmpty) ...<Widget>[
            const SizedBox(height: 3),
            Text(n.note, style: hand(16, color: C.muted, weight: 500, height: 1.4)),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _panelBtn(
                icon: Icons.arrow_back_rounded,
                label: 'আগের',
                onTap: _step == 0 ? null : () => _goStep(-1),
                color: C.muted,
              ),
              const SizedBox(width: 8),
              _panelBtn(
                icon: n.done ? Icons.undo_rounded : Icons.check_rounded,
                label: n.done ? 'আবার বাকি' : 'সম্পন্ন',
                onTap: _toggleDone,
                color: n.done ? C.amber : C.green,
                filled: true,
              ),
              const SizedBox(width: 8),
              _panelBtn(
                icon: last ? Icons.done_all_rounded : Icons.arrow_forward_rounded,
                label: last ? 'শেষ' : 'পরের',
                onTap: last ? () => setState(() => _step = null) : () => _goStep(1),
                color: C.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panelBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color color,
    bool filled = false,
  }) {
    return Expanded(
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: filled ? color.withValues(alpha: 0.16) : C.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: filled ? color.withValues(alpha: 0.7) : C.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 6),
                Text(label, style: hand(16, color: color, weight: 600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: C.surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: C.border),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _dockBtn(Icons.add_rounded, () => _addStep(), bg: C.accent),
          const SizedBox(width: 4),
          _dockBtn(
            Icons.timeline_rounded,
            () {
              setState(() {
                _connectMode = !_connectMode;
                _connectFrom = null;
              });
            },
            color: _connectMode ? C.violet : C.muted,
          ),
          _dockBtn(Icons.play_circle_outline_rounded, _startStepMode, color: C.green),
          const SizedBox(width: 4),
          Container(width: 1, height: 24, color: C.border),
          const SizedBox(width: 4),
          _dockBtn(Icons.center_focus_strong_rounded, _fitView, color: C.muted),
          _dockBtn(Icons.ios_share_rounded, _exportSheet, color: C.muted),
        ],
      ),
    );
  }

  Widget _dockBtn(IconData icon, VoidCallback onTap, {Color color = C.muted, Color? bg}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: bg ?? Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: bg != null ? Colors.black : color),
      ),
    );
  }

  void _exportSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('প্লেন ডাউনলোড', style: hand(26)),
            const SizedBox(height: 4),
            Text(
              'পুরো বোর্ডের ছবি ফাইলে সেভ হবে',
              style: hand(15, color: C.muted, weight: 500),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _exportTile(
                    icon: Icons.image_rounded,
                    title: 'JPG',
                    sub: 'ছবি হিসেবে',
                    color: C.blue,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _export(asPdf: false);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _exportTile(
                    icon: Icons.picture_as_pdf_rounded,
                    title: 'PDF',
                    sub: 'প্রিন্ট/শেয়ার',
                    color: C.accent,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _export(asPdf: true);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _exportTile({
    required IconData icon,
    required String title,
    required String sub,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: C.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: C.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 10),
            Text(title, style: hand(21)),
            Text(sub, style: hand(14, color: C.muted, weight: 500)),
          ],
        ),
      ),
    );
  }
}
