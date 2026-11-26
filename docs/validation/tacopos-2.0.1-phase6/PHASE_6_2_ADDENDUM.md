# TacoPOS 2.0.1 — Addendum Fase 6.2

Fecha: 26 de noviembre de 2026. Entorno de desarrollo local; no se usó Firebase productivo.

## Procedencia y protección del entorno

- Worktree de validación: `C:\Users\geren\Documents\RenovaDev\tacopos-2.0.1`.
- Rama: `fix/tacopos-2.0.1-operational-stability`.
- Commit base: `c85c88aea0c5c84d5647bbc6ec3ac6de5e7c271b`, sincronizado con upstream al inicio.
- Rules candidatas cargadas en Emulator: SHA-256 `732201CF7C3C8B553EC0E60749F251E3E1AFDAE210847F48A16637C60524DF2F`; endpoint local `127.0.0.1:8183`, Auth `9198`, Functions `5103`, proyecto `demo-tacopos-2-0-1`.
- Se conservaron los AVDs, emuladores, instalaciones y datos preexistentes. No se ejecutó `uninstall`, `pm clear`, wipe, restablecimiento ni runner con limpieza automática. Tampoco se ejecutaron operaciones de negocio ni escrituras en producción.
- Se crearon dos AVDs desechables: `TacoPOS_Phase62_Plus31` y `TacoPOS_Phase62_Plus32`. Solo se arrancó el primero; se identificó como `emulator-5556`. El `emulator-5554` preexistente permaneció sin interacción modificadora.

## Clientes históricos reconstruidos

Los artefactos son APK debug reconstruidos desde commits históricos, con configuración temporal de Emulator; no son los binarios firmados/distribuidos por Google Play. Cambios temporales solo en los worktrees detached `tacopos-phase62-plus31` y `tacopos-phase62-plus32`; no se llevaron al worktree de la rama, no se commitearon ni se empujaron. Cada puente exige `kDebugMode` y proyecto `demo-*`; release mantiene Firebase options y App Check normales.

| Cliente | Commit fuente | APK | Identidad | Firma debug SHA-256 |
|---|---|---|---|---|
| +31 | `6b638e154921eb223134dee5fa5f35b0fee57f08` | `C:\Users\geren\Documents\RenovaDev\tacopos-phase62-plus31\build\app\outputs\flutter-apk\app-debug.apk` | `com.renova.tacopos`, code 31, `1.5.13` | `e1599974f48eaeffe92b057f38f89e5cca0bd2ecc36afafda6672c97b6e8d2b3` |
| +32 | `1c660da74c54cd87495b26c2698d3808a0bb638d` | `C:\Users\geren\Documents\RenovaDev\tacopos-phase62-plus32\build\app\outputs\flutter-apk\app-debug.apk` | `com.renova.tacopos`, code 32, `2.0.0-rc.1` | `e1599974f48eaeffe92b057f38f89e5cca0bd2ecc36afafda6672c97b6e8d2b3` |

| Cliente | SHA-256 del APK |
|---|---|
| +31 debug | `5D312F7073988DB42DA6FE3C011C8CF9B1CAE1EAD2A1CCC1AD071FCC04245681` |
| +32 debug | `79D369CFBC7BC66F46F899797173FA6ABBEA2D8BF41A7F8AAA480D6DB44CAC31` |

Configuración para ambas reconstrucciones: `demo-tacopos-2-0-1`, Auth `10.0.2.2:9198`, Firestore `10.0.2.2:8183`, Functions `10.0.2.2:5103`. La configuración Android debug indicaba la misma app package/project de demo. El puente de +31 agregó opciones Firebase exclusivamente para debug; +32 reutilizó su puente existente y parametrizó los puertos. `flutter pub get` también actualizó archivos generados por plugins en esos worktrees. No se alteró la lógica de negocio ni se transfirieron esos cambios.

## Resultado del intento Android

**Compatibilidad operativa +31/+32: NO DEMOSTRADA.** +31 se instaló en el AVD desechable `emulator-5556` después de que Android reportó que el primer arranque había terminado. La app comenzó su actividad y Firebase Auth produjo una identidad anónima de prueba. Antes de llegar a la pantalla de acceso, el AVD mostró el diálogo de Android **“System UI isn’t responding”**. Logcat mostró lentitud severa del sistema (incluyendo 921 frames omitidos) y timeouts de servicios Android; la automatización de accesibilidad devolvió `null root node`. No se capturó una pantalla funcional ni se hizo login PIN o una operación de negocio.

Evidencia visual del bloqueo de entorno: [`phase62-plus31-initial.png`](evidence/phase62-plus31-initial.png), SHA-256 `4467C11E0AB51F11A66A8763AD0806C22652CBBBB4CCD6AED9B88EB0814B70C9`. Después se detuvo exclusivamente el AVD desechable con `adb -s emulator-5556 emu kill`, sin borrar su almacenamiento. El AVD +32 quedó sin iniciar. El apagado recuperó memoria del host y los demás dispositivos permanecieron activos.

