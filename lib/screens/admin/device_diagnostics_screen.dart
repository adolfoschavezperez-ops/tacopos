import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/operational_diagnostics_service.dart';
import '../../widgets/branded_scaffold.dart';

class DeviceDiagnosticsScreen extends StatefulWidget {
  const DeviceDiagnosticsScreen({super.key});

  @override
  State<DeviceDiagnosticsScreen> createState() =>
      _DeviceDiagnosticsScreenState();
}

class _DeviceDiagnosticsScreenState extends State<DeviceDiagnosticsScreen> {
  late Future<List<Map<String, Object?>>> _events;

  @override
  void initState() {
    super.initState();
    _events = OperationalDiagnosticsService.instance.readRecent();
  }

  void _refresh() {
    setState(() {
      _events = OperationalDiagnosticsService.instance.readRecent();
    });
  }

  Future<void> _copy() async {
    final text = await OperationalDiagnosticsService.instance.exportRecent();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnósticos locales copiados.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BrandedScaffold(
      title: 'Diagnóstico del dispositivo',
      actions: [
        IconButton(
          tooltip: 'Actualizar',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Copiar diagnóstico',
          onPressed: _copy,
          icon: const Icon(Icons.copy_all_outlined),
        ),
      ],
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _events,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('No se pudieron leer los diagnósticos.'));
          }
          final events = snapshot.data ?? const [];
          if (events.isEmpty) {
            return const Center(
              child: Text('Este dispositivo todavía no tiene eventos.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: events.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Registro local acotado a 128 KB. No contiene PIN, tokens, '
                    'identificadores de órdenes ni mensajes de error. '
                    'Los datos no se envían a Firebase.',
                  ),
                );
              }
              final event = events[index - 1];
              final timestamp = event['at']?.toString() ?? '';
              final category = event['category']?.toString() ?? 'evento';
              final name = event['event']?.toString() ?? 'desconocido';
              final result = event['result']?.toString() ?? '';
              final details = event.entries
                  .where(
                    (entry) => !{
                      'at',
                      'category',
                      'event',
                      'result',
                    }.contains(entry.key),
                  )
                  .map((entry) => '${entry.key}=${entry.value}')
                  .join(' · ');
              return Card(
                child: ListTile(
                  dense: true,
                  title: Text('$category / $name · $result'),
                  subtitle: Text(
                    [timestamp, if (details.isNotEmpty) details].join('\n'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
