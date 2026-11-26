# TacoPOS 2.0.1 — Cierre de validación Fase 6

Fecha de ejecución: 24 de noviembre de 2026 (hora local del proyecto; algunos logs del emulador quedaron en UTC del 25 de noviembre).

## Alcance y resultado

- Rama de trabajo: `fix/tacopos-2.0.1-operational-stability`.
- Commit base: `338a544ba93097ed6b67910edc26779431d1ab36`.
- Proyecto de Firebase utilizado: `demo-tacopos-2-0-1` en Firebase Emulator Suite, Firestore `127.0.0.1:8082`, Auth `127.0.0.1:9101`, Functions `127.0.0.1:5002`.
- Dispositivos: AVD Android 14 `emulator-5564` y `emulator-5566`. Empleados distintos (`waiter_a` y `waiter_b`) con registros de dispositivo en el restaurante de prueba.
- Ninguna escritura, deploy o consulta de datos se hizo en producción durante las operaciones descritas.
- Dictamen: **NO AUTORIZAR DISTRIBUCIÓN GENERAL**. Hay resultados positivos, pero siguen sin ejecutarse escenarios críticos de recuperación de Cocina, cancelaciones desde UI, borrador offline tras reinicio y Backoffice Finanzas.

## Rules y procedencia

Se obtuvo en modo de solo lectura la versión productiva `projects/tacopos-renovadev/rulesets/167eb735-240f-44cb-9665-7bc42b9dceda`, asociada a `projects/tacopos-renovadev/releases/cloud.firestore` al 24-11-2026. SHA-256 del snapshot productivo: `1ec5e8aa5626377856159f6714fdba80e7c3c9e35fc5fc950521a8879f30a372`.

El archivo `firestore.rules.production-candidate` propone ese baseline con el guard de marcador de captura local conservado y protecciones mínimas para órdenes terminales, sus artículos, pagos y lotes de cocina. SHA-256 candidato: `732201CF7C3C8B553EC0E60749F251E3E1AFDAE210847F48A16637C60524DF2F`. La Rules exacta del candidato fue cargada en el proyecto demo antes de la prueba final de cobro por UI; se leyó de vuelta desde el Emulator REST API y el SHA-256 coincidió exactamente.

Comparado contra el snapshot productivo leído, el candidato contiene 144 líneas añadidas y 8 cambiadas/eliminadas; el resto conserva el baseline. No se propone desplegar el Ruleset acumulado completo de la rama.

Resultados de reglas:

- Suite completa de Rules del repositorio: **137/137 PASS**.
- Pruebas de marcador y de órdenes terminales contra el archivo candidato exacto: **9/9 PASS**.
- Incluyen rechazo de edición de cantidades/captura/pagos posteriores al cierre, rechazo de batch que cierre la orden y agregue producto a la vez, compatibilidad de campos históricos, cierre financiero normal y cancelación administrativa autorizada.
- La aplicación Android sí realizó el pago completo de la orden de $44 después de cargar el candidato exacto. La captura concurrente y el recorrido de pago por persona se realizaron antes con una variante local de compatibilidad del emulador que omitía únicamente la regla de consulta `collectionGroup`; por eso esas interacciones anteriores no se contabilizan como recorridos completos bajo el archivo exacto.
- El candidato es propuesta local, **no desplegada**. No reemplazar Rules productivas completas por el archivo del repositorio sin revisar todos los cambios.

## Resultado del recorrido UI y Firestore

### Pago por persona

Orden de prueba `jyV0AK0TWkESbqCEvnsQ`: mesa de tres personas; persona 1 pastor $20 efectivo, persona 2 asada $24 tarjeta, persona 3 lengua $30 efectivo. Después del primer pago se observó pagado $20 / pendiente $54; después del segundo, pagado $44 / pendiente $30. El tercero dejó la orden `paid`, total $74, pagado $74, pendiente $0, tres pagos activos y la mesa disponible. El folio final tuvo secuencia 1. La aplicación regresó a Mesas automáticamente.

No se simuló un fallo del servicio de presencia posterior al cobro confirmado.

### Captura concurrente y Cocina

Con ambos AVDs autenticados simultáneamente como empleados/dispositivos diferentes, los dos capturaron productos en la misma orden `5c721cOr15hQbWmA0gcp` y enviaron dentro del mismo segundo. El padre quedó con `captureRevision=2`, total $44 y exactamente dos artículos: pastor x1 de `waiter_a` y asada x1 de `waiter_b`, en dos lotes y secuencias distintas. No hubo faltantes ni duplicados en la evidencia persistida.

Cocina recibió ambos lotes desde la UI; se usaron acciones reales para pasar platos y marcar Listo. Los dos artículos terminaron activos, cantidad 1, estado `ready`, y Cocina quedó sin comandas. La corrida no prueba un retraso de red de dos dispositivos ni todos los patrones de concurrencia interna de Firestore; sí demuestra dos solicitudes UI casi simultáneas que quedaron persistidas de forma íntegra.

### Estado en Mesas y corrección encontrada

Con Mesas abierta en el AVD A mientras Cocina procesaba la comanda en el AVD B, Firestore llegó a `ready` para orden, mesa y artículos, pero la tarjeta de Mesas seguía en “En preparación”. Causa: `_itemIsPreparing` consideraba suficiente la marca histórica `cookingAt`, incluso cuando el artículo ya estaba listo.