No se probó +31 crea/lee en +32, +32 crea/lee en +31, envío/surtido, pagos, órdenes legacy, reconexión, concurrencia, reintentos ni rechazo de cambios terminales desde clientes Android anteriores. El build y la firma debug no prueban compatibilidad contra Rules.

## Consumo independiente de empleado

**NO EJECUTADO de extremo a extremo.** Se inspeccionó el flujo de `PaymentScreen`: `employee_consumption` requiere seleccionar un empleado y se pasa por `onConfirm`. Las pruebas unitarias/widget y de reportes existentes distinguen el método de pago `employee_consumption` del descuento `employee_free_meal`, pero no prueban el movimiento operativo completo ni el corte de caja desde UI/Emulator. No se registró ningún movimiento ficticio en este intento y no se afirma impacto real en Caja, inventario, auditoría o Backoffice.

Se ejecutó el conjunto dirigido ya existente:

```text
flutter test --reporter compact \
  test/canonical_sales_summary_test.dart \
  test/employee_benefit_reconciliation_test.dart \
  test/order_payment_entry_widget_test.dart \
  test/finance_dashboard_test.dart
```

Resultado: **116/116 PASS**. Es evidencia de lógica/widget y agregación, no sustituto del movimiento independiente realizado desde la UI ni de su conciliación.

## Rendimiento sostenido con 2,001 órdenes

**NO EJECUTADO.** No se sembraron las 2,001 órdenes y no se midieron ventanas 0/5/15/30, ni ciclos de actividad de 30 minutos para baseline/candidato. No se midieron RAM/CPU comparativas, latencias, snapshots reales con volumen, bytes ni lecturas facturables; no se afirma ahorro cuantitativo.

La inspección del código actual confirma un límite relevante: `watchOpenOrders()`, `watchOpenTakeoutOrders()` y `watchOpenStandingOrders()` usan `_ordersRef.snapshots()` sin filtro. El primer snapshot recorre y convierte todos los documentos presentes para determinar actividad y sucursal. Los snapshots siguientes convierten documentos cambiados mediante `docChanges`, lo cual reduce el procesamiento de modelos en actualizaciones incrementales, pero **no reduce el conjunto histórico de la consulta ni el tamaño de su snapshot inicial**. `documents` en el diagnóstico es tamaño de snapshot, no una medida de bytes ni de lecturas facturables.

## Autenticación y borradores

**NO EJECUTADO en esta Fase 6.2.** No se realizó PIN, cierre/reapertura de proceso, reinicio del AVD, renovación autenticada, microcorte, recuperación de borrador ni envío tras reconexión. La pantalla de sistema no responsiva impidió alcanzar la interfaz; no se infiere un defecto de autenticación de la app ni se ejecutaron borrados de sus datos locales.

## Matriz resumida

| Bloque | Resultado | Límite |
|---|---|---|
| Compilación +31 debug Emulator | PASS | APK reconstruido; no equivale a Google Play |
| Compilación +32 debug Emulator | PASS | APK reconstruido; no equivale a Google Play |
| Instalación +31 en AVD desechable | PASS parcial | Instaló y arrancó actividad; el AVD/Android se bloqueó antes del login |
| Compatibilidad operativa +31/+32 | NO EJECUTADO | Sin recorridos de negocio ni cruce de versiones |
| Consumo empleado, suite dirigida | PASS 116/116 | Unit/widget/reportes; no movimiento/corte UI |
| Consumo independiente desde UI y conciliación | NO EJECUTADO | Bloqueante operativo pendiente |
| Perfil 2,001 órdenes, 0/5/15/30 por 30 min | NO EJECUTADO | No hay mediciones comparativas |
| PIN/reinicio/red/borrador | NO EJECUTADO | Bloqueado antes de llegar a UI |
| Producción | SIN CAMBIOS | Sin acceso ni escrituras productivas |

## Dictamen

Fase 6.2 permanece **ABIERTA / NO-GO**. Los dos APK reconstruidos se compilaron con IDs y configuración de Emulator y el conjunto dirigido de finanzas pasó, pero no existe evidencia de compatibilidad operativa histórica, consumo independiente conciliado ni rendimiento sostenido representativo. La primera causa de bloqueo Android demostrada en esta corrida fue la falta de respuesta de System UI/AVD bajo carga del host; no se atribuye al código de TacoPOS. Para continuar se necesita una infraestructura Android aislada que pueda mantener la UI responsiva, además de una ventana continua para ejecutar las dos pruebas de 30 minutos y las operaciones de negocio en Emulator.
