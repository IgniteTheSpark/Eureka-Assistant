import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'eureka_colors.dart';

/// §8 Domain system (Layer A) — the 8 life-domain labels + their accent/icon,
/// and a small reusable chip. The label IS the stored value (工作/学习/…).
///终版图标走单独 design doc;这里 emoji 仅占位。
const kDomains = ['工作', '学习', '健康', '运动', '社交', '娱乐', '生活', '灵感'];

const _domainIcon = {
  '工作': '💼', '学习': '📚', '健康': '🩺', '运动': '🏃',
  '社交': '🤝', '娱乐': '🎮', '生活': '🏠', '灵感': '💡',
};

/// Domain → accent color (reuses the §5.1 8-slot accent palette).
Color domainColor(EurekaColors eu, String domain) {
  switch (domain) {
    case '工作': return eu.accentBlue;
    case '学习': return eu.accentPurple;
    case '健康': return eu.accentGreen;
    case '运动': return eu.accentCyan;
    case '社交': return eu.accentAmber;
    case '娱乐': return eu.accentRed;
    case '生活': return eu.accentNeutral;
    case '灵感': return eu.accentGray;
    default:    return eu.textLo;
  }
}

String domainIcon(String domain) => _domainIcon[domain] ?? '🏷';

bool isDomain(String? d) => d != null && d.isNotEmpty && kDomains.contains(d);

/// Small domain chip (色点 + 2 字领域名). [dot] = pure color dot for tight space.
/// Renders nothing for null/unknown domains (不占位).
class DomainChip extends StatelessWidget {
  final String? domain;
  final bool dot;
  const DomainChip(this.domain, {super.key, this.dot = false});

  @override
  Widget build(BuildContext context) {
    final d = domain;
    if (!isDomain(d)) return const SizedBox.shrink();
    final eu = context.eu;
    final c = domainColor(eu, d!);
    if (dot) {
      return Container(
        width: 7, height: 7,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(d, style: TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