Se corrigió el orden del predicado para que `isKitchenReadyItem(item)` tenga precedencia sobre `cookingAt`; se agregó una prueba que fallaba antes de la corrección y pasa después. Tras instalar el APK de depuración corregido, se volvió a abrir Mesas sin cambiar las Rules/UI del flujo y la tarjeta reflejó “Listo para cobrar”. La prueba dirigida `test/table_operational_status_test.dart` pasa **16/16**.

### Cobro completo con Rules candidatas exactas y devolución a Mesas

Orden `5c721cOr15hQbWmA0gcp`: antes del pago, $44 total, $0 pagado, $44 pendiente y artículo de cocina listo. Con el SHA exacto de Rules candidato cargado en el emulador, la UI ejecutó el cobro completo en efectivo, mostró Mesas disponible y regresó automáticamente a Mesas. Firestore quedó `paid`, `paidTotal=44`, `pendingTotal=0`, un pago activo en efectivo por $44 con folio secuencial 2; la mesa quedó `available` sin `currentOrderId`.

## Cierre ficticio de Cocina y Caja

Se cerró Cocina por el flujo normal, registrando el inventario de prueba: sobrante 1 kg, merma 0. La Caja rechazó inicialmente el cierre mientras Cocina estaba abierta; después de cerrar Cocina, el cierre normal pasó. En Caja Admin se consultó el corte del 24-11-2026.

| Concepto del corte ficticio | Importe |
|---|---:|
| Venta bruta / venta neta | $118.00 |
| Descuentos | $0.00 |
| Pagos activos (4) | $118.00 |
| Efectivo de ventas | $94.00 |
| Tarjeta de ventas / terminal | $24.00 / $24.00 |
| Comisión absorbida de tarjeta | $0.96 |
| Consumo de empleados / retiros | $0.00 / $0.00 |
| Fondo inicial | $1,000.00 |
| Efectivo contado / efectivo esperado | $1,094.00 / $1,094.00 |
| Total real contado / esperado | $1,118.00 / $1,118.00 |
| Diferencia de efectivo / tarjeta / neta | $0.00 / $0.00 / $0.00 |

Caja y Cocina quedaron `closed`. No hubo pagos cancelados, descuentos, consumo de empleados, propinas, cambio ni comisión cobrada al cliente en esta sesión; esos casos quedan sin validar en esta Fase 6. La comisión de $0.96 fue absorbida y no cambió el monto de tarjeta cobrado de $24.

Caja Admin se observó desde la UI y mostró venta bruta $118, descuentos $0, efectivo $94, tarjeta $24 y diferencia de efectivo $0. **Backoffice Finanzas no se recorrió**: esa sección está disponible bajo `kIsWeb` y no forma parte de la app Android usada en esta corrida. Los datos persistidos del corte se leyeron desde el emulador, no equivalen a una validación UI de Backoffice Finanzas.

## Matriz solicitada

| Escenario | Estado | Evidencia/alcance |
|---|---|---|
| A: persona 1 efectivo, persona 2 tarjeta, persona 3 efectivo; parcial hasta el último pago | PASS | UI real y persistencia; montos 20/24/30, saldo final 0, 3 pagos activos, secuencia de folio 1, regreso a Mesas. |
| A: fallo del servicio de presencia después del pago | NO EJECUTADO | No se inyectó fallo del servicio. |
| B: terminales bajo sesión simultánea en dos tabletas | PARCIAL | Concurrencia de capturas sí; bloqueo por pago terminal demostrado con Rules Emulator. No se intentó desde cliente antiguo en tablet física/AVD posterior al cierre. |
| B: productos, cantidades y nuevos lotes rechazados al cerrar atómicamente | PASS (Rules Emulator) | Batch terminal + append rechazado; modificaciones posteriores de items/pagos rechazadas. No es recorrido Android con el cliente antiguo. |
| B: cobro legítimo y cancelación administrativa autorizada | PASS (Rules Emulator) | Prueba de pago final y de cancelación administrativa autorizada. |
| C: comanda enviada y cambios de Cocina reflejados en Mesas sin reentrar | PASS con corrección local | El antes falló y el después reflejó “Listo para cobrar” en el AVD que permaneció en Mesas. |
| C: todas las transiciones en vivo enviando/aceptando/preparando/parcial/lista/extra/liquidada/disponible | PARCIAL | Envío, extra, pasar platos, listo, pago y disponible observados; no se recorrieron todos los estados parciales enumerados. |
| D: validación de apertura false que después se vuelve true en Android | NO EJECUTADO | Sí hay cobertura widget automatizada; falta repetir la condición en la aplicación corriendo en AVD. |
| D: validación false→true y evento de nueva sesión | PASS (widget Flutter) | Se reproduce false transitorio de apertura/insumos; con la ruta montada, una revalidación acotada habilita Cocina cuando la apertura queda confirmada. Tras agotar el presupuesto, un nuevo evento de sesión vuelve a validar sin logout ni pulsar Reintentar. No es prueba física Android. |
| D: respuesta autoritativa antigua después del cierre de sesión de Cocina | PASS (widget Flutter) | Se retiene una respuesta `true`, se recibe después una señal nueva de sesión cerrada y luego llega la respuesta vieja; los botones siguen bloqueados. No es prueba física Android. |
| D: microcorte, reconexión de red y cambio de sucursal en Cocina | NO EJECUTADO en Android | Hay pruebas automatizadas del cambio de sucursal del stream y eventos confirmados; no se controló una interrupción de red en los AVD en esta corrida. |
| E: aceptar/rechazar solicitudes de cancelación desde UI en productos al final de comanda larga | NO EJECUTADO | No se crearon solicitudes ni se verificó físicamente el área de botones. |
| Captura local sobrevive cierre/reinicio Android sin autenticación offline | NO EJECUTADO | No se hizo reinicio con borrador local; no se alteró autenticación. |
| Dos AVDs con usuarios/dispositivos distintos envían a la misma orden | PASS | Acciones A y B iniciadas con diferencia menor a 100 ms; artículos/lotes/usuarios persistidos sin pérdida o duplicidad. |
| Cierre ficticio de Cocina y Caja por flujos normales | PASS | Ambos documentos `closed`, corte de Caja Admin y diferencias 0.00. |
| Backoffice Finanzas interpreta el mismo corte | NO EJECUTADO | No se recorrió interfaz web. |
| Descuentos, pagos cancelados, consumo empleado, cambio, comisión cobrada y demás ramas de conciliación | NO EJECUTADO | La sesión usada no contenía esos conceptos; no se inventaron operaciones solo para aparentar cobertura. |

