import 'package:flutter/material.dart';

import '../auth/backoffice_session.dart';
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
    this.readyInPhase2 = false,
  });

  final BackofficeSection section;
  final IconData icon;
  final bool readyInPhase2;
}

const List<_NavGroup> _navGroups = [
  _NavGroup('GENERAL', [
    _NavItem(
      section: BackofficeSection.dashboard,
      icon: Icons.space_dashboard_outlined,
      readyInPhase2: true,
    ),
    _NavItem(
      section: BackofficeSection.sales,
      icon: Icons.receipt_long_outlined,
      readyInPhase2: true,
    ),
  ]),
  _NavGroup('OPERACIÓN Y FINANZAS', [
    _NavItem(
      section: BackofficeSection.cash,
      icon: Icons.point_of_sale_outlined,
    ),
    _NavItem(
      section: BackofficeSection.purchases,
      icon: Icons.shopping_bag_outlined,
    ),
    _NavItem(
      section: BackofficeSection.inventory,
      icon: Icons.inventory_2_outlined,
    ),
    _NavItem(
      section: BackofficeSection.finance,
      icon: Icons.account_balance_outlined,
    ),
    _NavItem(
      section: BackofficeSection.reports,
      icon: Icons.analytics_outlined,
    ),
  ]),
  _NavGroup('ADMINISTRACIÓN', [
    _NavItem(
      section: BackofficeSection.employees,
      icon: Icons.badge_outlined,
    ),
    _NavItem(
      section: BackofficeSection.audit,
      icon: Icons.verified_user_outlined,
    ),
    _NavItem(
      section: BackofficeSection.settings,
      icon: Icons.tune_outlined,
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

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 920;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: tokens.canvas,
      drawer: isCompact
          ? Drawer(
              width: BackofficeSpacing.sidebarWidth,
              backgroundColor: tokens.sidebarBg,
              child: SafeArea(
                child: _SidebarContent(
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
      body: Row(
        children: [
          if (!isCompact)
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: _collapsed
                  ? BackofficeSpacing.sidebarCollapsedWidth
                  : BackofficeSpacing.sidebarWidth,
              decoration: BoxDecoration(
                color: tokens.sidebarBg,
                border: Border(right: BorderSide(color: tokens.border)),
              ),
              child: _SidebarContent(
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
                  isCompact: isCompact,
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
    );
  }
}

class _SidebarContent extends StatelessWidget {
  const _SidebarContent({
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: BackofficeSpacing.topBarHeight,
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 12 : 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tokens.brandAccent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: Text(
                    'T',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: tokens.brandOnAccent,
                    ),
                  ),
                ),
              ),
              if (!collapsed) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TacoPOS',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        'Backoffice 2.0',
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.textMuted,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (onToggleCollapse != null && !collapsed)
                IconButton(
                  onPressed: onToggleCollapse,
                  tooltip: 'Colapsar menú',
                  icon: Icon(
                    Icons.keyboard_double_arrow_left,
                    size: 16,
                    color: tokens.textMuted,
                  ),
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        if (collapsed && onToggleCollapse != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: IconButton(
              onPressed: onToggleCollapse,
              tooltip: 'Expandir menú',
              icon: Icon(
                Icons.keyboard_double_arrow_right,
                size: 16,
                color: tokens.textMuted,
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
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                      child: Text(
                        group.title,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                          color: tokens.textMuted,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 6),
                  ...group.items.map((item) {
                    final selected = currentSection == item.section;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Tooltip(
                        message: collapsed ? item.section.label : '',
                        child: InkWell(
                          onTap: () => onSelectSection(item.section),
                          borderRadius: BorderRadius.circular(
                            BackofficeSpacing.radiusMd,
                          ),
                          hoverColor: tokens.surfaceHover,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: collapsed ? 0 : 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? tokens.brandAccentSoft
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                BackofficeSpacing.radiusMd,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: collapsed
                                  ? MainAxisAlignment.center
                                  : MainAxisAlignment.start,
                              children: [
                                Icon(
                                  item.icon,
                                  size: 17,
                                  color: selected
                                      ? tokens.brandAccent
                                      : tokens.textMuted,
                                ),
                                if (!collapsed) ...[
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      item.section.label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: selected
                                            ? tokens.textPrimary
                                            : tokens.textSecondary,
                                      ),
                                    ),
                                  ),
                                  if (!item.readyInPhase2)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tokens.surfaceSubtle,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: tokens.border,
                                        ),
                                      ),
                                      child: Text(
                                        'Pronto',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w500,
                                          color: tokens.textMuted,
                                        ),
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tokens.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.business_outlined, size: 15, color: tokens.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.restaurantName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: tokens.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'RenovaDev SaaS Platform',
                        style: TextStyle(fontSize: 10.5, color: tokens.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.session,
    required this.currentRoute,
    required this.isCompact,
    required this.onOpenDrawer,
    required this.onSignOut,
    this.onNavigateBackToSales,
  });

  final BackofficeSession session;
  final BackofficeRoute currentRoute;
  final bool isCompact;
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          if (isCompact) ...[
            IconButton(
              onPressed: onOpenDrawer,
              icon: const Icon(Icons.menu, size: 18),
              tooltip: 'Menú',
            ),
            const SizedBox(width: 8),
          ],
          if (onNavigateBackToSales != null) ...[
            IconButton(
              onPressed: onNavigateBackToSales,
              icon: const Icon(Icons.arrow_back, size: 17),
              tooltip: 'Volver a Ventas',
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Row(
              children: [
                Text(
                  currentRoute.saleId != null
                      ? 'Ventas  /  Detalle ${currentRoute.saleId}'
                      : currentRoute.section.label,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isCompact) ...[
                  const SizedBox(width: 12),
                  EnvironmentIndicatorPill(config: session.config),
                ],
              ],
            ),
          ),
          // Branch selector
          _BranchDropdown(session: session),
          const SizedBox(width: 8),
          // Theme mode toggle
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
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            tooltip: 'Cuenta',
            offset: const Offset(0, 42),
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
                      'Restaurante: ${session.restaurantId}',
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
                    Icon(Icons.logout, size: 16),
                    SizedBox(width: 8),
                    Text('Cerrar sesión'),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  if (!isCompact) ...[
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
                      Icons.keyboard_arrow_down,
                      size: 15,
                      color: tokens.textMuted,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchDropdown extends StatelessWidget {
  const _BranchDropdown({required this.session});

  final BackofficeSession session;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final branches = session.branches;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
            Icons.keyboard_arrow_down,
            size: 15,
            color: tokens.textMuted,
          ),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: tokens.textPrimary,
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Todas las sucursales'),
            ),
            ...branches.map(
              (b) => DropdownMenuItem<String?>(
                value: b.id,
                child: Text(b.name),
              ),
            ),
          ],
          onChanged: session.selectBranch,
        ),
      ),
    );
  }
}
