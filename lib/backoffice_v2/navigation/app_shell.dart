import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../auth/backoffice_session.dart';
import '../auth/widgets/tacopos_brand_mark.dart';
import '../core/design/design_tokens.dart';
import '../widgets/environment_banner.dart';
import 'backoffice_route.dart';

class _NavGroup {
  const _NavGroup(this.title, this.items);

  final String title;
  final List<_NavItem> items;
}

class _NavItem {
  const _NavItem({
    required this.section,
    required this.icon,
    required this.activeIcon,
    this.available = false,
  });

  final BackofficeSection section;
  final IconData icon;
  final IconData activeIcon;
  final bool available;
}

const List<_NavGroup> _navGroups = [
  _NavGroup('GENERAL', [
    _NavItem(
      section: BackofficeSection.dashboard,
      icon: Icons.space_dashboard_outlined,
      activeIcon: Icons.space_dashboard_rounded,
      available: true,
    ),
    _NavItem(
      section: BackofficeSection.sales,
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
      available: true,
    ),
  ]),
  _NavGroup('OPERACIÓN', [
    _NavItem(
      section: BackofficeSection.cash,
      icon: Icons.point_of_sale_outlined,
      activeIcon: Icons.point_of_sale_rounded,
      available: true,
    ),
    _NavItem(
      section: BackofficeSection.authorizations,
      icon: Icons.verified_outlined,
      activeIcon: Icons.verified_rounded,
      available: true,
    ),
    _NavItem(
      section: BackofficeSection.purchases,
      icon: Icons.shopping_bag_outlined,
      activeIcon: Icons.shopping_bag_rounded,
      available: true,
    ),
    _NavItem(
      section: BackofficeSection.inventory,
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2_rounded,
      available: true,
    ),
    _NavItem(
      section: BackofficeSection.finance,
      icon: Icons.account_balance_outlined,
      activeIcon: Icons.account_balance_rounded,
      available: true,
    ),
    _NavItem(
      section: BackofficeSection.reports,
      icon: Icons.analytics_outlined,
      activeIcon: Icons.analytics_rounded,
      available: true,
    ),
  ]),
  _NavGroup('ADMINISTRACIÓN', [
    _NavItem(
      section: BackofficeSection.employees,
      icon: Icons.badge_outlined,
      activeIcon: Icons.badge_rounded,
    ),
    _NavItem(
      section: BackofficeSection.audit,
      icon: Icons.verified_user_outlined,
      activeIcon: Icons.verified_user_rounded,
      available: true,
    ),
    _NavItem(
      section: BackofficeSection.settings,
      icon: Icons.tune_outlined,
      activeIcon: Icons.tune_rounded,
    ),
  ]),
];

class BackofficeAppShell extends StatefulWidget {
  const BackofficeAppShell({
    super.key,
    required this.session,
    required this.currentRoute,
    required this.onNavigate,
    required this.onSignOut,
    required this.child,
  });

  final BackofficeSession session;
  final BackofficeRoute currentRoute;
  final ValueChanged<BackofficeRoute> onNavigate;
  final VoidCallback onSignOut;
  final Widget child;

  @override
  State<BackofficeAppShell> createState() => _BackofficeAppShellState();
}

