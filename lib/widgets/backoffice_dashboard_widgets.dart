import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';

enum DashboardChartType { verticalBars, horizontalBars, donut }

class DashboardChartDatum {
  const DashboardChartDatum({
    required this.label,
    required this.value,
    required this.displayValue,
  });

  final String label;
  final double value;
  final String displayValue;
}

class DashboardSectionPanel extends StatelessWidget {
  const DashboardSectionPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _ExecutiveSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: BrandColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class ExecutiveDashboardHeader extends StatelessWidget {
  const ExecutiveDashboardHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.dateLabel,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onToday,
    required this.onWeek,
    required this.onMonth,
  });

  final String title;
  final String subtitle;
  final String dateLabel;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onToday;
  final VoidCallback onWeek;
  final VoidCallback onMonth;

  @override
  Widget build(BuildContext context) {
    return _ExecutiveSurface(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Backoffice ejecutivo',
                style: TextStyle(
                  color: BrandColors.accentYellow,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                title,
                style: TextStyle(
                  fontSize: compact ? 24 : 30,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                  color: BrandColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          );
          final filters = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              _DatePill(icon: Icons.event_outlined, label: dateLabel),
              _FilterButton(label: 'Inicial', onTap: onPickStart),
              _FilterButton(label: 'Final', onTap: onPickEnd),
              _FilterButton(label: 'Hoy', onTap: onToday, prominent: true),
              _FilterButton(label: 'Semana', onTap: onWeek),
              _FilterButton(label: 'Mes', onTap: onMonth),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [copy, const SizedBox(height: 12), filters],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: copy),
              const SizedBox(width: 24),
              Flexible(child: filters),
            ],
          );
        },
      ),
    );
  }
}

