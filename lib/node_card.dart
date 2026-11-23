import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

Color kindColor(NodeKind k) => switch (k) {
      NodeKind.start => C.green,
      NodeKind.step => C.blue,
      NodeKind.decision => C.amber,
      NodeKind.end => C.accent,
    };

IconData kindIcon(NodeKind k) => switch (k) {
      NodeKind.start => Icons.play_arrow_rounded,
      NodeKind.step => Icons.check_box_outlined,
      NodeKind.decision => Icons.call_split_rounded,
      NodeKind.end => Icons.flag_rounded,
    };

/// A single step rendered as an n8n-style node card.
class NodeCard extends StatelessWidget {
  const NodeCard({
    super.key,
    required this.node,
    required this.index,
    required this.selected,
    required this.active,
    required this.connectSource,
  });

  final PlanNode node;
  final int index;
  final bool selected;
  final bool active;
  final bool connectSource;

  @override
  Widget build(BuildContext context) {
    final Color color = kindColor(node.kind);
    final bool lit = selected || active || connectSource;
    final Color edge = connectSource
        ? C.violet
        : selected
            ? C.accent
            : active
                ? C.accent.withValues(alpha: 0.85)
                : C.border;

    return SizedBox(
      width: PlanNode.w,
      height: PlanNode.h,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: edge, width: lit ? 1.8 : 1),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
                if (lit)
                  BoxShadow(
                    color: (connectSource ? C.violet : C.accent).withValues(alpha: 0.30),
                    blurRadius: 26,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: color.withValues(alpha: 0.55)),
                        ),
                        child: Icon(kindIcon(node.kind), size: 16, color: color),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          node.title.isEmpty ? 'শিরোনামহীন ধাপ' : node.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: hand(18, height: 1.15),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 2, 13, 0),
                  child: Text(
                    node.note.isEmpty ? 'বিবরণ যোগ করতে ট্যাপ করো…' : node.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: hand(
                      14,
                      color: node.note.isEmpty ? C.muted.withValues(alpha: 0.7) : C.muted,
                      weight: 500,
                      height: 1.5,
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (node.done ? C.green : C.muted).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: (node.done ? C.green : C.muted).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          node.done ? '✓ সম্পন্ন' : 'ধাপ $index',
                          style: hand(13, color: node.done ? C.green : C.muted, weight: 600),
                        ),
                      ),
                      if (node.kind != NodeKind.step) ...<Widget>[
                        const SizedBox(width: 6),
                        Text(
                          node.kind.label,
                          style: hand(13, color: color, weight: 600),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Ports
          Positioned(
            left: PlanNode.w / 2 - 6,
            top: -6,
            child: _port(),
          ),
          Positioned(
            left: PlanNode.w / 2 - 6,
            bottom: -6,
            child: _port(),
          ),
        ],
      ),
    );
  }

  Widget _port() {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: C.surface2,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF4C5468), width: 1.6),
      ),
      child: Center(
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: connectSource ? C.violet : const Color(0xFF6B7488),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
