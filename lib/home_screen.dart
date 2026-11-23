import 'package:flutter/material.dart';

import 'board_screen.dart';
import 'export_service.dart';
import 'models.dart';
import 'node_card.dart';
import 'storage.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PlanStore _store = PlanStore();
  List<BoardPlan> _plans = <BoardPlan>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<BoardPlan> plans = await _store.loadAll();
    if (plans.isEmpty) {
      final BoardPlan demo = BoardPlan.demo();
      await _store.save(demo);
      plans = <BoardPlan>[demo];
    }
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _loading = false;
    });
  }

  Future<void> _open(BoardPlan plan) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(builder: (BuildContext ctx) => BoardScreen(plan: plan)),
    );
    _load();
  }

  Future<void> _newPlan() async {
    final TextEditingController c = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('নতুন প্লেন', style: hand(26)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'এই প্লেনের একটা নাম দাও',
              style: hand(15, color: C.muted, weight: 500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              style: hand(20),
              decoration: const InputDecoration(hintText: 'যেমন: অক্টোবর ক্যাম্পেইন'),
              onSubmitted: (String v) => Navigator.of(ctx).pop(v),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('বাতিল', style: hand(17, color: C.muted, weight: 600)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text),
            style: FilledButton.styleFrom(
              backgroundColor: C.accent,
              foregroundColor: Colors.black,
            ),
            child: Text('তৈরি করো', style: hand(17, color: Colors.black)),
          ),
        ],
      ),
    );
    if (name == null) return;
    final BoardPlan plan = BoardPlan.empty(name.isEmpty ? 'আমার প্লেন' : name);
    await _store.save(plan);
    if (!mounted) return;
    await _open(plan);
  }

  Future<void> _rename(BoardPlan plan) async {
    final TextEditingController c = TextEditingController(text: plan.name);
    final String? v = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('নাম বদলাও', style: hand(24)),
        content: TextField(controller: c, autofocus: true, style: hand(20)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('বাতিল', style: hand(17, color: C.muted, weight: 600)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: C.accent, foregroundColor: Colors.black),
            child: Text('সেভ', style: hand(17, color: Colors.black)),
          ),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    plan.name = v;
    plan.touch();
    await _store.save(plan);
    _load();
  }

  Future<void> _duplicate(BoardPlan plan) async {
    final BoardPlan copy = BoardPlan.fromJson(plan.toJson());
    final BoardPlan clone = BoardPlan(
      id: newId('p'),
      name: '${plan.name} (কপি)',
      nodes: copy.nodes.map((PlanNode n) => n.copyWith(id: newId('n'))).toList(),
      edges: <PlanEdge>[],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final Map<String, String> idMap = <String, String>{
      for (int i = 0; i < plan.nodes.length; i++) plan.nodes[i].id: clone.nodes[i].id,
    };
    for (final PlanEdge e in plan.edges) {
      final String? f = idMap[e.from];
      final String? t = idMap[e.to];
      if (f != null && t != null) clone.edges.add(PlanEdge(from: f, to: t));
    }
    await _store.save(clone);
    _load();
  }

  Future<void> _delete(BoardPlan plan) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('প্লেন মুছে ফেলবে?', style: hand(23)),
        content: Text(
          '“${plan.name}” স্থায়ীভাবে মুছে যাবে।',
          style: hand(16, color: C.muted, weight: 500, height: 1.4),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('না', style: hand(17, color: C.muted, weight: 600)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF6B6B), foregroundColor: Colors.black),
            child: Text('মুছে ফেলো', style: hand(17, color: Colors.black)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.delete(plan.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final int totalSteps = _plans.fold(0, (int a, BoardPlan p) => a + p.nodes.length);
    final int doneSteps = _plans.fold(0, (int a, BoardPlan p) => a + p.doneCount);

    return Scaffold(
      backgroundColor: C.bg,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SizedBox(
          width: 220,
          height: 54,
          child: FilledButton.icon(
            onPressed: _newPlan,
            icon: const Icon(Icons.add_rounded, color: Colors.black, size: 22),
            label: Text('নতুন প্লেন', style: hand(20, color: Colors.black)),
            style: FilledButton.styleFrom(
              backgroundColor: C.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
              elevation: 6,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: C.accent))
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 124),
                children: <Widget>[
                  _header(),
                  const SizedBox(height: 18),
                  _stats(totalSteps, doneSteps),
                  const SizedBox(height: 22),
                  Row(
                    children: <Widget>[
                      Text('আমার প্লেন', style: hand(22)),
                      const SizedBox(width: 8),
                      Text(
                        '(${banglaNumber(_plans.length)})',
                        style: hand(16, color: C.muted, weight: 500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ..._plans.map(_planCard),
                  const SizedBox(height: 10),
                  _tipCard(),
                ],
              ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: <Widget>[
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[C.accent, C.violet],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: <BoxShadow>[
              BoxShadow(color: C.accent.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 6)),
            ],
          ),
          child: Center(child: Text('ব', style: hand(30, color: Colors.black))),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('বোর্ড', style: hand(34, height: 1.0)),
            Text(
              'প্রজেক্ট প্লেনার • ধাপে ধাপে',
              style: hand(14, color: C.muted, weight: 500),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: C.border),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.offline_bolt_rounded, size: 14, color: C.green),
              const SizedBox(width: 4),
              Text('অফলাইন', style: hand(13, color: C.muted, weight: 600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stats(int totalSteps, int doneSteps) {
    return Row(
      children: <Widget>[
        _statTile('প্লেন', '${_plans.length}', C.blue),
        const SizedBox(width: 10),
        _statTile('মোট ধাপ', '$totalSteps', C.amber),
        const SizedBox(width: 10),
        _statTile('সম্পন্ন', '$doneSteps', C.green),
      ],
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  value,
                  style: hand(31, color: color, height: 1.0, weight: 700),
                ),
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    'টি',
                    style: hand(12, color: color.withValues(alpha: 0.75)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(label, style: hand(13, color: C.muted, weight: 500)),
          ],
        ),
      ),
    );
  }

  /// Little node chain so each card previews the actual flow.
  Widget _miniFlow(BoardPlan plan) {
    if (plan.nodes.isEmpty) return const SizedBox.shrink();
    final List<PlanNode> ns = plan.nodes.take(6).toList();
    final int extra = plan.nodes.length - ns.length;
    final List<Widget> row = <Widget>[];
    for (int i = 0; i < ns.length; i++) {
      if (i > 0) {
        row.add(Container(
          width: 13,
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          color: const Color(0xFF343A4A),
        ));
      }
      final Color kc = kindColor(ns[i].kind);
      row.add(Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: kc.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: kc.withValues(alpha: 0.45)),
        ),
        child: Icon(
          ns[i].done ? Icons.check_rounded : kindIcon(ns[i].kind),
          size: 15,
          color: kc,
        ),
      ));
    }
    if (extra > 0) {
      row.add(Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Text(
          '+$extra',
          style: hand(14, color: C.muted, weight: 600),
        ),
      ));
    }
    return SizedBox(
      height: 30,
      child: Row(children: row),
    );
  }

  Widget _planCard(BoardPlan plan) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _open(plan),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: C.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      plan.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: hand(22, height: 1.15),
                    ),
                  ),
                  PopupMenuButton<String>(
                    color: C.surface2,
                    icon: const Icon(Icons.more_horiz_rounded, color: C.muted, size: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onSelected: (String v) {
                      switch (v) {
                        case 'rename':
                          _rename(plan);
                        case 'duplicate':
                          _duplicate(plan);
                        case 'delete':
                          _delete(plan);
                      }
                    },
                    itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'rename',
                        child: Text('নাম বদলাও', style: hand(17, weight: 600)),
                      ),
                      PopupMenuItem<String>(
                        value: 'duplicate',
                        child: Text('কপি বানাও', style: hand(17, weight: 600)),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('মুছে ফেলো', style: hand(17, color: const Color(0xFFFF7A7A), weight: 600)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _miniFlow(plan),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  _chip('${banglaNumber(plan.nodes.length)} ধাপ', C.blue),
                  const SizedBox(width: 6),
                  _chip('${banglaNumber(plan.doneCount)} সম্পন্ন', C.green),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      _ago(plan.updatedAt),
                      style: hand(13, color: C.muted, weight: 500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _progressBar(plan.progress),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progressBar(double v) {
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints cs) {
        final double w = cs.maxWidth * v.clamp(0.0, 1.0);
        return Container(
          height: 5,
          decoration: BoxDecoration(
            color: C.surface2,
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.centerLeft,
          child: w <= 0
              ? const SizedBox.shrink()
              : Container(
                  width: w,
                  height: 5,
                  decoration: BoxDecoration(
                    color: C.green,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
        );
      },
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: hand(13, color: color, weight: 600)),
    );
  }

  Widget _tipCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.border),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.lightbulb_outline_rounded, color: C.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'ক্যানভাসে নোড টেনে সাজাও, ▶ ধাপে ধাপে চালাও, তারপর JPG বা PDF ডাউনলোড করো।',
              style: hand(15, color: C.muted, weight: 500, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  String _ago(DateTime d) {
    final Duration diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'এইমাত্র';
    if (diff.inMinutes < 60) return '${banglaNumber(diff.inMinutes)} মিনিট আগে';
    if (diff.inHours < 24) return '${banglaNumber(diff.inHours)} ঘণ্টা আগে';
    if (diff.inDays < 30) return '${banglaNumber(diff.inDays)} দিন আগে';
    return '${banglaNumber((diff.inDays / 30).floor())} মাস আগে';
  }
}