## Validaciones automatizadas

- `flutter analyze`: PASS, sin issues.
- `flutter test`: PASS, **953/953** (repetida después del ajuste final de recuperación de Cocina).
- `npm run test:rules`: PASS, **137/137**, con Firestore Emulator local y guard `demo-*`.
- Rules exactas del candidato mínimo: pruebas dirigidas de marcador y terminales **9/9 PASS**.
- `git diff --check`: PASS después de consolidar esta documentación.

## Cambios locales propuestos

- `lib/core/orders/table_operational_status.dart`: un artículo listo ya no cuenta como “en preparación” por conservar un `cookingAt` histórico.
- `lib/screens/kitchen/kitchen_screen.dart`: reintenta de forma acotada una validación de apertura que responde false y descarta respuestas asíncronas antiguas cuando cambia la sesión/alcance confirmado. Las acciones siguen cerradas hasta una confirmación vigente.
- `test/kitchen_incremental_items_test.dart`: widget regressions para false→true automático, recuperación mediante nuevo evento de sesión después del presupuesto de reintentos y rechazo de una respuesta true tardía.
- `test/table_operational_status_test.dart`: regresión del estado listo con timestamps `cookingAt` y `readyAt`.
- `test/firestore-rules/local_order_capture_marker.rules.test.js` y `test/firestore-rules/order_terminal_protection.rules.test.js`: permiten pasar ruta de Rules candidata por variable de entorno; agregan cobertura del batch terminal y cancelación administrativa autorizada.
- `firestore.rules.production-candidate`: propuesta mínima de Rules; no desplegada.
- Evidencia de pantalla guardada en `evidence/`.

## Bloqueos para declarar Fase 6 cerrada

1. Repetir desde Android físico/AVD la matriz de validación de apertura false→true, respuestas tardías, cambio de sucursal y microcorte/reconexión; solo se ejecutaron ahora las pruebas widget de false→true y respuesta tardía.
2. Ejecutar Aceptar/Rechazar cancelación desde UI con comanda larga y varias solicitudes.
3. Demostrar que el borrador local persiste después de cerrar/reiniciar la app y luego puede enviarse.
4. Ejecutar Backoffice Finanzas en web contra el mismo corte ficticio y comparar su total/diferencia.
5. Completar casos financieros con descuento, cancelación, cambio, consumo empleado y comisión cobrada.
6. Respaldar commit en la rama remota de esta feature y volver a comprobar SHA/status remoto.

Hasta resolver esos puntos, el candidato no debe distribuirse de forma general.

## Addendum de cierre — 25 de noviembre de 2026

Este cierre parte de `e53d73358fbce258d63984ec44e7ca7be15b51b5` en `fix/tacopos-2.0.1-operational-stability`.

### Corrección de alcance del emulador Android

Durante la validación de cierre se detectó que la aplicación y la prueba de integración usaban por defecto `127.0.0.1:8080/9099/5001` desde el host Android, mientras que el stack dedicado de este worktree está en `127.0.0.1:8082/9101/5002`. Para evitar volver a cruzar los proyectos demo:

- `lib/main.dart` acepta puertos de Emulator explícitos, validados en debug y únicamente con proyecto `demo-*`.
- La integración de captura local usa los mismos defines y ahora tiene defaults coherentes con el stack convencional `8080/9099/5001`.
- Se agregó `integration_test/phase6_candidate_rules_android_test.dart` para consultar tablas y `collectionGroup('payments')` desde el SDK Android contra el stack candidato con puertos explícitos.
- La prueba de Rules ahora cubre explícitamente lectura por collection group y compatibilidad de escrituras con forma Android +31 antes y después de terminalizar una orden.

El contenido cargado en `demo-tacopos-2-0-1` fue leído desde `http://127.0.0.1:8082/emulator/v1/projects/demo-tacopos-2-0-1:securityRules`. SHA-256 del contenido devuelto: `732201CF7C3C8B553EC0E60749F251E3E1AFDAE210847F48A16637C60524DF2F`, idéntico al archivo `firestore.rules.production-candidate`.

La incompatibilidad previa de `collectionGroup` se debía a probar con otro snapshot de Rules que carecía del match global de lectura para `/{path=**}/payments/{paymentId}`. El candidato sí conserva dicho permiso de lectura para usuarios autenticados, y deniega escritura en ese match. No se omitió ni relajó una regla para hacer pasar las pruebas.

