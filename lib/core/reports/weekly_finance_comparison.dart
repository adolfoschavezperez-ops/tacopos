import 'package:intl/intl.dart';

import 'finance_dashboard.dart';

const int weeklyFinanceComparisonWeeks = 4;

enum WeeklyFinanceDailyMetric { sales, income, orders }

enum WeeklyFinanceChartMetric { sales, income, profit, orders }

class WeeklyFinanceComparisonReport {
  const WeeklyFinanceComparisonReport({
    required this.generatedAt,
    required this.weeks,
    required this.samePeriodWeeks,
    required this.elapsedDayCount,
  });

  final DateTime generatedAt;
  final List<WeeklyFinanceWeekSummary> weeks;
  final List<WeeklyFinanceWeekSummary> samePeriodWeeks;
  final int elapsedDayCount;

  WeeklyFinanceWeekSummary? get currentWeek {
    for (final week in weeks) {
      if (week.isCurrent) return week;
    }
    return null;
  }

  WeeklyFinanceWeekSummary? bestBy(double Function(WeeklyFinanceMetrics) pick) {
    if (weeks.isEmpty) return null;
    return weeks.reduce((best, week) {
      final bestValue = pick(best.metrics);
      final weekValue = pick(week.metrics);
      if (weekValue > bestValue) return week;
      return best;
    });
  }
}

class WeeklyFinanceWeekSummary {
  const WeeklyFinanceWeekSummary({
    required this.label,
    required this.startDate,
    required this.endExclusive,
    required this.isCurrent,
    required this.isInProgress,
    required this.metrics,
    required this.dailyRows,
  });

  final String label;
  final DateTime startDate;
  final DateTime endExclusive;
  final bool isCurrent;
  final bool isInProgress;
  final WeeklyFinanceMetrics metrics;
  final List<WeeklyFinanceDaySummary> dailyRows;

  DateTime get endDate => endExclusive.subtract(const Duration(days: 1));
  String get startBusinessDate => _businessDate(startDate);
  String get endBusinessDate => _businessDate(endDate);
  String get periodLabel =>
      '${_displayDate(startDate)} - ${_displayDate(endDate)}';
}

class WeeklyFinanceDaySummary {
  const WeeklyFinanceDaySummary({
    required this.date,
    required this.weekdayIndex,
    required this.isFutureForCurrentWeek,
    required this.metrics,
  });

  final DateTime date;
  final int weekdayIndex;
  final bool isFutureForCurrentWeek;
  final WeeklyFinanceMetrics metrics;

  String get businessDate => _businessDate(date);
}

class WeeklyFinanceMetrics {
  const WeeklyFinanceMetrics({
    this.grossSales = 0,
    this.discounts = 0,
    this.netSales = 0,
    this.realIncome = 0,
    this.cashIncome = 0,
    this.cardIncome = 0,
    this.otherIncome = 0,
    this.shortages = 0,
    this.overages = 0,
    this.expenses = 0,
    this.orders = 0,
  });

  final double grossSales;
  final double discounts;
  final double netSales;
  final double realIncome;
  final double cashIncome;
  final double cardIncome;
  final double otherIncome;
  final double shortages;
  final double overages;
  final double expenses;
  final int orders;

  double get financialProfit => _money(realIncome - expenses);
  double get averageTicket => orders == 0 ? 0 : _money(netSales / orders);

  WeeklyFinanceMetrics operator +(WeeklyFinanceMetrics other) {
    return WeeklyFinanceMetrics(
      grossSales: _money(grossSales + other.grossSales),
      discounts: _money(discounts + other.discounts),
      netSales: _money(netSales + other.netSales),
      realIncome: _money(realIncome + other.realIncome),
      cashIncome: _money(cashIncome + other.cashIncome),
      cardIncome: _money(cardIncome + other.cardIncome),
      otherIncome: _money(otherIncome + other.otherIncome),
      shortages: _money(shortages + other.shortages),
      overages: _money(overages + other.overages),
      expenses: _money(expenses + other.expenses),
      orders: orders + other.orders,
    );
  }
}

class WeeklyFinanceChange {
  const WeeklyFinanceChange({
    required this.current,
    required this.previous,
    required this.delta,
    required this.percent,
  });

  final double current;
  final double previous;
  final double delta;
  final double? percent;

  bool get isPositive => delta > 0;
  bool get isNegative => delta < 0;
}

WeeklyFinanceComparisonReport buildWeeklyFinanceComparisonReport({
  required FinanceDashboardBundle bundle,
  required DateTime now,
}) {
  final currentMonday = mondayForDate(now);
  final today = DateTime(now.year, now.month, now.day);
  final elapsedDayCount = now.weekday.clamp(1, DateTime.daysPerWeek);
  final weeks = <WeeklyFinanceWeekSummary>[];
  final samePeriodWeeks = <WeeklyFinanceWeekSummary>[];

  for (var offset = weeklyFinanceComparisonWeeks - 1; offset >= 0; offset--) {
    final start = currentMonday.subtract(Duration(days: offset * 7));
    final endExclusive = start.add(const Duration(days: 7));
    final isCurrent = offset == 0;
    weeks.add(
      _buildWeekSummary(
        label: _labelForOffset(offset),
        startDate: start,
        endExclusive: endExclusive,
        today: today,
        isCurrent: isCurrent,
        dayLimit: DateTime.daysPerWeek,
        bundle: bundle,
      ),
    );
    samePeriodWeeks.add(
      _buildWeekSummary(
        label: _labelForOffset(offset),
        startDate: start,
        endExclusive: start.add(Duration(days: elapsedDayCount)),
        today: today,
        isCurrent: isCurrent,
        dayLimit: elapsedDayCount,
        bundle: bundle,
      ),
    );
  }

  return WeeklyFinanceComparisonReport(
    generatedAt: now,
    weeks: List.unmodifiable(weeks),
    samePeriodWeeks: List.unmodifiable(samePeriodWeeks),
    elapsedDayCount: elapsedDayCount,
  );
}

