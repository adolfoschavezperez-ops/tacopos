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
