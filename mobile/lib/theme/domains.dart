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

/// §8 域色 = 身份色,B「潮汐」低饱和 8 色板(2026-06 锁定;源 = 今日页重设计稿)。
/// **与 §5.1 功能 accent 槽解耦** —— `accentRed/Green/Amber` 还要当 错误/成功/警告,
/// 不能被域色染,故域色独立写死在此。日历 dot + 今日页气泡/卡 共用本函数 → 自动对齐。
/// theme-independent(域色 = 身份,不随日夜变);[eu] 仅保签名 + 未知域兜底。
const _domainColor = {
  '工作': Color(0xFF8AB4FF), '学习': Color(0xFFB89CF0),
  '健康': Color(0xFF84C9A0), '运动': Color(0xFF6FD0D8),
  '社交': Color(0xFFF5C977), '娱乐': Color(0xFFF08A8A),
  '生活': Color(0xFF9FB0C9), '灵感': Color(0xFFC3BCD0),
};

Color domainColor(EurekaColors eu, String domain) =>
    _domainColor[domain] ?? eu.textLo;

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
