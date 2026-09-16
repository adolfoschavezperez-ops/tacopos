# Android: total autoritativo al entrar a Cobrar

Fecha: 2026-09-16. Rama: `fix/android-authoritative-total-on-payment`.
Base: `3c3fb55`. Versión durante la auditoría: **1.5.9+26**.
El cierre posterior autorizado para **1.5.10+27** se documenta en
[el reporte de release](android-release-1.5.10-27.md).

## Auditoría previa

En HEAD, `lib/screens/waiter/order_screen.dart`, `_OrderSummaryState.build`
(líneas originales 1319–1340), mostraba una columna con `Text('TOTAL')` y
`MoneyText(value: widget.order.total)`. Era el total bruto del documento de la
orden recibido por `watchOrder`, no `netTotal` ni una suma de la cola optimista.

Los artículos se actualizan visualmente con `OrderCaptureState`, mientras las
escrituras se serializan en la instancia existente de `OrderCaptureQueue` del
repositorio. `recalculateOrderTotal` actualiza el documento cuando termina la
cola. Por ello, el encabezado podía conservar el total anterior durante una
ráfaga. Además, el total bruto podía diferir del neto o saldo de Cobro.

Cada persona tenía otro `MoneyText(value: subtotal)`, alimentado por un
`fold` local de `item.total` de artículos no cancelados. Esa suma sí podía
incluir artículos optimistas todavía sin persistir.

Al iniciar esta tarea ya había cambios locales en `order_screen.dart` y
`order_screen_cleanup_static_test.dart` que retiraban ambos importes. Se
conservaron y completaron.

**Ya existía revalidación al entrar a Cobrar:** `_openPayment` esperaba
`flushPendingMutations` y `prepareOrderForCheckout`; la navegación entregaba
únicamente `orderId`, nunca el importe visual. Sin embargo:

- El manejador no tenía guarda interna contra doble toque.
- La cola absorbía errores de escritura para continuar; `flush` no los conocía.
- `flush` esperaba una referencia a la cola que podía cambiar mientras esperaba.
- Las lecturas de checkout permitían recurrir a caché.
- PaymentScreen podía construir el resumen mientras artículos/pagos aún
  cargaban, usando listas vacías; también aceptaba snapshots iniciales de caché.

## Resultado y fuente del total

| Comportamiento | Antes | Después |
| --- | --- | --- |
| Total de orden visible en captura | Sí, `order.total` | No |
| Subtotal por persona visible en captura | Sí, suma local | No |
| Precios del menú y montos de renglón | Visibles | Conservados |
| Fuente del resumen de Cobro | Documento de orden y pagos por streams, con posibles datos de caché/listas pendientes | Documento, artículos y pagos confirmados por servidor, después de flush y preparación |
| Fórmulas de cobro | Funciones canónicas existentes | Las mismas |

Se retiró la columna `TOTAL` completa, el subtotal de `_PersonItemsCard`,
su parámetro y los separadores asociados. Se conservaron encabezado, personas,
cantidades, notas, extras, estados y botones.

Secuencia final de `_openPayment`:

1. Comprueba permiso, bloquea doble toque y fija el ID de la operación.
2. Bloquea captura durante la entrada a Cobro y muestra el indicador existente.
3. Espera `flushPendingMutations`: todas las escrituras de la orden y su
   reconciliación; si aparece otra escritura durante la espera, continúa drenando.
4. Ejecuta `recalculateOrderTotal` con `Source.server`. Usa exactamente
   `activeOrderItemsTotal` y `reconcileOrderPayments`, sin fórmula nueva.
5. Ejecuta `prepareOrderForCheckout` con lecturas `Source.server` de orden,
   artículos, pagos y configuración de descuento general. Conserva la
   validación de cocina y las reglas existentes para descuentos/pagos previos.
6. Relee la orden mediante `getOrderOnce(..., source: Source.server)`.
7. Comprueba que la pantalla siga montada, activa y ligada a la misma orden.
8. Abre PaymentScreen por `orderId`. Sus streams rechazan caché y escrituras
   locales sin confirmar, incluyen cambios de metadatos y esperan artículos
   y pagos antes de construir cualquier importe.

El resumen conserva `_checkoutAccountTotals` →
`calculateCheckoutAccountTotals` / `checkoutAppliedPaymentAmount`. Mesa,
persona, selección, parcialidades, descuentos y métodos de pago mantienen
sus manejadores y semántica existentes.

La reconciliación explícita de servidor agrega trabajo al entrar a Cobrar;
la captura mantiene su optimización de recalcular al terminar cada ráfaga.
Los parámetros nuevos del repositorio conservan sus valores predeterminados
para los demás consumidores.

## Fallos y reintento