### Validación repetida en este cierre

- `npm run test:rules -- --reporter dot`, con guard de proyecto demo y Firestore Emulator local, usando `TACOPOS_RULES_FILE=firestore.rules.production-candidate`: **139/139 PASS**. Incluye `collectionGroup('payments')`, escritura legacy +31 sobre orden activa, rechazo de agregar artículo y reabrir orden terminal, captura local, cancelación administrativa y negativas de seguridad.
- `flutter analyze`: **PASS**, sin issues.
- `flutter test`: **953/953 PASS**.
- `integration_test/phase6_candidate_rules_android_test.dart`: **1/1 PASS** en `emulator-5564`, después de configurar el JDK para usar el truststore de Windows, manteniendo validación TLS.
- `flutter build apk --debug` con los defines explícitos del stack candidato: **PASS**; instalada con `adb install -r`. No se generó APK/AAB de release.
- `git diff --check`: PASS después de consolidar el addendum y las evidencias.

### Integración Android y bloqueo restante de la interfaz

El primer intento de `integration_test/phase6_candidate_rules_android_test.dart` en `emulator-5564` falló antes de instalar el test porque Gradle no confiaba en la cadena Maven (`PKIX path building failed`). El host Windows sí validó el certificado con su almacén del sistema; repetir Gradle con `-Djavax.net.ssl.trustStoreType=Windows-ROOT` resolvió el problema sin desactivar TLS ni cambiar repositorios.

La prueba Android **PASS 1/1**: inició Firebase Auth Emulator en `10.0.2.2:9101`, leyó las mesas de `aviacion` y ejecutó `collectionGroup('payments')` en Firestore Emulator `10.0.2.2:8082`, bajo el SHA candidato exacto. También se generó e instaló por `adb install -r` una APK **debug** del worktree con el proyecto y los puertos candidatos; no se desinstaló la aplicación. Se guardó captura y jerarquía UI del inicio de sesión en `evidence/`.

La integración Android prueba el SDK Firebase y las Rules, pero no el recorrido de TacoPOS. En la app principal debug se inició sesión por el flujo UI con el usuario ficticio Admin y se confirmó la sucursal `Aviacion`; al abrir Mesas, la pantalla mostró “No hay mesas registradas para esta sucursal”. En paralelo, Admin SDK y el test Android SDK leen cuatro mesas activas con `branchId=aviacion`, además de los cinco empleados activos. No se observó `PERMISSION_DENIED` concluyente para esa lectura en Logcat. Sí aparece una advertencia Firestore `RESOURCE_EXHAUSTED / too_many_pings` durante la corrida; no hay evidencia suficiente para afirmar que esa advertencia cause la lista vacía. Capturas y jerarquías están en `evidence/`.

La evidencia de interfaz anterior que no registró los puertos efectivos **no se considera evidencia de recorrido bajo el proyecto/Rules candidatos**. Las consultas Android SDK y las Rules Emulator son válidas para sus alcances, pero no sustituyen los recorridos UI pedidos.

### Estado actualizado de bloques solicitados

| Bloque / escenario | Estado al cierre | Evidencia o bloqueo |
|---|---|---|
| 1. SHA efectivo de Rules candidatas | PASS | REST del Emulator devuelve el mismo contenido y SHA que el archivo candidato. |
| 1. Compatibilidad `collectionGroup('payments')` | PASS | 139/139 en Rules Emulator y lectura desde SDK Android con Rules candidatas exactas. |
| 1. Forma de escrituras Android +31 y protección terminal | PASS (Rules Emulator) | Orden legacy activa permite captura/estado de Cocina; tras pago, nuevo artículo y reapertura son rechazados. |
| 1. Pago de tres personas, fallo de presencia, regreso a Mesas, intento Android +31/+32 después de liquidación, cancelación admin y captura concurrente bajo candidato exacto | NO DEMOSTRADO integralmente | Tests Rules cubren límites autorizados y denegados; la app autentica, pero Mesas no ve las mesas que sí devuelve el test SDK. Flujos de negocio detenidos sin crear órdenes. |
| 2. Cocina: microcorte, false→true, cambio de sucursal, respuestas tardías y acciones tras reconexión en AVD | NO EJECUTADO en UI | Las regresiones widget permanecen cubiertas por Flutter. La prueba Android SDK no incluye KitchenScreen; no se habilitaron acciones con datos provisionales. |
| 3. Solicitudes aceptar/rechazar en comanda extensa, varias cancelaciones y segunda tablet en Mesas | NO EJECUTADO bajo Rules candidatas | El recorrido de negocio no pasó del inicio de sesión; la prueba SDK no ejercita estas pantallas. |
| 4. Captura offline tras cierre/reinicio Android y envío exactamente una vez | NO EJECUTADO bajo stack candidato | No se reinició Android con un borrador operativo. La prueba de SDK no equivale al reinicio del sistema y recorrido UI completo. |
| 5. Conciliación exacta, cierre Caja/Cocina y lectura del mismo corte por Backoffice Finanzas | NO DEMOSTRADO para este stack | Los resultados de cortes documentados antes de corregir los puertos no se atribuyen al proyecto candidato. No se produjo nueva operación ficticia para reemplazarlos. |
| Regresión automatizada Flutter | PASS | `flutter analyze`; `flutter test` 953/953. |
| Rules completas del candidato | PASS | 139/139; emulador y guard `demo-*`/host local. |

