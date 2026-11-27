enum BackofficeSection {
  dashboard('/dashboard', 'Dashboard'),
  sales('/sales', 'Ventas'),
  cash('/cash', 'Caja'),
  purchases('/purchases', 'Compras'),
  inventory('/inventory', 'Inventarios'),
  finance('/finance', 'Finanzas'),
  reports('/reports', 'Reportes'),
  employees('/employees', 'Empleados'),
  audit('/audit', 'Auditoría'),
  settings('/settings', 'Configuración');

  const BackofficeSection(this.path, this.label);

  final String path;
  final String label;
}

class BackofficeRoute {
  const BackofficeRoute.login()
    : isLogin = true,
      section = BackofficeSection.dashboard,
      saleId = null;

  const BackofficeRoute.section(this.section)
    : isLogin = false,
      saleId = null;

  const BackofficeRoute.saleDetail(this.saleId)
    : isLogin = false,
      section = BackofficeSection.sales;

  final bool isLogin;
  final BackofficeSection section;
  final String? saleId;

  String get location {
    if (isLogin) return '/login';
    if (saleId != null && saleId!.isNotEmpty) return '/sales/$saleId';
    return section.path;
  }

  static BackofficeRoute parse(String? rawLocation) {
    final uri = Uri.tryParse(rawLocation ?? '') ?? Uri(path: '/dashboard');
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      return const BackofficeRoute.section(BackofficeSection.dashboard);
    }
    final first = segments.first.toLowerCase();
    if (first == 'login') {
      return const BackofficeRoute.login();
    }
    if (first == 'sales' && segments.length >= 2) {
      return BackofficeRoute.saleDetail(segments[1]);
    }
    for (final section in BackofficeSection.values) {
      if (section.path == '/$first') {
        return BackofficeRoute.section(section);
      }
    }
    return const BackofficeRoute.section(BackofficeSection.dashboard);
  }

  @override
  bool operator ==(Object other) {
    return other is BackofficeRoute &&
        other.isLogin == isLogin &&
        other.section == section &&
        other.saleId == saleId;
  }

  @override
  int get hashCode => Object.hash(isLogin, section, saleId);
}