La misma cola conserva errores para que `flush` pueda propagarlos; no se creó
otra cola. La reconciliación en segundo plano tampoco relanza errores sin
manejador ni entra en reintentos infinitos. Un fallo de escritura, flush,
reconciliación, preparación o lectura impide navegar y muestra
`No se pudo validar el total: ...`. El usuario puede reintentar Cobrar; se
valida lo realmente persistido. Una escritura fallida no se vuelve a insertar
automáticamente ni se inventa un monto.

El bloqueo nuevo de captura aplica exclusivamente a la entrada a Cobro;
no modifica el envío a cocina. No se modificaron secuencias, lotes, stockouts,
reglas de descuentos, redondeos, comisiones ni liquidación de pagos.

## Pruebas y validación

- **97 pruebas dirigidas aprobadas**: grupo de 92 pruebas de cola, UI,
  beneficios, descuentos, persistencia y guardas; otras 5 del repositorio y
  selección de fuente.
- **Suite completa: 764 pruebas aprobadas.**
- `dart format lib test`: correcto; ningún cambio de formato fuera del alcance.
- `flutter analyze`: sin incidencias.
- `flutter build apk --debug`: correcto. APK local en
  `build/app/outputs/flutter-apk/app-debug.apk`.

Cobertura nueva:

| Caso | Evidencia |
| --- | --- |
| A/B: captura antes/después de agregar | Pruebas widget, sin total general ni de persona; precios conservados |
| C: Cobrar con cola vacía | Orden de llamadas y total $100 en PaymentScreen |
| D/E: último producto y Cobrar inmediato | Prueba widget y de cola: $100 + $30 + $40 + $20 = $190; doble toque abre una sola pantalla |
| F/I: parcial, efectivo/tarjeta, persona | Saldos $70 y $50; pagos previos no tratados como lista vacía |
| G: Employee 30, Partner 50, Family/Friend | Resumen con reconciliación canónica, además de suites existentes de descuentos |
| H: free meal | Gratuito completo y gratuito parcial con saldo pendiente |
| J: fallos | Escritura/reconciliación en cola y fallos de flush, preparación o lectura; no navega; reintento explícito |
| Cambio remoto anterior a Cobrar | Documento visual $100, artículos remotos $175: checkout muestra $175 |
| Fuente de datos real del repositorio | Reconciliación lee servidor para artículos, orden y pagos; $190 menos $30 pagados = $160 pendientes |
| Snapshots antiguos | Cobro rechaza caché y pending writes; captura conserva sus snapshots optimistas |

Las pruebas widget ejecutan OrderScreen y PaymentScreen con un repositorio
controlado y las funciones canónicas reales. Las pruebas de fuente ejecutan
TacoPosRepository con un límite Firestore simulado. No se conectaron a Firebase
productivo ni se realizaron cobros reales. No se probó en dispositivo físico
ni una carrera simultánea entre dispositivos reales.

Los tamaños widget verificados son 412×915 y 1280×720. Una exploración con
el menú a 1280×900 mostró desbordamiento de tarjetas con la tipografía de
pruebas; el diseño de esas tarjetas queda fuera de este cambio y no se alteró.

Logs locales: `.dart_tool/order_payment_targeted_test.log`,
`.dart_tool/order_payment_full_test.log`, `.dart_tool/order_payment_analyze.log`,
`.dart_tool/order_payment_format.log`, `.dart_tool/order_payment_debug_build.log`.

## Archivos modificados

- `lib/screens/waiter/order_screen.dart`
- `lib/screens/waiter/payment_screen.dart`
- `lib/core/orders/order_capture_queue.dart`
- `lib/services/taco_pos_repository.dart`
- `test/order_screen_cleanup_static_test.dart`
- `test/order_capture_queue_test.dart`
- `test/order_payment_entry_widget_test.dart` (nuevo)
- `test/checkout_server_source_test.dart` (nuevo)
- `pubspec.yaml` / `pubspec.lock`: `firebase_core_platform_interface` se declaró
  dependencia directa solo de desarrollo para los mocks de Firebase; ya estaba
  resuelta en 8.1.0 y no se actualizó ningún paquete.
- Este reporte.

**TOTAL DEFINITIVO SE MUESTRA ÚNICAMENTE EN COBRO = SÍ**, para el flujo auditado.
**ORDER SCREEN NO MUESTRA TOTAL = SÍ.**
**COBRAR ESPERA MUTACIONES PENDIENTES = SÍ.**
**TOTAL DE COBRO USA ESTADO AUTORITATIVO = SÍ.**
**FÓRMULAS MODIFICADAS = NO.**

Al terminar la auditoría inicial se conservó `1.5.9+26`, sin archivos de
Backoffice modificados y sin commit, merge, publicación, AAB, release,
Play Store ni Firebase deploy. El cierre posterior sigue la autorización
registrada en el reporte de release.
