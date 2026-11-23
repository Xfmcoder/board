import 'dart:math' as math;
import 'dart:ui' show Rect;

enum NodeKind { start, step, decision, end }

extension NodeKindX on NodeKind {
  String get label => switch (this) {
        NodeKind.start => 'শুরু',
        NodeKind.step => 'ধাপ',
        NodeKind.decision => 'সিদ্ধান্ত',
        NodeKind.end => 'শেষ',
      };
}

NodeKind kindFromKey(String? key) => NodeKind.values.firstWhere(
      (NodeKind k) => k.name == key,
      orElse: () => NodeKind.step,
    );

int _seq = 0;

String newId(String prefix) {
  _seq++;
  return '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$_seq';
}

class PlanNode {
  PlanNode({
    required this.id,
    required this.title,
    this.note = '',
    this.kind = NodeKind.step,
    this.x = 0,
    this.y = 0,
    this.done = false,
  });

  /// Node cards are fixed size so the canvas can compute its content bounds.
  static const double w = 248;
  static const double h = 164;

  final String id;
  String title;
  String note;
  NodeKind kind;
  double x;
  double y;
  bool done;

  PlanNode copyWith({String? id, String? title, String? note, NodeKind? kind, double? x, double? y, bool? done}) {
    return PlanNode(
      id: id ?? this.id,
      title: title ?? this.title,
      note: note ?? this.note,
      kind: kind ?? this.kind,
      x: x ?? this.x,
      y: y ?? this.y,
      done: done ?? this.done,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'note': note,
        'kind': kind.name,
        'x': x,
        'y': y,
        'done': done,
      };

  factory PlanNode.fromJson(Map<String, dynamic> j) => PlanNode(
        id: (j['id'] ?? newId('n')).toString(),
        title: (j['title'] ?? '').toString(),
        note: (j['note'] ?? '').toString(),
        kind: kindFromKey(j['kind']?.toString()),
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        done: j['done'] == true,
      );
}

class PlanEdge {
  const PlanEdge({required this.from, required this.to});

  final String from;
  final String to;

  Map<String, dynamic> toJson() => <String, dynamic>{'from': from, 'to': to};

  factory PlanEdge.fromJson(Map<String, dynamic> j) =>
      PlanEdge(from: j['from'].toString(), to: j['to'].toString());
}

/// A "প্লেন" — an ordered set of steps drawn as a node graph.
class BoardPlan {
  BoardPlan({
    required this.id,
    required this.name,
    required this.nodes,
    required this.edges,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  String name;
  final List<PlanNode> nodes;
  final List<PlanEdge> edges;
  final DateTime createdAt;
  DateTime updatedAt;

  static BoardPlan empty(String name) => BoardPlan(
        id: newId('p'),
        name: name.trim().isEmpty ? 'নতুন প্লেন' : name.trim(),
        nodes: <PlanNode>[],
        edges: <PlanEdge>[],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  int get doneCount => nodes.where((PlanNode n) => n.done).length;

  double get progress => nodes.isEmpty ? 0 : doneCount / nodes.length;

  PlanNode? nodeById(String id) {
    for (final PlanNode n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  PlanNode? get lastNode => nodes.isEmpty ? null : nodes.last;

  PlanNode addStep({
    NodeKind kind = NodeKind.step,
    String title = '',
    String note = '',
    bool link = true,
  }) {
    final PlanNode? last = lastNode;
    final int index = nodes.length;
    double x = 90;
    double y = 110;
    if (last != null) {
      // Vertical flow: each step sits under the previous one, so a phone-width
      // canvas stays readable at 100% zoom (n8n's top-down layout).
      x = last.x + (index.isEven ? 0 : 26);
      y = last.y + PlanNode.h + 86;
    }
    final PlanNode node = PlanNode(
      id: newId('n'),
      title: title,
      note: note,
      kind: kind,
      x: x,
      y: y,
    );
    nodes.add(node);
    if (link && last != null) {
      edges.add(PlanEdge(from: last.id, to: node.id));
    }
    touch();
    return node;
  }

  void removeNode(String id) {
    nodes.removeWhere((PlanNode n) => n.id == id);
    edges.removeWhere((PlanEdge e) => e.from == id || e.to == id);
    touch();
  }

  void connect(String from, String to) {
    if (from == to) return;
    final bool exists = edges.any((PlanEdge e) => e.from == from && e.to == to);
    if (exists) return;
    edges.add(PlanEdge(from: from, to: to));
    touch();
  }

  void disconnect(String from, String to) {
    edges.removeWhere((PlanEdge e) => e.from == from && e.to == to);
    touch();
  }

  void touch() => updatedAt = DateTime.now();

  void relayout({bool chain = true}) {
    if (!chain) return;
    for (int i = 0; i < nodes.length; i++) {
      nodes[i].x = 90 + (i.isEven ? 0 : 26);
      nodes[i].y = 120 + i * (PlanNode.h + 86);
    }
    touch();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'nodes': nodes.map((PlanNode n) => n.toJson()).toList(),
        'edges': edges.map((PlanEdge e) => e.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory BoardPlan.fromJson(Map<String, dynamic> j) => BoardPlan(
        id: (j['id'] ?? newId('p')).toString(),
        name: (j['name'] ?? 'প্লেন').toString(),
        nodes: ((j['nodes'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic e) => PlanNode.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        edges: ((j['edges'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic e) => PlanEdge.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()) ?? DateTime.now(),
        updatedAt: DateTime.tryParse((j['updatedAt'] ?? '').toString()) ?? DateTime.now(),
      );

  /// A small starter plan so the first launch is not an empty screen.
  static BoardPlan demo() {
    final BoardPlan p = empty('আমার প্রথম প্লেন');
    p.addStep(kind: NodeKind.start, title: 'লক্ষ্য ঠিক করো', note: 'যা করতে চাও, এক লাইনে লিখে ফেলো');
    p.addStep(title: 'তথ্য জোগাড়', note: 'কী কী দরকার — তালিকা করো');
    p.addStep(kind: NodeKind.decision, title: 'যাচাই করো', note: 'তথ্য ঠিক আছে কি না দেখো');
    p.addStep(title: 'কাজ শুরু', note: 'প্রথম ছোট কাজটা সেরে ফেলো');
    p.addStep(kind: NodeKind.end, title: 'শেষ করো', note: 'ফলাফল মিলিয়ে দেখো');
    p.nodes[1].done = true;
    return p;
  }
}

/// Bounding box that contains every node, used for fit-to-view and export crop.
Rect contentBounds(BoardPlan plan, {double pad = 44}) {
  if (plan.nodes.isEmpty) return const Rect.fromLTWH(0, 0, 1200, 800);
  double minX = double.infinity;
  double minY = double.infinity;
  double maxX = -double.infinity;
  double maxY = -double.infinity;
  for (final PlanNode n in plan.nodes) {
    minX = math.min(minX, n.x);
    minY = math.min(minY, n.y);
    maxX = math.max(maxX, n.x + PlanNode.w);
    maxY = math.max(maxY, n.y + PlanNode.h);
  }
  return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
}