DateTime mondayForDate(DateTime value) {
  final day = DateTime(value.year, value.month, value.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

DateTime weeklyComparisonRangeStart(DateTime now) {
  return mondayForDate(
    now,
  ).subtract(const Duration(days: (weeklyFinanceComparisonWeeks - 1) * 7));
}

DateTime weeklyComparisonRangeEndExclusive(DateTime now) {
  return mondayForDate(now).add(const Duration(days: 7));
}

WeeklyFinanceChange weeklyFinanceChange({
  required double current,
  required double previous,
}) {
  final delta = _money(current - previous);
  if (previous.abs() < 0.005) {
    return WeeklyFinanceChange(
      current: _money(current),
      previous: _money(previous),
      delta: delta,
      percent: current.abs() < 0.005 ? 0 : null,
    );
  }
  return WeeklyFinanceChange(
    current: _money(current),
    previous: _money(previous),
    delta: delta,
    percent: _money((delta / previous) * 100),
  );
}

double weeklyChartValue(
  WeeklyFinanceWeekSummary week,
  WeeklyFinanceChartMetric metric,
) {
  return switch (metric) {
    WeeklyFinanceChartMetric.sales => week.metrics.netSales,
    WeeklyFinanceChartMetric.income => week.metrics.realIncome,
    WeeklyFinanceChartMetric.profit => week.metrics.financialProfit,
    WeeklyFinanceChartMetric.orders => week.metrics.orders.toDouble(),
  };
}

double weeklyDailyValue(
  WeeklyFinanceDaySummary day,
  WeeklyFinanceDailyMetric metric,
) {
  return switch (metric) {
    WeeklyFinanceDailyMetric.sales => day.metrics.netSales,
    WeeklyFinanceDailyMetric.income => day.metrics.realIncome,
    WeeklyFinanceDailyMetric.orders => day.metrics.orders.toDouble(),
  };
}

WeeklyFinanceWeekSummary _buildWeekSummary({
  required String label,
  required DateTime startDate,
  required DateTime endExclusive,
  required DateTime today,
  required bool isCurrent,
  required int dayLimit,
  required FinanceDashboardBundle bundle,
}) {
  final days = <WeeklyFinanceDaySummary>[];
  var total = const WeeklyFinanceMetrics();
  for (var dayIndex = 0; dayIndex < DateTime.daysPerWeek; dayIndex++) {
    final date = startDate.add(Duration(days: dayIndex));
    final isIncluded = dayIndex < dayLimit;
    final isFuture = isCurrent && date.isAfter(today);
    final metrics = isIncluded
        ? _metricsForBusinessDate(_businessDate(date), bundle)
        : const WeeklyFinanceMetrics();
    days.add(
      WeeklyFinanceDaySummary(
        date: date,
        weekdayIndex: dayIndex,
        isFutureForCurrentWeek: isFuture,
        metrics: metrics,
      ),
    );
    if (isIncluded) total += metrics;
  }

  return WeeklyFinanceWeekSummary(
    label: label,
    startDate: startDate,
    endExclusive: endExclusive,
    isCurrent: isCurrent,
    isInProgress: isCurrent,
    metrics: total,
    dailyRows: List.unmodifiable(days),
  );
}

WeeklyFinanceMetrics _metricsForBusinessDate(
  String businessDate,
  FinanceDashboardBundle bundle,
) {
  final sales = bundle.salesByDay.where(
    (row) => row.businessDate == businessDate,
  );
  final collections = bundle.collectionsByDay.where(
    (row) => row.businessDate == businessDate,
  );
  final expenses = bundle.approvedExpenses.where(
    (row) => row.businessDate == businessDate,
  );

  return WeeklyFinanceMetrics(
    grossSales: _money(
      sales.fold<double>(0, (sum, row) => sum + row.grossSales),
    ),
    discounts: _money(sales.fold<double>(0, (sum, row) => sum + row.discounts)),
    netSales: _money(sales.fold<double>(0, (sum, row) => sum + row.netSales)),
    realIncome: _money(
      collections.fold<double>(0, (sum, row) => sum + row.realCollected),
    ),
    cashIncome: _money(
      collections.fold<double>(0, (sum, row) => sum + row.cash),
    ),
    cardIncome: _money(
      collections.fold<double>(0, (sum, row) => sum + row.card),
    ),
    otherIncome: _money(
      collections.fold<double>(0, (sum, row) => sum + row.other),
    ),
    shortages: _money(
      collections.fold<double>(0, (sum, row) => sum + row.shortage),
    ),
    overages: _money(
      collections.fold<double>(0, (sum, row) => sum + row.overage),
    ),
    expenses: _money(expenses.fold<double>(0, (sum, row) => sum + row.amount)),
    orders: sales.fold<int>(0, (sum, row) => sum + row.documents),
  );
}

String _labelForOffset(int offset) {
  return switch (offset) {
    0 => 'Semana actual',
    1 => 'Semana anterior',
    2 => 'Hace 2 semanas',
    _ => 'Hace 3 semanas',
  };
}

String _businessDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

String _displayDate(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

double _money(num value) => (value * 100).roundToDouble() / 100;