### Dictamen

La Fase 6 **no queda cerrada**. No se autoriza preparar distribución del candidato: faltan recorridos UI críticos bajo el proyecto y SHA de Rules correctos, incluidos pago por personas, recuperación de Cocina, cancelaciones desde lista larga, persistencia offline después de reiniciar y conciliación con Backoffice Finanzas. El bloqueo de PKIX para Gradle ya fue resuelto de forma segura mediante `Windows-ROOT`. El bloqueo actual es la discrepancia reproducible entre la lectura de mesas desde SDK Android aislado y la lista vacía de Mesas en la app principal. Debe determinarse por qué difieren antes de ejecutar escrituras ficticias de operación; después, repetir sólo los escenarios aún no demostrados.

## Addendum 25 de noviembre de 2026 — discrepancia de Mesas y ejecución UI

### Causa raíz y corrección del entorno

La configuración Android debug (`android/app/src/debug/google-services.json`) apuntaba a `demo-tacopos-local-capture`, mientras la prueba de integración creaba una FirebaseApp nombrada para `demo-tacopos-2-0-1`. La aplicación usa Firebase `[DEFAULT]`, que Android inicializa desde `google-services.json`; por eso el test del SDK podía leer cuatro mesas del candidato mientras la aplicación consultaba otra base vacía. No era un filtro de sucursal ni evidencia de rechazo de Rules.

Se corrigieron solamente `project_id` y `storage_bucket` de la configuración **debug** para que apunten a `demo-tacopos-2-0-1`. Las opciones son valores demo con identificadores ficticios; `android/app/src/release/google-services.json` no se tocó. Se agregó a la integración Android una aserción sobre el proyecto de `[DEFAULT]` y una lectura de sus cuatro mesas, antes de conservar la lectura con la FirebaseApp independiente. El recorrido real mostró Mesa 1–4.

La instrumentación temporal de `main.dart`, `TablesScreen` y `watchTables` registró, con la misma app, autenticación, ruta y sucursal: `restaurants/main_restaurant/tables`, `branchId=aviacion`, cuatro documentos recibidos, cuatro convertidos, cuatro tras el filtro de sucursal y cuatro tras `activeOnly`. Hubo un snapshot de caché con `isFromCache=true`, `hasPendingWrites=false`, y después un snapshot confirmado con `isFromCache=false`, `hasPendingWrites=false`; una lectura `Source.server` devolvió los mismos cuatro documentos. La reconciliación revisó cero órdenes candidatas y no liberó ni cambió mesas. La instrumentación ya se retiró.

`RESOURCE_EXHAUSTED / too_many_pings` apareció en registros antiguos de una ejecución con configuración inconsistente. No apareció en la reproducción corregida; la app obtuvo los snapshots de caché y servidor con cuatro mesas. No hay evidencia de que ese aviso causara la lista vacía reproducida, ni se concluye que nunca pueda ser un problema separado.

### Preparación ficticia del emulador

Las sesiones anteriores de Caja y Cocina estaban cerradas. Se abrieron por sus pantallas normales para el 25-11-2026. Cocina se abrió desde Control de cocina tras ingresar 100 refrescos, 100 kg de lengua y 100 kg de tortilla como stock ficticio. Como la ruta debug Emulator omite `AppUpdateGate`, no crea por sí sola los documentos de registro de dispositivo requeridos por la callable. La primera llamada real a Enviar fue rechazada con `permission-denied: El dispositivo no esta registrado`; el borrador siguió visible y no se perdió. Para continuar se registraron únicamente dispositivos ficticios de los AVDs en `demo-tacopos-2-0-1` (sin cambiar Rules o Functions). El mismo borrador se reintentó desde la UI y el envío se confirmó.

### Escenarios ejecutados desde Android

| Escenario | Resultado | Evidencia y límites |
|---|---|---|
| Mesas con `[DEFAULT]` | PASS | Cuatro mesas visibles; caché y servidor coinciden. Captura y logs sanitizados bajo `evidence/`. |
| Abrir Cocina y procesar | PASS parcial | Se abrió la sesión desde UI. El pedido de tres tacos se vio en Cocina; `Siguiente plato` avanzó entre artículos y `Listo` dejó los tres `ready`. En la operación concurrente se procesaron ambos lotes adicionales mediante `Listo`. No se simuló microcorte ni cambio de sucursal. |
| Pago por tres personas | PASS | Total $74: persona 1 efectivo $24, persona 2 tarjeta $30, persona 3 efectivo $20. Se verificaron los tres pagos activos, orden `paid` y mesa disponible; la app regresó a Mesas al completar el último pago. No se inyectó fallo de `LivePresenceService`. |
| Captura concurrente | PASS | AVDs 5560/5562, Mesero A/B, enviaron casi simultáneamente sobre la misma orden. Firestore registró dos artículos de cantidad 1, dos empleados, dos batches/secuencias, total $54 y `captureRevision=2` después de las capturas; sin IDs duplicados ni líneas faltantes. El pedido se procesó en Cocina y se liquidó después con efectivo $54. |
| Dispositivo con borrador ante orden terminal | PASS parcial | El segundo AVD conservó un taco local sin enviar. Tras la liquidación desde el otro AVD, la UI indicó que la orden estaba cerrada, bloqueó enviarlo a esa orden y ofreció conservarlo en Comandas pendientes. Tras `adb reboot` sin limpiar datos, la app restauró esa advertencia. No se completó la recuperación/reasignación del borrador a una orden nueva; no se probó APK +31. |
| Caja/Cocina: conciliación y cierre | NO EJECUTADO | Se verificaron documentos activos y saldos antes del cierre. Las sesiones ficticias del 25-11-2026 siguen abiertas; no se verificó el mismo corte desde Backoffice Finanzas. |
| Cancelaciones, varias solicitudes y UI larga | NO EJECUTADO | No se solicitó ni resolvió cancelación de producto en la UI durante este addendum. |
| Cocina offline, reconexión, validación inicial false→true, sucursal y respuestas obsoletas | NO EJECUTADO | El snapshot de caché inicial tenía las cuatro mesas; no se sometió Cocina a pérdida de red ni carrera de validaciones. |
| Compatibilidad terminal con Android +31 | NO EJECUTADO | Los AVDs +31 no se instalaron/ejecutaron contra el candidato; no se infiere compatibilidad por el test de Rules. |
| Integración SDK Android: app principal y named app | PASS | `flutter test integration_test/phase6_candidate_rules_android_test.dart -d emulator-5564` con defines del proyecto/puertos correctos pasó 1/1. El test ahora verifica que `[DEFAULT]` corresponda al candidato y lea las cuatro mesas; la app nombrada sigue validando Rules, empleados y `collectionGroup('payments')`. |

