import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../models/product.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';
import 'employee_catalog_screen.dart';
import 'order_platform_catalog_screen.dart';
import 'product_catalog_screen.dart';
import 'table_catalog_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();
    final employee = AppSession.instance.employee;

    if (employee?.canViewAdmin != true) {
      return const BrandedScaffold(
        title: 'Socio / Admin',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para ver admin.',
        ),
      );
    }

    return BrandedScaffold(
      title: 'Socio / Admin',
      actions: [
        IconButton(
          tooltip: 'Mesas',
          onPressed: employee?.canManageTables == true
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TableCatalogScreen(),
                    ),
                  );
                }
              : null,
          icon: const Icon(Icons.table_restaurant),
        ),
        IconButton(
          tooltip: 'Plataformas',
          onPressed: employee?.canManagePlatforms == true
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OrderPlatformCatalogScreen(),
                    ),
                  );
                }
              : null,
          icon: const Icon(Icons.delivery_dining),
        ),
        IconButton(
          tooltip: 'Productos',
          onPressed: employee?.canManageProducts == true
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProductCatalogScreen(),
                    ),
                  );
                }
              : null,
          icon: const Icon(Icons.restaurant_menu),
        ),
        IconButton(
          tooltip: 'Empleados',
          onPressed: employee?.canManageEmployees == true
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EmployeeCatalogScreen(),
                    ),
                  );
                }
              : null,
          icon: const Icon(Icons.badge_outlined),
        ),
      ],
      body: StreamBuilder<List<PosOrder>>(
        stream: repository.watchAllOrders(),
        builder: (context, ordersSnapshot) {
          if (ordersSnapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudieron cargar ordenes',
              message: '${ordersSnapshot.error}',
            );
          }

          if (ordersSnapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando dashboard...');
          }

          final orders = ordersSnapshot.data ?? [];

          return StreamBuilder<List<Payment>>(
            stream: repository.watchPayments(),
            builder: (context, paymentsSnapshot) {
              if (paymentsSnapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudieron cargar pagos',
                  message: '${paymentsSnapshot.error}',
                );
              }

              final payments = _todayPayments(paymentsSnapshot.data ?? []);
              final baseSales = payments.fold<double>(
                0,
                (runningTotal, payment) => runningTotal + payment.baseAmount,
              );
              final cash = _baseByMethod(payments, 'cash');
              final cardBase = _baseByMethod(payments, 'card');
              final cardSurcharge = payments
                  .where((payment) => payment.method == 'card')
                  .fold<double>(
                    0,
                    (runningTotal, payment) =>
                        runningTotal + payment.surchargeAmount,
                  );
              final cardCharged = payments
                  .where((payment) => payment.method == 'card')
                  .fold<double>(
                    0,
                    (runningTotal, payment) =>
                        runningTotal + payment.chargedAmount,
                  );
              final employeeConsumption = _baseByMethod(
                payments,
                'employee_consumption',
              );
              final platformPaid = _baseByMethod(payments, 'platform_paid');
              final didiPaid = _platformTotal(payments, 'didi');
              final uberPaid = _platformTotal(payments, 'uber');
              final rappiPaid = _platformTotal(payments, 'rappi');
              final realCharged = payments.fold<double>(
                0,
                (runningTotal, payment) => runningTotal + payment.chargedAmount,
              );
              final paidOrders = orders
                  .where(
                    (order) => _isToday(order.paidAt) && order.status == 'paid',
                  )
                  .length;
              final openOrders = orders
                  .where((order) => order.status != 'paid')
                  .length;
              final partialOrders = orders
                  .where((order) => order.paymentStatus == 'partial')
                  .length;

              return StreamBuilder<List<Product>>(
                stream: repository.watchProducts(),
                builder: (context, productsSnapshot) {
                  if (productsSnapshot.hasError) {
                    return EmptyState(
                      icon: Icons.error_outline,
                      title: 'No se pudieron cargar productos',
                      message: '${productsSnapshot.error}',
                    );
                  }

                  final products = productsSnapshot.data ?? [];
                  final activeProducts = products
                      .where((product) => product.active)
                      .length;

                  return ListView(
                    padding: const EdgeInsets.all(22),
                    children: [
                      const SectionHeader(
                        title: 'Dashboard',
                        subtitle: 'Operacion en tiempo real.',
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 900 ? 4 : 2;
                          return GridView.count(
                            crossAxisCount: columns,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: constraints.maxWidth >= 900
                                ? 1.6
                                : 1.25,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _MetricCard(
                                title: 'Ventas del dia',
                                icon: Icons.payments,
                                money: baseSales,
                                accent: BrandColors.accentYellow,
                              ),
                              _MetricCard(
                                title: 'Efectivo',
                                icon: Icons.attach_money,
                                money: cash,
                                accent: BrandColors.accentOrange,
                              ),
                              _MetricCard(
                                title: 'Tarjeta base',
                                icon: Icons.credit_card,
                                money: cardBase,
                                accent: BrandColors.success,
                              ),
                              _MetricCard(
                                title: 'Comision tarjeta',
                                icon: Icons.percent,
                                money: cardSurcharge,
                                accent: BrandColors.info,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 900 ? 4 : 2;
                          return GridView.count(
                            crossAxisCount: columns,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: constraints.maxWidth >= 900
                                ? 1.8
                                : 1.35,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _MetricCard(
                                title: 'Total tarjeta',
                                icon: Icons.credit_score,
                                money: cardCharged,
                                accent: BrandColors.accentYellow,
                              ),
                              _MetricCard(
                                title: 'Consumo empleado',
                                icon: Icons.badge_outlined,
                                money: employeeConsumption,
                                accent: BrandColors.info,
                              ),
                              _MetricCard(
                                title: 'Pagado plataforma',
                                icon: Icons.delivery_dining,
                                money: platformPaid,
                                accent: BrandColors.accentOrange,
                              ),
                              _MetricCard(
                                title: 'Ordenes pagadas',
                                icon: Icons.check_circle_outline,
                                value: '$paidOrders',
                                accent: BrandColors.success,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 900 ? 4 : 2;
                          return GridView.count(
                            crossAxisCount: columns,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: constraints.maxWidth >= 900
                                ? 1.8
                                : 1.35,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _MetricCard(
                                title: 'Total plataforma',
                                icon: Icons.delivery_dining,
                                money: platformPaid,
                                accent: BrandColors.accentYellow,
                              ),
                              _MetricCard(
                                title: 'DiDi',
                                icon: Icons.two_wheeler,
                                money: didiPaid,
                                accent: BrandColors.info,
                              ),
                              _MetricCard(
                                title: 'Uber',
                                icon: Icons.local_taxi,
                                money: uberPaid,
                                accent: BrandColors.success,
                              ),
                              _MetricCard(
                                title: 'Rappi',
                                icon: Icons.shopping_bag_outlined,
                                money: rappiPaid,
                                accent: BrandColors.accentOrange,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 900 ? 2 : 2;
                          return GridView.count(
                            crossAxisCount: columns,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: constraints.maxWidth >= 900
                                ? 2.4
                                : 1.45,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _MetricCard(
                                title: 'Total cobrado real',
                                icon: Icons.point_of_sale,
                                money: realCharged,
                                accent: BrandColors.success,
                              ),
                              _MetricCard(
                                title: 'Ordenes abiertas',
                                icon: Icons.receipt_long,
                                value: '$openOrders',
                                accent: BrandColors.accentOrange,
                              ),
                              _MetricCard(
                                title: 'Ordenes parciales',
                                icon: Icons.pie_chart_outline,
                                value: '$partialOrders',
                                accent: BrandColors.info,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      if (employee?.canManageTables == true) ...[
                        _AdminLinkPanel(
                          icon: Icons.table_restaurant,
                          iconColor: BrandColors.accentOrange,
                          title: 'Catalogo de mesas',
                          subtitle:
                              'Ver, agregar, editar y activar mesas fisicas y la entrada Para llevar.',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TableCatalogScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (employee?.canManagePlatforms == true) ...[
                        _AdminLinkPanel(
                          icon: Icons.delivery_dining,
                          iconColor: BrandColors.info,
                          title: 'Catalogo de plataformas',
                          subtitle:
                              'Configura canales para pedidos para llevar: En persona, DiDi, Uber o Rappi.',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const OrderPlatformCatalogScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (employee?.canManageProducts == true) ...[
                        GlassPanel(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: BrandColors.glassHighlight,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.restaurant_menu,
                                  color: BrandColors.accentYellow,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Catalogo de productos',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Ver, agregar, editar y activar productos del menu. $activeProducts activos.',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: BrandColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              GlassButton(
                                icon: Icons.arrow_forward,
                                label: 'Abrir',
                                prominent: true,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ProductCatalogScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (employee?.canManageEmployees == true) ...[
                        GlassPanel(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: BrandColors.glassHighlight,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.badge_outlined,
                                  color: BrandColors.info,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Catalogo de empleados',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Ver, agregar, editar y activar empleados para consumo empleado.',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: BrandColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              GlassButton(
                                icon: Icons.arrow_forward,
                                label: 'Abrir',
                                prominent: true,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const EmployeeCatalogScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      const SectionHeader(
                        title: 'Ordenes recientes',
                        subtitle: 'Ultimos movimientos registrados.',
                      ),
                      const SizedBox(height: 12),
                      if (orders.isEmpty)
                        const GlassPanel(
                          child: Text(
                            'Aun no hay ordenes. Abre una mesa desde Mesero / Caja.',
                            style: TextStyle(color: BrandColors.textMuted),
                          ),
                        )
                      else
                        ...orders
                            .take(8)
                            .map((order) => _RecentOrderTile(order: order)),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  List<Payment> _todayPayments(List<Payment> payments) {
    return payments.where((payment) => _isToday(payment.createdAt)).toList();
  }

  double _baseByMethod(List<Payment> payments, String method) {
    return payments
        .where((payment) => payment.method == method)
        .fold<double>(
          0,
          (runningTotal, payment) => runningTotal + payment.baseAmount,
        );
  }

  double _platformTotal(List<Payment> payments, String platformId) {
    return payments
        .where(
          (payment) =>
              payment.method == 'platform_paid' &&
              payment.platformId == platformId,
        )
        .fold<double>(
          0,
          (runningTotal, payment) => runningTotal + payment.baseAmount,
        );
  }

  bool _isToday(DateTime? date) {
    if (date == null) {
      return false;
    }

    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

class _AdminLinkPanel extends StatelessWidget {
  const _AdminLinkPanel({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: BrandColors.glassHighlight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: BrandColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GlassButton(
            icon: Icons.arrow_forward,
            label: 'Abrir',
            prominent: true,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.icon,
    required this.accent,
    this.value,
    this.money,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final String? value;
  final double? money;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 28),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (money != null)
            MoneyText(
              value: money!,
              style: TextStyle(
                color: accent,
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            )
          else
            Text(
              value ?? '0',
              style: TextStyle(
                color: accent,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentOrderTile extends StatelessWidget {
  const _RecentOrderTile({required this.order});

  final PosOrder order;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: EdgeInsets.zero,
        accent: BrandColors.accentOrange,
        child: ListTile(
          leading: const Icon(
            Icons.receipt_long,
            color: BrandColors.accentOrange,
          ),
          title: Text(
            order.displayName,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text('${order.status} | ${order.kitchenStatus}'),
          trailing: MoneyText(
            value: order.total,
            style: const TextStyle(
              color: BrandColors.accentYellow,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
