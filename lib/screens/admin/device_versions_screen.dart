import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_update/app_update_policy.dart';
import '../../core/theme/brand_colors.dart';
import '../../services/device_registry_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class DeviceVersionsScreen extends StatefulWidget {
  const DeviceVersionsScreen({
    super.key,
    DeviceRegistryService? registryService,
  }) : _registryService = registryService;

  final DeviceRegistryService? _registryService;

  @override
  State<DeviceVersionsScreen> createState() => _DeviceVersionsScreenState();
}

class _DeviceVersionsScreenState extends State<DeviceVersionsScreen> {
  late final DeviceRegistryService _registryService;
  String _branchFilter = 'all';
  DeviceUpdateStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    _registryService =
        widget._registryService ?? DeviceRegistryService.instance;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PremiumBackground(
        child: SafeArea(
          child: StreamBuilder<List<RegisteredDevice>>(
            stream: _registryService.watchDevices(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudo cargar',
                  message: '${snapshot.error}',
                );
              }
              if (!snapshot.hasData) {
                return const LoadingPanel(message: 'Cargando dispositivos...');
              }
              final devices = snapshot.data!;
              final branches = _branchOptions(devices);
              final filtered = devices.where(_matchesFilters).toList();
              return ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  _Header(
                    totalDevices: devices.length,
                    filteredDevices: filtered.length,
                  ),
                  const SizedBox(height: 18),
                  _Filters(
                    branches: branches,
                    branchFilter: _branchFilter,
                    statusFilter: _statusFilter,
                    onBranchChanged: (value) =>
                        setState(() => _branchFilter = value),
                    onStatusChanged: (value) =>
                        setState(() => _statusFilter = value),
                  ),
                  const SizedBox(height: 18),
                  if (filtered.isEmpty)
                    const EmptyState(
                      icon: Icons.devices_other_outlined,
                      title: 'Sin dispositivos',
                      message:
                          'Cuando las tablets abran TacoPOS desde Google Play apareceran aqui.',
                    )
                  else
                    _DeviceTable(devices: filtered),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  bool _matchesFilters(RegisteredDevice device) {
    if (_branchFilter != 'all' && device.branchId != _branchFilter) {
      return false;
    }
    if (_statusFilter != null && device.updateStatus != _statusFilter) {
      return false;
    }
    return true;
  }

  Map<String, String> _branchOptions(List<RegisteredDevice> devices) {
    final values = <String, String>{'all': 'Todas'};
    for (final device in devices) {
      if (device.branchId.isEmpty) continue;
      values[device.branchId] = device.branchName.isEmpty
          ? device.branchId
          : device.branchName;
    }
    return values;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.totalDevices, required this.filteredDevices});

  final int totalDevices;
  final int filteredDevices;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const Icon(
            Icons.devices_other_outlined,
            color: BrandColors.accentYellow,
            size: 34,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dispositivos y versiones',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '$filteredDevices de $totalDevices dispositivos visibles',
                  style: const TextStyle(color: BrandColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.branches,
    required this.branchFilter,
    required this.statusFilter,
    required this.onBranchChanged,
    required this.onStatusChanged,
  });

  final Map<String, String> branches;
  final String branchFilter;
  final DeviceUpdateStatus? statusFilter;
  final ValueChanged<String> onBranchChanged;
  final ValueChanged<DeviceUpdateStatus?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<String>(
            initialValue: branches.containsKey(branchFilter)
                ? branchFilter
                : 'all',
            decoration: const InputDecoration(labelText: 'Sucursal'),
            items: branches.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: (value) => onBranchChanged(value ?? 'all'),
          ),
        ),
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<DeviceUpdateStatus?>(
            initialValue: statusFilter,
            decoration: const InputDecoration(labelText: 'Estado'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Todos')),
              DropdownMenuItem(
                value: DeviceUpdateStatus.upToDate,
                child: Text('Actualizado'),
              ),
              DropdownMenuItem(
                value: DeviceUpdateStatus.updateRecommended,
                child: Text('Actualizacion recomendada'),
              ),
              DropdownMenuItem(
                value: DeviceUpdateStatus.updateRequired,
                child: Text('Actualizacion obligatoria'),
              ),
              DropdownMenuItem(
                value: DeviceUpdateStatus.playUpdateUnavailable,
                child: Text('Pendiente en Google Play'),
              ),
              DropdownMenuItem(
                value: DeviceUpdateStatus.unknown,
                child: Text('Sin conexion reciente'),
              ),
            ],
            onChanged: onStatusChanged,
          ),
        ),
      ],
    );
  }
}

class _DeviceTable extends StatelessWidget {
  const _DeviceTable({required this.devices});

  final List<RegisteredDevice> devices;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Nombre')),
            DataColumn(label: Text('Sucursal')),
            DataColumn(label: Text('Funcion')),
            DataColumn(label: Text('Version instalada')),
            DataColumn(label: Text('Version recomendada')),
            DataColumn(label: Text('Ultima conexion')),
            DataColumn(label: Text('Empleado activo')),
            DataColumn(label: Text('Estado')),
          ],
          rows: devices
              .map(
                (device) => DataRow(
                  cells: [
                    DataCell(Text(device.deviceName)),
                    DataCell(
                      Text(_fallback(device.branchName, device.branchId)),
                    ),
                    DataCell(Text(_fallback(device.role, '-'))),
                    DataCell(
                      Text(
                        '${_fallback(device.appVersionName, '-')} '
                        '(${device.appVersionCode})',
                      ),
                    ),
                    DataCell(
                      Text(
                        device.recommendedVersionCode <= 0
                            ? '-'
                            : '${device.recommendedVersionCode}',
                      ),
                    ),
                    DataCell(Text(_lastSeen(device.lastSeenAt))),
                    DataCell(Text(_fallback(device.employeeName, '-'))),
                    DataCell(_StatusPill(status: _effectiveStatus(device))),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  DeviceUpdateStatus _effectiveStatus(RegisteredDevice device) {
    final lastSeenAt = device.lastSeenAt;
    if (lastSeenAt == null ||
        DateTime.now().difference(lastSeenAt) > const Duration(hours: 24)) {
      return DeviceUpdateStatus.unknown;
    }
    return device.updateStatus;
  }

  String _fallback(String value, String fallback) {
    return value.trim().isEmpty ? fallback : value.trim();
  }

  String _lastSeen(DateTime? value) {
    if (value == null) return 'Sin registro';
    return DateFormat('dd/MM/yyyy HH:mm').format(value);
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final DeviceUpdateStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      DeviceUpdateStatus.upToDate => ('Actualizado', BrandColors.success),
      DeviceUpdateStatus.updateRecommended => (
        'Actualizacion recomendada',
        BrandColors.accentYellow,
      ),
      DeviceUpdateStatus.updateRequired => (
        'Actualizacion obligatoria',
        BrandColors.danger,
      ),
      DeviceUpdateStatus.playUpdateUnavailable => (
        'Pendiente en Google Play',
        BrandColors.accentOrange,
      ),
      DeviceUpdateStatus.unknown => (
        'Sin conexion reciente',
        BrandColors.textMuted,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}
