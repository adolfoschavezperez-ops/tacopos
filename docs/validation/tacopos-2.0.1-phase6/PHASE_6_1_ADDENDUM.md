# TacoPOS 2.0.1 — Addendum Fase 6.1

Fecha: 26 de noviembre de 2026. Entorno de pruebas local y exclusivamente ficticio.

## Estado verificado

- Worktree: `C:\Users\geren\Documents\RenovaDev\tacopos-2.0.1`.
- Rama: `fix/tacopos-2.0.1-operational-stability`.
- HEAD de partida: `1fa1665fef7898dff8a30036ccf1b7e12afcb913`; estaba alineado con su upstream antes de este addendum.
- No hubo acceso, consulta, escritura, despliegue ni cambio en Firebase productivo. No se cambió Rules, índices, Functions, versiones, ni el código de negocio.
- La candidata usada conserva SHA-256 `732201CF7C3C8B553EC0E60749F251E3E1AFDAE210847F48A16637C60524DF2F`, copiada de `firestore.rules.production-candidate` a una ruta temporal fuera del repositorio. La línea de comando del proceso Firestore confirmó la ruta de esa copia.

## Entorno de Emulator

Se preservaron las instancias preexistentes. Para la sesión de empleado se levantó una instancia aislada con el ID que trae la configuración Android debug (`demo-tacopos-2-0-1`), pero puertos distintos: Auth `127.0.0.1:9198`, Firestore `127.0.0.1:8183`, Functions `127.0.0.1:5103`, hub `4410`. Firebase CLI 15.30.0, Node 22.21.0 y Firestore Emulator 1.22.0 / Java 21.0.12. Los fixtures se crearon únicamente bajo ese proyecto: cuatro empleados de demostración, una sucursal y un registro de dispositivo. No se cargaron órdenes de negocio.

El primer intento usó `demo-tacopos-phase6-1`, mientras la configuración nativa debug apuntaba a `demo-tacopos-2-0-1`; no se contaron sus lecturas de catálogo como resultado funcional. La instancia posterior alineó proyecto, app y fixtures y pasó una aserción temprana de igualdad del `projectId`.

La suite de Rules se ejecutó aparte contra una instancia Firestore nueva, proyecto `demo-tacopos-rules-final`, puerto `8283`, con el mismo SHA de Rules candidata. Se evitó apuntar la suite al emulador que conserva los fixtures de la prueba Android.

## Restauración de sesión

La causa de la aserción anterior del test quedó localizada en la precondición: el test tenía un usuario Firebase Auth, pero no una identidad operativa de empleado persistida. `LoginGate` restaura el empleado y sucursal almacenados de forma segura y revalida empleado, permisos y dispositivo; Auth por sí solo no debe iniciar una sesión operativa.

Se ajustó únicamente `integration_test/operational_session_android_test.dart` para exigir una cuenta de Auth Emulator sembrada, comprobar el `projectId`, cargar un empleado y sucursal reales del fixture, validar el dispositivo, persistir la identidad y entonces montar `LoginGate`. La nueva secuencia inicia con `AppSession` vacío.

Resultado Android AVD `emulator-5554`: **1/1 PASS** para restauración por `LoginGate`, refresh forzado del token Firebase y ciclo `paused/resumed`, conservando empleado y sucursal. Este recorrido no ejercita PIN/UI de primer inicio ni reinicio físico del dispositivo; la evidencia de reinicio de proceso online está en los addenda anteriores de `RESULTS.md`.

**Incidente de la automatización:** al terminar, el runner de `flutter test integration_test` retiró el paquete `com.renova.tacopos` del AVD (confirmado porque `adb shell pm path com.renova.tacopos` dejó de devolver ruta). Eso elimina el almacenamiento local de esa instalación. El AVD era de pruebas, pero no se inspeccionó antes si contenía borradores locales; por tanto no se puede certificar que el almacenamiento local previo estuviera vacío ni que se preservaran posibles borradores. Los documentos de Firestore Emulator no se borraron. No se repetirá ese runner sobre el AVD para validaciones de borradores. No se afirma que haya ocurrido pérdida de una operación real.

## Revisión histórica +31 / +32

Se identificaron commits y APK debug disponibles, pero **no se instalaron ni ejecutaron** contra Rules candidatas. Son reconstrucciones debug con puente/configuración local de Emulator en los worktrees históricos, no son los APK originales distribuidos por Google Play:

| Versión reconstruida | Commit fuente | APK debug SHA-256 | Manifest |
|---|---|---|---|
| +31 | `6b638e154921eb223134dee5fa5f35b0fee57f08` | `CD0D8F9F5EA89395D5C55D1FC4BDB48B73DDE435F73BF6775CFF8EE61DADCF5B` | `com.renova.tacopos`, versionCode 31, versionName `1.5.13` |
| +32 | `1c660da74c54cd87495b26c2698d3808a0bb638d` | `FF3B0249E1F06EDA17452A2612A34A36F419BB1378873AD501C69B6CE247329D` | `com.renova.tacopos`, versionCode 32, versionName `2.0.0-rc.1` |

La inspección de diferencias mostró modificaciones locales de configuración debug/Emulator y archivos generados en esos worktrees; no se tocaron. No se infiere compatibilidad operativa o de escritura de Rules por haber verificado los manifests.

## Consumo independiente de empleado

**NO EJECUTADO desde la interfaz ni conciliado.** La evidencia anterior de `employee_free_meal` corresponde a un descuento de beneficio de comida y no es el movimiento de pago `employee_consumption`. No se afirma su impacto en Caja, inventario o Backoffice en esta corrida.

## Rendimiento sostenido

**NO EJECUTADO** con 2,001 órdenes ni a los minutos 0/5/15/30. No se generaron métricas nuevas de CPU, RAM, snapshots, conversiones, listeners, bytes o lecturas facturables. Las cifras instrumentales del AVD en `DEVICE_PERFORMANCE_INCIDENT.md` son muestras de humo/ventanas breves, no sustituyen este escenario ni prueban ahorro de tráfico o costo.

No se atribuye la lentitud de producción al histórico de órdenes con esta evidencia. No se habilitó `operationalActive`, filtros de estado ni migraciones.

## Regresión ejecutada

| Validación | Resultado |
|---|---:|
| `flutter analyze` | PASS, sin issues |
| `flutter test --reporter compact` | PASS, **972/972** |
| `npm test` en `functions/`, Node `v22.21.0`, Firestore/Auth Emulator locales | PASS, build TypeScript y **117/117** |
| `npm run test:rules`, instancia nueva con candidate Rules SHA indicado | PASS, **139/139** |
| `flutter test integration_test/operational_session_android_test.dart` en Android AVD y candidate Rules | PASS, **1/1** |
| `git diff --check` | PASS |

## Dictamen

Fase 6.1 **NO CERRADA**. La restauración de una sesión operativa con fixture válido quedó reproducida en Android y se aclaró que el fallo anterior era una precondición incompleta del test, no una prueba de pérdida de sesión de empleado. Se mantiene **NO-GO** para cierre/release porque faltan pruebas operativas de compatibilidad +31/+32, consumo independiente de empleado y perfil sostenido con 2,001 órdenes. También queda la limitación del almacenamiento local del AVD anotada arriba. No hay cambios productivos ni despliegues.