class ExecutiveKpiCard extends StatelessWidget {
  const ExecutiveKpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    this.accent = BrandColors.accentYellow,
  });

  final String title;
  final String value;
  final String detail;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _ExecutiveSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBadge(icon: icon, color: accent),
              const Spacer(),
              Container(
                width: 52,
                height: 6,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BrandColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class SecondaryMetricCard extends StatelessWidget {
  const SecondaryMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _ExecutiveSurface(
      padding: const EdgeInsets.all(14),
      compact: true,
      child: Row(
        children: [
          _IconBadge(icon: icon, color: BrandColors.accentOrange, small: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: BrandColors.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AlertPanel extends StatelessWidget {
  const AlertPanel({super.key, required this.alerts});

  final List<String> alerts;

  @override
  Widget build(BuildContext context) {
    final hasAlerts = alerts.any((alert) => !alert.startsWith('Sin alertas'));
    return DashboardSectionPanel(
      title: 'Estado operativo',
      subtitle: 'Alertas criticas y pendientes abiertos en este momento.',
      trailing: _StatusDot(active: hasAlerts),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: alerts
            .map(
              (alert) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: hasAlerts
                      ? BrandColors.accentYellow.withValues(alpha: 0.10)
                      : BrandColors.success.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasAlerts
                        ? BrandColors.accentYellow.withValues(alpha: 0.24)
                        : BrandColors.success.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasAlerts
                          ? Icons.warning_amber_outlined
                          : Icons.check_circle_outline,
                      size: 18,
                      color: hasAlerts
                          ? BrandColors.accentYellow
                          : BrandColors.success,
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: Text(alert)),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class InsightCard extends StatelessWidget {
  const InsightCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _ExecutiveSurface(
      padding: const EdgeInsets.all(16),
      compact: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBadge(icon: icon, color: BrandColors.info, small: true),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: BrandColors.textMuted),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: BrandColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class ChartPanel extends StatelessWidget {
  const ChartPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.data,
    required this.type,
    this.height = 230,
  });

  final String title;
  final String subtitle;
  final List<DashboardChartDatum> data;
  final DashboardChartType type;
  final double height;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionPanel(
      title: title,
      subtitle: subtitle,
      child: SizedBox(
        height: height,
        child: data.isEmpty
            ? const EmptyChartState()
            : switch (type) {
                DashboardChartType.verticalBars => _VerticalBars(data: data),
                DashboardChartType.horizontalBars => _HorizontalBars(
                  data: data,
                ),
                DashboardChartType.donut => _DonutChart(data: data),
              },
      ),
    );
  }
}

class EmptyChartState extends StatelessWidget {
  const EmptyChartState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Text(
          'Sin datos para graficar',
          style: TextStyle(color: BrandColors.textMuted),
        ),
      ),
    );
  }
}

class _VerticalBars extends StatelessWidget {
  const _VerticalBars({required this.data});

  final List<DashboardChartDatum> data;

  @override
  Widget build(BuildContext context) {
    final maxValue = _maxValue(data);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: data.take(12).map((item) {
        final ratio = maxValue <= 0 ? 0.0 : item.value / maxValue;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  item.displayValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: BrandColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: ratio.clamp(0.04, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              BrandColors.accentOrange.withValues(alpha: 0.70),
                              BrandColors.accentYellow,
                            ],
                          ),
                        ),
                        child: const SizedBox(width: double.infinity),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _HorizontalBars extends StatelessWidget {
  const _HorizontalBars({required this.data});

  final List<DashboardChartDatum> data;

  @override
  Widget build(BuildContext context) {
    final maxValue = _maxValue(data);
    return Column(
      children: data.take(7).map((item) {
        final ratio = maxValue <= 0 ? 0.0 : item.value / maxValue;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      item.displayValue,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 9,
                    backgroundColor: Colors.white.withValues(alpha: 0.07),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      BrandColors.accentYellow,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.data});

  final List<DashboardChartDatum> data;

  @override
  Widget build(BuildContext context) {
    final visible = data.where((item) => item.value > 0).take(6).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        final chart = CustomPaint(
          painter: _DonutPainter(visible),
          child: const SizedBox.square(dimension: 150),
        );
        final legend = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: visible.asMap().entries.map((entry) {
            final color = _chartColor(entry.key);
            final item = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.displayValue,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            );
          }).toList(),
        );
        if (compact) {
          return Column(
            children: [
              Expanded(child: Center(child: chart)),
              const SizedBox(height: 8),
              Expanded(child: legend),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: Center(child: chart)),
            const SizedBox(width: 18),
            Expanded(child: legend),
          ],
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.data);

  final List<DashboardChartDatum> data;

  @override
  void paint(Canvas canvas, Size size) {
    final total = data.fold<double>(0, (sum, item) => sum + item.value);
    final rect = Offset.zero & size;
    final stroke = math.max(18.0, size.shortestSide * 0.15);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    paint.color = Colors.white.withValues(alpha: 0.08);
    canvas.drawArc(rect.deflate(stroke / 2), 0, math.pi * 2, false, paint);

    if (total <= 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < data.length; i++) {
      final sweep = (data[i].value / total) * math.pi * 2;
      paint.color = _chartColor(i);
      canvas.drawArc(rect.deflate(stroke / 2), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}

class _ExecutiveSurface extends StatelessWidget {
  const _ExecutiveSurface({
    required this.child,
    required this.padding,
    this.compact = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: BrandColors.surfaceHigh.withValues(alpha: compact ? 0.44 : 0.58),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: BrandColors.accentYellow.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: BrandColors.accentYellow),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.onTap,
    this.prominent = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final color = prominent ? BrandColors.accentYellow : Colors.white;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(
          color: color.withValues(alpha: prominent ? 0.55 : 0.16),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.color,
    this.small = false,
  });

  final IconData icon;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 34.0 : 42.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, size: small ? 18 : 22, color: color),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? BrandColors.accentYellow : BrandColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(active ? 'Atencion' : 'Estable'),
        ],
      ),
    );
  }
}

double _maxValue(List<DashboardChartDatum> data) {
  return data.fold<double>(
    0,
    (max, item) => item.value > max ? item.value : max,
  );
}

Color _chartColor(int index) {
  const colors = [
    BrandColors.accentYellow,
    BrandColors.accentOrange,
    BrandColors.info,
    BrandColors.success,
    Color(0xFFFF8A7A),
    Color(0xFFBCA7FF),
  ];
  return colors[index % colors.length];
}
