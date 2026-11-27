# TacoPOS 2.0.1 — Fase 6.4: evidencia y cierre de pendientes

Fecha: 26 de noviembre de 2026. Rama: `fix/tacopos-2.0.1-operational-stability`. Base: `911b4241ed08567e917e8ca57c837ea018244bdd`.

## Alcance y entorno

Se usó exclusivamente el proyecto aislado `demo-tacopos-2-0-1`, Firestore Emulator `127.0.0.1:8183` y Auth Emulator `127.0.0.1:9198`. El contenido cargado de `firestore.rules.production-candidate` se verificó con SHA-256 `732201CF7C3C8B553EC0E60749F251E3E1AFDAE210847F48A16637C60524DF2F`. No se accedió a producción, ni se desplegó, cambió versión o modificó Rules.

El APK +31 reconstruido desde `6b638e154921eb223134dee5fa5f35b0fee57f08` y el APK +32 reconstruido desde `1c660da74c54cd87495b26c2698d3808a0bb638d` son builds debug de prueba, no los binarios originales distribuidos por Google Play. Se utilizó un solo AVD a la vez; no fue posible completar la vuelta de +32 a +31 porque el AVD +31 volvió a quedar no responsivo. El producto de prueba `phase64-test-taco-30` es un fixture sintético sin efecto de inventario.

## Matriz de ejecución

| Escenario | Estado | Evidencia / alcance |
|---|---|---|
| +31 crea una orden de Mesa, agrega una unidad y la envía | PASS | UI real. Orden `b5j0Mrdibo0mWO6NuF57`, una unidad de $30, un artículo y batch `0BZwehtyP5IFuIscSGST`. |
| +32 observa la orden creada por +31 y procesa Cocina | PASS | UI real de +32 mostró la orden. Se pulsó `Listo`; lectura posterior, de solo lectura, confirmó orden/artículo `ready`, cantidad 1, mismo batch y mesa ocupada. |
| +32 crea una orden, captura y envía por captura local | PASS | UI real. Orden `q94L0G6lVNQ4ViVeQPbk`, un artículo de $30, un batch `H7OaHfesimJjuOVcF94Y`; no se observaron duplicados. |
| +32 procesa su propia orden hasta `ready` | PASS | UI real con estado confirmado previamente. Después del toque se vio un estado provisional transitorio; la vista regresó a sincronizada y cero comandas activas. Lectura del emulador confirmó una unidad `ready`, sin cambios de secuencia o batch. |
| +32 creada → +31 lectura/operación | NO EJECUTADO | La segunda sesión del AVD +31 quedó no responsiva. No se inició un segundo AVD. |
| Agregar artículos, cobrar, cancelar operaciones y orden legacy durante convivencia +31/+32 | NO EJECUTADO en esta corrida | La compatibilidad demostrada es solo creación/envío +31, lectura y surtido +32, más creación/envío/surtido +32. Los resultados de cobros y Rules de otras fases son evidencia independiente y no equivalen a esta matriz cruzada. |
| Candidato actual TacoPOS 2.0.1 en UI cruzada | NO EJECUTADO | No se sustituyó el APK histórico en el AVD ni se confundió el APK histórico +32 con el candidato. |
| Sesión financiera combinada (fondo, efectivo, tarjeta, beneficio 100%, descuento 30%, consumo independiente, reintento y cierre) | NO EJECUTADO | No se registraron pagos ni movimientos financieros nuevos en esta corrida; por ello no existe conciliación esperada/real ni diferencia que declarar. El consumo independiente de $100 ya consta como prueba separada en 6.3, pero no satisface esta sesión combinada. |
| Respuesta perdida tras persistir consumo independiente y reintento lógico original | NO EJECUTADO | No se inyectó ni simuló una respuesta perdida después de un commit de consumo. Los tests de idempotencia de solicitudes de gastos no demuestran este protocolo financiero. |

Las órdenes sintéticas de la corrida quedaron abiertas con saldo pendiente de $30 cada una, aunque Cocina quedó `ready`. Se conserva este estado en el Emulator para no falsear un cierre financiero que no se ejecutó. El sistema del AVD volvió al día 26 después del reinicio mientras las órdenes se crearon bajo `businessDate=2026-11-27`; este detalle se debe considerar si se retoma el flujo normal de cierre.

Los XML de UI y el resumen de estado de Firestore se guardan en `evidence/phase64-*`. Firestore se inspeccionó con Admin SDK conectado explícitamente al Emulator, en lectura; las operaciones de negocio de órdenes se hicieron desde la UI. El SHA de Rules y los datos de las dos órdenes están en `evidence/phase64-cross-version-server-state.json`.

## Rendimiento, conversiones y listeners

Se ejecutó `flutter test test/kitchen_incremental_items_test.dart test/employee_benefit_reconciliation_test.dart test/canonical_sales_summary_test.dart test/operational_diagnostics_service_test.dart`: **82/82 PASS**. Dentro del fake de Firestore, la prueba de conversión valida carga inicial de 2,001 documentos y una actualización incremental que convierte el documento modificado; Cocina aplica la misma estrategia. También recorre cambios de estado, estado cache/provisional, error transitorio, cancelación y reentrada del feed. Es evidencia de lógica mediante fake/widget test, no una medida runtime del SDK Firestore Android.

El archivo local de diagnósticos del APK histórico +32 contiene 118 eventos acumulados, 31 callbacks de `tables_open_orders_snapshot` con `documents=2001` y 2 attaches. Esa versión no emitió `convertedDocuments`; no se infiere de ella el costo de conversiones del candidato. En el candidato actual el código instrumenta `convertedDocuments` en Mesas y Cocina, y el test dirigido verifica esos contadores, pero no se extrajo una muestra de un APK candidato ejecutándose en el AVD. Por ello, las conversiones directas runtime del candidato siguen **pendientes**.

La evidencia de memoria T0/T5/T15/T30 existente permanece en `PHASE_6_3_ADDENDUM.md`; no se repitió. Sus condiciones baseline/candidato no son totalmente equivalentes y no sustentan una reducción de lecturas facturables, bytes de red, CPU o RAM atribuible al candidato. Se conserva el hallazgo previo de dos listeners legítimos de Mesas (mesas y órdenes abiertas); esta corrida no cubrió navegación, pausa/reanudación ni reconexión del candidato para certificar que no se acumulen.

## Validación de código

- `flutter test` dirigido: **82/82 PASS**.
- `flutter analyze`: no ejecutado; no hubo cambios de código productivo.
- Suite completa Flutter, Firestore Rules y Functions: no repetidas porque el código no cambió y no aportaban evidencia a los escenarios UI pendientes.
- No se ejecutó inyección de fallo ni integración financiera en esta corrida.

## Dictamen

**NO-GO — Fase 6 permanece abierta.** La compatibilidad cruzada queda demostrada parcialmente para envío de +31 y recepción/surtido en +32; no están demostradas la dirección inversa, los cobros/cancelaciones cruzados ni la convivencia con el candidato 2.0.1. Faltan la conciliación financiera combinada, el reintento tras respuesta perdida con commit previamente confirmado, y los contadores de conversiones recogidos directamente en runtime del candidato. No hay evidencia de defecto financiero en esta corrida, pero tampoco base para declarar esos controles aprobados.

No se modificó producto. La próxima ejecución debe retomar los casos faltantes en el Emulator con fecha operativa consistente, instrumentación exportada desde el candidato actual, un mecanismo de fallo que confirme persistencia antes de descartar la respuesta y una sesión financiera ficticia cuyos importes esperados se fijen antes de operar. Esto no autoriza Fase 7, release, deploy ni publicación.
