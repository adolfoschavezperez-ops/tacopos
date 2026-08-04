import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/app_update/app_update_policy.dart';
import 'package:tacopos/services/app_update_service.dart';
import 'package:tacopos/widgets/mandatory_update_gate.dart';

void main() {
  testWidgets('Mesas valida inmediatamente al abrir', (tester) async {
    final client = _FakeMandatoryUpdateClient([_allowed()]);

    await tester.pumpWidget(_app(_gate(client, 'Mesas')));
    await tester.pump();

    expect(client.checkCount, 1);
    expect(find.text('Mesas activa'), findsOneWidget);
  });

  testWidgets('Cocina valida inmediatamente al abrir', (tester) async {
    final client = _FakeMandatoryUpdateClient([_allowed()]);

    await tester.pumpWidget(_app(_gate(client, 'Cocina')));
    await tester.pump();

    expect(client.checkCount, 1);
    expect(find.text('Cocina activa'), findsOneWidget);
  });

  testWidgets('Mesas vuelve a validar cada 5 minutos', (tester) async {
    final client = _FakeMandatoryUpdateClient([_allowed(), _allowed()]);

    await tester.pumpWidget(_app(_gate(client, 'Mesas')));
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();

    expect(client.checkCount, 2);
  });

  testWidgets('Cocina vuelve a validar cada 5 minutos', (tester) async {
    final client = _FakeMandatoryUpdateClient([_allowed(), _allowed()]);

    await tester.pumpWidget(_app(_gate(client, 'Cocina')));
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();

    expect(client.checkCount, 2);
  });

  testWidgets('regresar del segundo plano ejecuta una validacion', (
    tester,
  ) async {
    final client = _FakeMandatoryUpdateClient([_allowed(), _allowed()]);

    await tester.pumpWidget(_app(_gate(client, 'Mesas')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(client.checkCount, 2);
  });

  testWidgets('no crea multiples timers al reconstruir', (tester) async {
    final client = _FakeMandatoryUpdateClient([
      _allowed(),
      _allowed(),
      _allowed(),
    ]);

    await tester.pumpWidget(_app(_gate(client, 'Mesas')));
    await tester.pump();
    await tester.pumpWidget(_app(_gate(client, 'Mesas')));
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();

    expect(client.checkCount, 2);
  });

  testWidgets('no muestra overlays duplicados', (tester) async {
    final client = _FakeMandatoryUpdateClient([_required(), _required()]);

    await tester.pumpWidget(_app(_gate(client, 'Mesas')));
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();

    expect(find.text('Actualización obligatoria'), findsOneWidget);
  });

  testWidgets('el boton atras no cierra el bloqueo', (tester) async {
    final client = _FakeMandatoryUpdateClient([_required()]);

    await tester.pumpWidget(_app(_gate(client, 'Mesas')));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Actualización obligatoria'), findsOneWidget);
  });

  testWidgets('tocar fuera no cierra el bloqueo', (tester) async {
    final client = _FakeMandatoryUpdateClient([_required()]);

    await tester.pumpWidget(_app(_gate(client, 'Mesas')));
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();

    expect(find.text('Actualización obligatoria'), findsOneWidget);
  });

  testWidgets('Actualizar ahora abre Google Play una sola vez', (tester) async {
    final client = _FakeMandatoryUpdateClient([_required()]);

    await tester.pumpWidget(_app(_gate(client, 'Cocina')));
    await tester.pump();
    await tester.tap(find.text('Actualizar ahora'));
    await tester.pump();

    expect(client.openGooglePlayCount, 1);
    expect(AppUpdateService.googlePlayPackageId, 'com.renova.tacopos');
  });

  testWidgets('regresar de Google Play vuelve a validar', (tester) async {
    final client = _FakeMandatoryUpdateClient([_required(), _required()]);

    await tester.pumpWidget(_app(_gate(client, 'Cocina')));
    await tester.pump();
    await tester.tap(find.text('Actualizar ahora'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(client.openGooglePlayCount, 1);
    expect(client.checkCount, 2);
  });

  testWidgets('el bloqueo desaparece al cumplir la version minima', (
    tester,
  ) async {
    final client = _FakeMandatoryUpdateClient([_required(), _allowed()]);

    await tester.pumpWidget(_app(_gate(client, 'Mesas')));
    await tester.pump();
    expect(find.text('Actualización obligatoria'), findsOneWidget);
    await tester.tap(find.text('Volver a verificar'));
    await tester.pump();

    expect(find.text('Actualización obligatoria'), findsNothing);
    expect(find.text('Mesas activa'), findsOneWidget);
  });

  testWidgets('error de red sin politica almacenada no bloquea', (
    tester,
  ) async {
    final client = _FakeMandatoryUpdateClient([Exception('offline')]);

    await tester.pumpWidget(_app(_gate(client, 'Mesas')));
    await tester.pump();

    expect(find.text('Actualización obligatoria'), findsNothing);
    expect(find.text('Mesas activa'), findsOneWidget);
  });

  testWidgets(
    'error de red con politica obligatoria almacenada mantiene bloqueo',
    (tester) async {
      final client = _FakeMandatoryUpdateClient([
        _required(),
        Exception('offline'),
      ]);

      await tester.pumpWidget(_app(_gate(client, 'Mesas')));
      await tester.pump();
      await tester.tap(find.text('Volver a verificar'));
      await tester.pump();

      expect(find.text('Actualización obligatoria'), findsOneWidget);
    },
  );

  testWidgets(
    'error de red con politica permisiva almacenada permite continuar',
    (tester) async {
      final client = _FakeMandatoryUpdateClient([
        _allowed(),
        Exception('offline'),
      ]);

      await tester.pumpWidget(_app(_gate(client, 'Cocina')));
      await tester.pump();
      await tester.pump(const Duration(minutes: 5));
      await tester.pump();

      expect(find.text('Actualización obligatoria'), findsNothing);
      expect(find.text('Cocina activa'), findsOneWidget);
    },
  );

  testWidgets('el timer se cancela al destruir la pantalla', (tester) async {
    final client = _FakeMandatoryUpdateClient([_allowed(), _allowed()]);

    await tester.pumpWidget(_app(_gate(client, 'Mesas')));
    await tester.pump();
    await tester.pumpWidget(_app(const SizedBox.shrink()));
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();

    expect(client.checkCount, 1);
  });

  testWidgets('evita consultas simultaneas', (tester) async {
    final client = _FakeMandatoryUpdateClient([]);
    client.pending = Completer<AppUpdateCheckResult>();

    await tester.pumpWidget(_app(_gate(client, 'Mesas')));
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();

    expect(client.checkCount, 1);
    client.pending!.complete(_allowed());
    await tester.pump();
  });
}

Widget _app(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

Widget _gate(_FakeMandatoryUpdateClient client, String screenName) {
  return MandatoryUpdateGate(
    screenName: screenName,
    updateClient: client,
    child: Center(child: Text('$screenName activa')),
  );
}

class _FakeMandatoryUpdateClient implements MandatoryUpdateClient {
  _FakeMandatoryUpdateClient(this.results);

  final List<Object> results;
  Completer<AppUpdateCheckResult>? pending;
  int checkCount = 0;
  int openGooglePlayCount = 0;

  @override
  Future<AppUpdateCheckResult> checkForUpdate() async {
    checkCount++;
    final completer = pending;
    if (completer != null) return completer.future;
    final result = results.isEmpty ? _allowed() : results.removeAt(0);
    if (result is AppUpdateCheckResult) return result;
    throw result;
  }

  @override
  Future<void> openGooglePlay() async {
    openGooglePlayCount++;
  }
}

AppUpdateCheckResult _allowed() {
  return _result(
    decision: const AppUpdateDecision(
      severity: AppUpdateSeverity.none,
      message: '',
      canContinue: true,
    ),
    currentVersionCode: 11,
    minimumSupportedVersionCode: 11,
  );
}

AppUpdateCheckResult _required() {
  return _result(
    decision: const AppUpdateDecision(
      severity: AppUpdateSeverity.required,
      message: 'Actualizacion requerida',
      canContinue: false,
    ),
    currentVersionCode: 10,
    minimumSupportedVersionCode: 11,
  );
}

AppUpdateCheckResult _result({
  required AppUpdateDecision decision,
  required int currentVersionCode,
  required int minimumSupportedVersionCode,
}) {
  return AppUpdateCheckResult(
    decision: decision,
    currentVersionCode: currentVersionCode,
    currentVersionName: currentVersionCode == 11 ? '1.4.0' : '1.3.0',
    currentPackageName: 'com.renova.tacopos',
    minimumSupportedVersionCode: minimumSupportedVersionCode,
    recommendedVersionCode: 11,
    playUpdateAvailability: const PlayUpdateAvailability(
      updateAvailable: true,
      flexibleAllowed: true,
      immediateAllowed: true,
      installedFromPlay: true,
      installerPackageName: 'com.android.vending',
      availableVersionCode: 11,
    ),
    configActive: true,
    forceUpdate: decision.isRequired,
  );
}
