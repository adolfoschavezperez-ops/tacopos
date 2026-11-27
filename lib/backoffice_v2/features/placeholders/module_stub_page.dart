import 'package:flutter/material.dart';

import '../../core/design/design_tokens.dart';
import '../../navigation/backoffice_route.dart';
import '../../widgets/saas_card.dart';
import '../../widgets/status_pill.dart';

class ModuleStubPage extends StatelessWidget {
  const ModuleStubPage({
    super.key,
    required this.section,
    required this.targetPhase,
    required this.description,
    required this.plannedCapabilities,
  });

  final BackofficeSection section;
  final String targetPhase;
  final String description;
  final List<String> plannedCapabilities;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        section.label,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(width: 10),
                      StatusPill(label: targetPhase, tone: StatusTone.info),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SaasCard(
          title: 'Estado de implementación',
          subtitle: 'Módulo reservado dentro de la arquitectura modular',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Este módulo aún no está habilitado en Fase 2 (Infraestructura y arquitectura base). No se muestran datos simulados ni flujos incompletos como terminados.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'Alcance planificado:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...plannedCapabilities.map(
                (cap) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 15,
                        color: tokens.brandAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cap,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