Las evidencias de Android/Firestore son solo del proyecto `demo-tacopos-2-0-1`; los IDs de pedidos y sesiones corresponden a datos ficticios. La primera apertura de la app con la configuración equivocada llegó únicamente a Auth Emulator y a una reconciliación que no encontró órdenes ni tocó mesas; no se hizo ninguna operación de negocio en ese otro demo. No se consultó ni escribió producción.

### Dictamen actualizado

La causa de la pantalla Mesas vacía quedó demostrada y el arreglo de **entorno debug** está integrado en una prueba Android dirigida. Se validaron desde UI pagos por persona, captura concurrente, envío y acciones `Siguiente plato`/`Listo`, además de la protección de borrador ante una orden terminal. La **Fase 6 no queda cerrada**: faltan conciliación/cierre normal de Caja y Cocina con lectura desde Backoffice Finanzas, cancelaciones de lista larga, recuperación de Cocina bajo cortes y cambios de sucursal, recuperación/reenvío del borrador después del reinicio a una orden abierta y compatibilidad UI de +31. No autorizar preparación del release hasta completar esos bloqueos.

### Seguimiento del 25 de noviembre — intento de cierre normal de Cocina

Se retomó la sesión ficticia desde la pantalla normal de Control de cocina en el AVD `emulator-5564`. `Cerrar cocina` abrió el formulario de conteo final. Durante la captura de los conteos, Android mostró el diálogo del sistema **“TacoPOS isn't responding”**. La evidencia está en `evidence/phase6-kitchen-close-attempt-anr.png` y `evidence/phase6-kitchen-close-attempt-anr.xml`.

No se pulsó confirmar cierre ni existe evidencia de que se haya enviado/escrito el cierre; por tanto, este intento **no cuenta como cierre** y no se afirma que Cocina o Caja hayan quedado cerradas. El ANR impidió continuar de forma segura por el flujo UI. No se usó Admin SDK para cerrar sesiones ni se modificaron datos fuera de las operaciones de UI autorizadas. La sesión de Caja/Cocina y la conciliación con Backoffice Finanzas quedan pendientes. No se repitieron pruebas automatizadas ya aprobadas.

### Follow-up: ANR trace and emulator resources (25 November 2026)

The recovered `dumpsys activity lastanr` entry timestamps the ANR at 10:44:44 and gives the reason as a 5,021 ms input-dispatch timeout while `MainActivity` awaited a synthetic `KEYCODE_CTRL_LEFT`. This key was injected by the test automation (`adb input keycombination KEYCODE_CTRL_LEFT KEYCODE_A`) while trying to replace a numeric field. That is the demonstrated trigger; the evidence does not identify a Flutter frame, Firestore request, or close-session transaction as the cause. Android had a trace at `/data/anr/anr_2026-11-25-10-44-44-233`, but `adb pull` was denied to the shell user, so no main-thread stack was recovered.

Later resource snapshots showed 3.2% aggregate guest CPU over 10:48:41–10:53:41, app PSS 285,685 KB/RSS 380,784 KB, and 762,052 KB guest memory available. These readings are after the ANR. During subsequent host-side probes, Windows reported 267,164 KB available out of 16,249,784 KB; this indicates host memory pressure then, but does not prove pressure at 10:44. Firestore `too_many_pings` warnings occurred later at 10:52:24 and 10:55:24, so they do not explain the earlier input-dispatch timeout based on available chronology. Evidence: `evidence/phase6-kitchen-close-anr-analysis.txt`.

No product code was changed. The close form was not submitted. The closure remains unvalidated; retry it on one clean AVD with adequate host memory and without synthetic control-key events.

### Infrastructure reset and execution gate (25 November 2026)