class _BackofficeAppShellState extends State<BackofficeAppShell> {
  bool _collapsed = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _openMobileMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _MobileMoreSheet(
        session: widget.session,
        currentSection: widget.currentRoute.section,
        onSelectSection: (section) {
          Navigator.of(ctx).pop();
          widget.onNavigate(BackofficeRoute.section(section));
        },
        onSignOut: () {
          Navigator.of(ctx).pop();
          widget.onSignOut();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final isTablet = width >= 720 && width < 1024;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: tokens.canvas,
      drawer: isTablet
          ? Drawer(
              width: BackofficeSpacing.sidebarWidth,
              backgroundColor: tokens.sidebarBg,
              child: SafeArea(
                child: _DarkGraphiteSidebar(
                  session: widget.session,
                  currentSection: widget.currentRoute.section,
                  collapsed: false,
                  onSelectSection: (section) {
                    Navigator.of(context).pop();
                    widget.onNavigate(BackofficeRoute.section(section));
                  },
                ),
              ),
            )
          : null,
      bottomNavigationBar: isMobile
          ? _MobileBottomNav(
              currentSection: widget.currentRoute.section,
              onSelectSection: (s) =>
                  widget.onNavigate(BackofficeRoute.section(s)),
              onOpenMore: _openMobileMoreSheet,
            )
          : null,
      body: SafeArea(
        top: true,
        bottom: !isMobile,
        child: Row(
          children: [
            if (!isMobile && !isTablet)
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: _collapsed
                    ? BackofficeSpacing.sidebarCollapsedWidth
                    : BackofficeSpacing.sidebarWidth,
                decoration: BoxDecoration(
                  color: tokens.sidebarBg,
                  border: Border(right: BorderSide(color: tokens.sidebarBorder)),
                ),
                child: _DarkGraphiteSidebar(
                  session: widget.session,
                  currentSection: widget.currentRoute.section,
                  collapsed: _collapsed,
                  onToggleCollapse: () =>
                      setState(() => _collapsed = !_collapsed),
                  onSelectSection: (section) =>
                      widget.onNavigate(BackofficeRoute.section(section)),
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    session: widget.session,
                    currentRoute: widget.currentRoute,
                    isMobile: isMobile,
                    isTablet: isTablet,
                    onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
                    onNavigateBackToSales: widget.currentRoute.saleId != null
                        ? () => widget.onNavigate(
                            const BackofficeRoute.section(
                              BackofficeSection.sales,
                            ),
                          )
                        : null,
                    onSignOut: widget.onSignOut,
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: widget.child,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkGraphiteSidebar extends StatelessWidget {
  const _DarkGraphiteSidebar({
    required this.session,
    required this.currentSection,
    required this.collapsed,
    required this.onSelectSection,
    this.onToggleCollapse,
  });

  final BackofficeSession session;
  final BackofficeSection currentSection;
  final bool collapsed;
  final ValueChanged<BackofficeSection> onSelectSection;
  final VoidCallback? onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);

    return Container(
      color: tokens.sidebarBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: BackofficeSpacing.topBarHeight,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 14 : 18),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.sidebarBorder)),
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                TacoPosBrandMark(
                  size: 30,
                  showWordmark: !collapsed,
                  lightText: true,
                ),
                if (!collapsed && onToggleCollapse != null) ...[
                  const Spacer(),
                  IconButton(
                    onPressed: onToggleCollapse,
                    tooltip: 'Colapsar menú',
                    icon: Icon(
                      Icons.keyboard_double_arrow_left_rounded,
                      size: 17,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
          if (collapsed && onToggleCollapse != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: IconButton(
                onPressed: onToggleCollapse,
                tooltip: 'Expandir menú',
                icon: Icon(
                  Icons.keyboard_double_arrow_right_rounded,
                  size: 17,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              children: _navGroups.map((group) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!collapsed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                        child: Text(
                          group.title,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: Colors.white.withValues(alpha: 0.36),
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 8),
                    ...group.items.map((item) {
                      final selected = currentSection == item.section;
                      final muted = !item.available && !selected;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Tooltip(
                          message: collapsed
                              ? item.section.label
                              : (item.available
                                    ? ''
                                    : 'Disponible próximamente'),
                          child: InkWell(
                            onTap: () => onSelectSection(item.section),
                            borderRadius: BorderRadius.circular(
                              BackofficeSpacing.radiusMd,
                            ),
                            hoverColor: Colors.white.withValues(alpha: 0.05),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              padding: EdgeInsets.symmetric(
                                horizontal: collapsed ? 0 : 10,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFF97316)
                                        .withValues(alpha: 0.14)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  BackofficeSpacing.radiusMd,
                                ),
                                border: selected
                                    ? Border.all(
                                        color: const Color(0xFFF97316)
                                            .withValues(alpha: 0.28),
                                      )
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: collapsed
                                    ? MainAxisAlignment.center
                                    : MainAxisAlignment.start,
                                children: [
                                  if (selected && !collapsed)
                                    Container(
                                      width: 3,
                                      height: 16,
                                      margin: const EdgeInsets.only(right: 9),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF97316),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    ),
                                  Icon(
                                    selected ? item.activeIcon : item.icon,
                                    size: 18,
                                    color: selected
                                        ? const Color(0xFFF97316)
                                        : Colors.white.withValues(
                                            alpha: muted ? 0.35 : 0.68,
                                          ),
                                  ),
                                  if (!collapsed) ...[
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        item.section.label,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          color: selected
                                              ? const Color(0xFFFAFAF9)
                                              : Colors.white.withValues(
                                                  alpha: muted ? 0.42 : 0.78,
                                                ),
                                        ),
                                      ),
                                    ),
                                    if (!item.available)
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.18,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
          ),
          if (!collapsed)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.sidebarSurface,
                borderRadius: BorderRadius.circular(BackofficeSpacing.radiusMd),
                border: Border.all(color: tokens.sidebarBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: tokens.sidebarBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tokens.sidebarBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      AppConstants.logoAsset,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.storefront_rounded,
                        size: 16,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.restaurantName,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFAFAF9),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${session.branches.length} sucursales activas',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.48),
                          ),
                        ),
                      ],
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

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.session,
    required this.currentRoute,
    required this.isMobile,
    required this.isTablet,
    required this.onOpenDrawer,
    required this.onSignOut,
    this.onNavigateBackToSales,
  });

  final BackofficeSession session;
  final BackofficeRoute currentRoute;
  final bool isMobile;
  final bool isTablet;
  final VoidCallback onOpenDrawer;
  final VoidCallback onSignOut;
  final VoidCallback? onNavigateBackToSales;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final employeeName = session.employee?.name ?? 'Administrador';
    final initials = employeeName
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((e) => e.isEmpty ? '' : e[0].toUpperCase())
        .join();

    return Container(
      height: BackofficeSpacing.topBarHeight,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 20),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          if (isTablet) ...[
            IconButton(
              onPressed: onOpenDrawer,
              icon: const Icon(Icons.menu_rounded, size: 20),
              tooltip: 'Menú',
            ),
            const SizedBox(width: 6),
          ],
          if (isMobile) ...[
            const TacoPosBrandMark(size: 26, showWordmark: false),
            const SizedBox(width: 10),
          ],
          if (onNavigateBackToSales != null) ...[
            IconButton(
              onPressed: onNavigateBackToSales,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              tooltip: 'Volver a Ventas',
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    currentRoute.saleId != null
                        ? 'Ventas  /  Detalle de orden'
                        : currentRoute.section.label,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isMobile) ...[
                  const SizedBox(width: 10),
                  EnvironmentIndicatorPill(config: session.config),
                ],
              ],
            ),
          ),
          _BranchDropdown(session: session, compact: isMobile),
          const SizedBox(width: 8),
          IconButton(
            onPressed: session.toggleThemeMode,
            tooltip: session.isDarkMode ? 'Modo claro' : 'Modo oscuro',
            icon: Icon(
              session.isDarkMode
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              size: 18,
              color: tokens.textSecondary,
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              tooltip: 'Cuenta',
              offset: const Offset(0, 44),
              onSelected: (value) {
                if (value == 'signout') onSignOut();
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employeeName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.textPrimary,
                        ),
                      ),
                      Text(
                        session.restaurantName,
                        style: TextStyle(fontSize: 11, color: tokens.textMuted),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'signout',
                  child: Row(
                    children: [
                      Icon(Icons.logout_rounded, size: 16),
                      SizedBox(width: 8),
                      Text('Cerrar sesión'),
                    ],
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: tokens.surfaceSubtle,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tokens.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: tokens.brandAccentSoft,
                      child: Text(
                        initials.isEmpty ? 'A' : initials,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: tokens.brandAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      employeeName,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: tokens.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BranchDropdown extends StatelessWidget {
  const _BranchDropdown({required this.session, required this.compact});

  final BackofficeSession session;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final branches = session.branches;

    return Container(
      height: 34,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 11),
      decoration: BoxDecoration(
        color: tokens.surfaceSubtle,
        borderRadius: BorderRadius.circular(BackofficeSpacing.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: session.selectedBranchId,
          isDense: true,
          dropdownColor: tokens.surface,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 15,
            color: tokens.textMuted,
          ),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: tokens.textPrimary,
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(compact ? 'Todas' : 'Todas las sucursales'),
            ),
            ...branches.map(
              (b) => DropdownMenuItem<String?>(value: b.id, child: Text(b.name)),
            ),
          ],
          onChanged: session.selectBranch,
        ),
      ),
    );
  }
}

class _MobileBottomNav extends StatelessWidget {
  const _MobileBottomNav({
    required this.currentSection,
    required this.onSelectSection,
    required this.onOpenMore,
  });

  final BackofficeSection currentSection;
  final ValueChanged<BackofficeSection> onSelectSection;
  final VoidCallback onOpenMore;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final isDash = currentSection == BackofficeSection.dashboard;
    final isSales = currentSection == BackofficeSection.sales;
    final isMore = !isDash && !isSales;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _BottomNavTab(
                icon: isDash
                    ? Icons.space_dashboard_rounded
                    : Icons.space_dashboard_outlined,
                label: 'Dashboard',
                selected: isDash,
                onTap: () => onSelectSection(BackofficeSection.dashboard),
              ),
              _BottomNavTab(
                icon: isSales
                    ? Icons.receipt_long_rounded
                    : Icons.receipt_long_outlined,
                label: 'Ventas',
                selected: isSales,
                onTap: () => onSelectSection(BackofficeSection.sales),
              ),
              _BottomNavTab(
                icon: Icons.grid_view_rounded,
                label: 'Módulos',
                selected: isMore,
                onTap: onOpenMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavTab extends StatelessWidget {
  const _BottomNavTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final color = selected ? tokens.brandAccent : tokens.textMuted;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 21, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileMoreSheet extends StatelessWidget {
  const _MobileMoreSheet({
    required this.session,
    required this.currentSection,
    required this.onSelectSection,
    required this.onSignOut,
  });

  final BackofficeSession session;
  final BackofficeSection currentSection;
  final ValueChanged<BackofficeSection> onSelectSection;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);

    return Container(
      decoration: BoxDecoration(
        color: tokens.sidebarBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: tokens.sidebarBorder),
      ),
      child: SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.90,
          builder: (context, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const TacoPosBrandMark(size: 28, showWordmark: true),
                    const Spacer(),
                    EnvironmentIndicatorPill(config: session.config),
                  ],
                ),
                const SizedBox(height: 16),
                ..._navGroups.map((group) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
                        child: Text(
                          group.title,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.7,
                            color: Colors.white.withValues(alpha: 0.40),
                          ),
                        ),
                      ),
                      ...group.items.map((item) {
                        final selected = currentSection == item.section;
                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          tileColor: selected
                              ? const Color(0xFFF97316).withValues(alpha: 0.14)
                              : null,
                          leading: Icon(
                            selected ? item.activeIcon : item.icon,
                            size: 19,
                            color: selected
                                ? const Color(0xFFF97316)
                                : Colors.white.withValues(
                                    alpha: item.available ? 0.78 : 0.38,
                                  ),
                          ),
                          title: Text(
                            item.section.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: selected
                                  ? const Color(0xFFFAFAF9)
                                  : Colors.white.withValues(
                                      alpha: item.available ? 0.85 : 0.45,
                                    ),
                            ),
                          ),
                          onTap: () => onSelectSection(item.section),
                        );
                      }),
                    ],
                  );
                }),
                const SizedBox(height: 16),
                Divider(color: tokens.sidebarBorder),
                const SizedBox(height: 8),
                ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.logout_rounded,
                    size: 19,
                    color: Color(0xFFF87171),
                  ),
                  title: const Text(
                    'Cerrar sesión',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF87171),
                    ),
                  ),
                  onTap: onSignOut,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
