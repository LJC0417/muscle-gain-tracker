/// 复用 UI 组件（ARCHITECTURE F04）
/// 严格对齐 prototype 视觉：
///   - Card：白卡 + 圆角 16 + 微阴影
///   - RingProgress：conic-gradient 圆环 + 内圈挖空
///   - MacroBar / MacroRow：蛋白/碳水/脂肪横条
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 通用白卡片。
class MgCard extends StatelessWidget {
  final String? title;
  final String? sub;
  final Widget? right;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const MgCard({
    super.key,
    this.title,
    this.sub,
    this.right,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.border, width: 0.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null || sub != null || right != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (title != null)
                              Text(
                                title!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppPalette.text,
                                ),
                              ),
                            if (sub != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  sub!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppPalette.textSub,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (right != null) right!,
                    ],
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// 圆环（conic-gradient + 内圈挖空）。
/// value / target 都可空；空时显示灰色环。
class RingProgress extends StatelessWidget {
  final double value;
  final double target;
  final String centerLabel;
  final String subLabel;
  final double size;

  const RingProgress({
    super.key,
    required this.value,
    required this.target,
    required this.centerLabel,
    required this.subLabel,
    this.size = 132,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = target > 0 ? value / target : 0.0;
    final pct = ratio.clamp(0.0, 1.2);
    final deg = (pct * 360).clamp(0.0, 360.0).toDouble();
    final isOver = ratio > 1.0;
    final ringColor = isOver ? AppPalette.danger : AppPalette.primary;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 圆环本体
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                startAngle: -1.5708, // -π/2, 12 点钟方向
                endAngle: 4.7124,     //  3π/2
                colors: [
                  ringColor,
                  ringColor,
                  AppPalette.surfaceMuted,
                  AppPalette.surfaceMuted,
                ],
                stops: [
                  0.0,
                  deg / 360.0,
                  deg / 360.0,
                  1.0,
                ],
                transform: GradientRotation(-1.5708),
              ),
            ),
          ),
          // 内圈挖空
          Container(
            width: size - 24,
            height: size - 24,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppPalette.background,
            ),
          ),
          // 中心文字
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerLabel,
                style: TextStyle(
                  fontSize: size / 5.5,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppPalette.textSub,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一条宏量进度条。
class MacroRow extends StatelessWidget {
  final String label;
  final double value;
  final double target;
  final Color color;
  const MacroRow({
    super.key,
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = target > 0 ? (value / target).clamp(0.0, 1.2) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppPalette.textSub,
                ),
              ),
              Text(
                '${_nf(value)} / ${_nf(target)} g',
                style: const TextStyle(
                  fontSize: 13,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: AppPalette.surfaceMuted,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class MacroBar extends StatelessWidget {
  final double pVal;
  final double pTarget;
  final double cVal;
  final double cTarget;
  final double fVal;
  final double fTarget;
  const MacroBar({
    super.key,
    required this.pVal,
    required this.pTarget,
    required this.cVal,
    required this.cTarget,
    required this.fVal,
    required this.fTarget,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MacroRow(label: '蛋白', value: pVal, target: pTarget,
            color: AppPalette.protein),
        MacroRow(label: '碳水', value: cVal, target: cTarget,
            color: AppPalette.carb),
        MacroRow(label: '脂肪', value: fVal, target: fTarget,
            color: AppPalette.fat),
      ],
    );
  }
}

/// Badge（文字 + 背景色圆角徽章）。
class MgBadge extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const MgBadge({
    super.key,
    required this.text,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

String _nf(double v) {
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}