Before further business UI tests, the running processes and AVD names were inventoried. Only the three AVDs explicitly named for TacoPOS 2.0.1 phase 6 were shut down normally with `adb emu kill`: `TacoPOS_201_B` (5562), `TacoPOS_201_Phase6_B` (5566), and `TacoPOS_201_Phase6_A` (5564). No `-wipe-data` or app-data clearing was used. The generic `Medium_Phone_API_36.1` (5554) and `Pixel_6` (5556) were left running because their ownership could not be proven. The separate `demo-tacopos-local-capture` emulator suite was also left untouched.

The active candidate emulator was verified read-only as project `demo-tacopos-2-0-1`, with Auth 9101, Firestore 8082, and Functions 5002. Firestore returned Rules source text identical to `firestore.rules.production-candidate`; both SHA-256 values are `732201CF7C3C8B553EC0E60749F251E3E1AFDAE210847F48A16637C60524DF2F`. The candidate process uses `.firebase-phase6-production-candidate.json`; `firebase.json` default ports are not the effective ports. Exact process/AVD inventory is in `evidence/phase6-infrastructure-inventory-2026-11-25.txt`.

After stopping the three TacoPOS test AVDs, free memory was measured at several points. The highest sample was 3,008 MiB, below the 3,072 MiB launch threshold; the latest sample is 2,881 MiB (191 MiB short). A guarded attempt to start `TacoPOS_201_Phase6_A` was refused before launch. No AVD was restarted and no new UI/business scenario was run. The next operational validation is blocked until at least 191 MiB more host free memory is available, with additional headroom recommended, while keeping unrelated generic AVDs and the separate emulator suite untouched. No pending device data was wiped.

### Seguimiento: escenarios operativos pendientes ejecutados (25 de noviembre de 2026)

La autorización posterior permitió continuar sin exigir el umbral orientativo de 3 GiB. Se utilizó un solo AVD (`TacoPOS_201_Phase6_A`, `emulator-5564`), apagado normalmente al finalizar, sin wipe ni limpieza de datos. Proyecto exclusivo: `demo-tacopos-2-0-1` (Auth 9101, Firestore 8082, Functions 5002). El SHA activo de Rules fue `732201CF7C3C8B553EC0E60749F251E3E1AFDAE210847F48A16637C60524DF2F`, igual a `firestore.rules.production-candidate`. La suite separada `demo-tacopos-local-capture` fue detenida preservando su export. No hubo acceso/escritura a producción, deploy, build, cambio de versión ni AAB.

| Escenario | Resultado | Evidencia / observaciones |
|---|---|---|
| Comanda extensa: aceptar y rechazar cancelación desde Cocina, incluyendo últimos renglones | PASS | La UI aceptó cancelar el taco pastor final y rechazó la solicitud del taco lengua final. Firestore persistió 1 artículo cancelado y 8 activos; la aceptación redujo el total de $222 a $202; el artículo rechazado permaneció activo. `phase6-kitchen-cancel-detail.xml`, `phase6-kitchen-cancel-reject-detail.xml`, `phase6-kitchen-after-accept.xml`, `phase6-kitchen-reject-confirm.xml`. |
| Siguiente plato y Listo después de las cancelaciones | PASS | La UI avanzó el plato/persona y marcó Listo; Firestore confirmó 8 activos `ready`, 1 `cancelled`, orden `ready`. `phase6-kitchen-after-next.xml`, `phase6-kitchen-after-ready-person3.xml`. |
| Microcorte y recuperación de botones de Cocina | PASS | Sin red, la UI informó caché no confirmada y deshabilitó Siguiente plato. Al restaurarla, pasó a sincronizado con servidor y habilitó la acción. No requirió logout/reentrada. `phase6-kitchen-offline.xml`, `phase6-kitchen-reconnected.xml`. No se ejercitó cambio de sucursal ni carrera de respuesta antigua. |
| Borrador local después de reiniciar Android y envío exactamente una vez | PASS | Captura de nueve tacos para tres personas; se desconectó la red, se cerró y reinició el AVD y se volvió a iniciar sesión. El primer envío falló por falta de registro ficticio del dispositivo, sin borrar el borrador. Tras registrar ese dispositivo sólo en Emulator, el mismo borrador se envió por UI: 9 artículos (3 asada, 3 lengua, 3 pastor), un batch/marker, total $222 y `captureRevision=1`, sin duplicados ni faltantes. `phase6-after-reboot-order.xml`, `phase6-reboot-send-result.xml`, `phase6-after-reboot-send-attempt.xml`. |
| Descuento, comida de empleado, cancelación de pago, cambio y comisión de tarjeta | PASS para modalidades ejercidas | UI registró comida de empleado como beneficio/descuento de $100; descuento familiar $10 sobre base $50; efectivo recibido $60, cambio $8 y pago $52. En otra mesa, un pago parcial en efectivo de $10 se canceló por UI, conservando auditoría y excluyéndose de pagos activos; luego se cobró $24 con tarjeta. Comisión de tarjeta absorbida $0.96 para ese pago, sin recargo al cliente. `phase6-after-employee-meal-payment.xml`, `phase6-family-discount-applied.xml`, `phase6-full-cash-change.xml`, `phase6-after-cancel-payment.xml`, `phase6-mesa3-card-payment.xml`. El movimiento distinto de consumo de empleado no se ejecutó: el caso realizado fue comida de empleado contabilizada como descuento. |
| Cierre normal de Cocina | PASS | Se cerró por Control de cocina UI; sesión ficticia del 25-11-2026 persistida `closed`. Conteos finales introducidos desde UI. `phase6-kitchen-close-result.xml`, `phase6-kitchen-closed.xml`. |
| Cierre normal de Caja | PASS | Se cerró desde Caja/Corte UI, efectivo contado $190 y tarjeta terminal $54. La sesión `fjtfQ1ns5hZjaQyDw3UF` quedó `closed`; esperado/contado $190/$54, diferencia de efectivo y tarjeta, faltante y sobrante: $0.00. `phase6-cash-close-current.png`, `phase6-cash-closed.xml`. |
| Mismo corte en Backoffice Finanzas | PASS | Backoffice web local contra el mismo Emulator, sucursal Aviación, fecha 25-11-2026. Mostró venta bruta $354, descuentos $110, venta neta $244, ingreso/monetario esperado $241.84, comisiones absorbidas $2.16, faltantes $0 y sobrantes $0. Coincide con Caja Admin y pagos persistidos. `phase6-backoffice-finance-today-results.png`, `phase6-backoffice-finance-lower-results.png`, `phase6-cash-admin-report-current.png`. |
| Compatibilidad Android +31 y +32 con Rules candidatas | NO EJECUTADO | No hay APK +31/+32 en este worktree ni se instaló cliente anterior en el único AVD. El cliente probado fue el debug de 2.0.1; test de Rules no demuestra compatibilidad de APKs reales. No se generaron builds antiguos. |
| Movimiento independiente de consumo de empleado | NO EJECUTADO | Se verificó la comida/beneficio de empleado de $100 como descuento. El movimiento independiente de consumo sigue sin validarse. |

#### Conciliación del corte ficticio

Lectura de pagos de la sesión cerrada: 9 documentos, 8 activos y 1 cancelado; base/venta bruta activa $354; descuentos $110; neto activo $244; efectivo $190; tarjeta $54; recibido en efectivo $198; cambio $8; comisión de tarjeta absorbida $2.16; recargo de tarjeta $0; descuento de comida de empleado $100. El pago cancelado de $10 se excluyó. Caja Admin y Backoffice Finanzas coincidieron: $190 + $54 = $244; menos $2.16 de comisión absorbida = $241.84 de ingreso disponible; diferencia $0.00.

#### Dictamen actualizado

Los escenarios pendientes de cancelación larga, progreso/recuperación de Cocina, persistencia y reenvío tras reinicio, cierres normales y conciliación con Backoffice quedaron demostrados con la interfaz real y datos exclusivamente ficticios. No se demostró un defecto que requiera modificar el producto en estos recorridos. La Fase 6 **aún no se considera cerrada**: falta probar APKs reales +31/+32 con las Rules candidatas y falta el movimiento independiente de consumo de empleado. No se autoriza distribución general hasta cerrar esos dos puntos o hasta que el propietario retire formalmente uno de los criterios de aceptación.

### Addendum — Sesion del empleado y diagnostico de rendimiento (25 de noviembre de 2026)

Se implemento persistencia segura de identidad de empleado/sucursal (sin PIN ni token), revalidacion autoritativa, recuperacion transitoria y registro local ligero consultable por Administracion. El registro mide CPU/PSS/RSS, RX/TX por UID Android, frames lentos, listener attach/cancel, documentos de snapshots, fuente cache/servidor, y duracion de persistencia/cola/envio. No envia telemetria a Firebase ni cambia Rules/Functions. Detalle y limites en `DEVICE_PERFORMANCE_INCIDENT.md`.

El ensayo Android de 30 minutos en Mesas termino con el proceso y la sesion sin cambios. Reinicio online y test de token-refresh/lifecycle conservaron empleado/sucursal; unit tests cubren logout voluntario, revocacion, permisos y fallos transitorios. El intento adicional de reinicio offline no se cuenta: el runner de integracion habia desinstalado la app y no habia Activity; se retiro su XML de launcher para no presentarlo como evidencia. Solo hay un AVD disponible; la tablet fisica de Andres no esta conectada.

En AVD, la instrumentacion se verifico y sobrevivio `force-stop`; la muestra de proceso es baseline del emulador y no representa trafico celular. Codigo confirma consultas historicas globales de `orders` en Mesas/Cocina/Para llevar/Parados, pero no hay evidencia suficiente para atribuirles la lentitud exclusiva ni el cierre de sesion reportado. La causa de produccion permanece INDETERMINADA hasta comparar la tablet afectada con una sana.

**Bloqueos vigentes de Fase 6:** compatibilidad UI historica +31/+32 y movimiento independiente de consumo de empleado. Ambos siguen pendientes. La Fase 6 no queda cerrada.

Validacion final de la instrumentacion: `flutter analyze` PASS; `flutter test` PASS (1066/1066); Cocina incremental PASS (32/32); diagnosticos y sesion PASS (14/14); `git diff --check` PASS. Se corrigio el conteo de documentos para usar `snapshot.docs.length`; el uso de `snapshot.size` hacia fallar los doubles de Firestore y marcaba los snapshots de Cocina como errores permanentes.


### Addendum Fase 6.1 (26 de noviembre de 2026)

El detalle de la revisión de proyecto/Rules, restauración Android, artefactos históricos, suites finales, pendientes y limitaciones del AVD está en [PHASE_6_1_ADDENDUM.md](PHASE_6_1_ADDENDUM.md). La Fase 6 sigue abierta: no se ejecutaron compatibilidad +31/+32, consumo independiente de empleado ni rendimiento sostenido de 2,001 órdenes.
