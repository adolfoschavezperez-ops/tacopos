# TacoPOS 2.0 — validación financiera de cierre

Fecha de revisión: 2026-11-24
Resultado: **BLOQUEADO; no se cerró la caja de prueba**.

## Entorno y fuente

- Firebase usado: `demo-tacopos-local-capture`.
- Firestore Emulator: `127.0.0.1:8080`; Auth Emulator: `127.0.0.1:9099`; Functions Emulator: `127.0.0.1:5001`.
- Android Emulator `emulator-5554`, interfaz administrativa de TacoPOS.
- La inspección de documentos usó Firebase Admin SDK apuntando explícitamente al proyecto demo. No se consultó ni modificó Firebase productivo.
- Rama `feature/durable-local-order-capture`, commit `a35c186a24b4ba2ee9ba46c8de27c8f063671a4e`; el commit coincidía con `origin` al momento de la inspección.
- Evidencia visual: [resumen administrativo de caja abierta](evidence/tacopos-2-financial-close-open-session-2026-11-24.png).

## Sesión inspeccionada

Documento: `restaurants/main_restaurant/cashSessions/6RdAyg1nUwoveO70zWSq`
Sucursal: `aviacion`; fecha operativa: `2026-11-24`; estado: `open`.

La sesión contiene 13 pagos: 12 activos y 1 cancelado. Los importes guardados en los campos del corte siguen en cero porque el cálculo se persiste durante el cierre; no se escribieron valores de corte ni se cambió el estado de la sesión.

### Reconciliación actual de pagos

| Concepto | Importe | Evidencia |
|---|---:|---|
| Efectivo aplicado activo | $1,022.00 | Pagos `cash` activos |
| Efectivo recibido | $1,058.00 | Incluye el efectivo entregado antes del cambio |
| Cambio entregado | $36.00 | La diferencia recibido menos cambio es $1,022.00 |
| Tarjeta activa según `chargedAmount` | $224.00 | Cuatro pagos activos de tarjeta |
| Tarjeta esperada en el resumen administrativo | $208.00 | Visible en la pantalla de la app; el cálculo canónico interpreta como neto una prueba histórica bruta con descuento |
| Comisión absorbida registrada | $8.96 | 4% de los importes base de tarjeta registrados ($80, $64, $20, $60) |
| Recargo cobrado al cliente | $0.00 | Los cuatro pagos registran `surchargeAmount: 0` |
| Consumo de empleado | $48.00 | Método separado; no suma al efectivo ni a la terminal |
| Pagos cancelados | $20.00 | Un pago en efectivo con estado `cancelled`; excluido de los totales activos |
| Fondo inicial / retiros | $0.00 / $0.00 | Sin fondo ni solicitudes de retiro en esta sesión |

El método de cierre del repositorio excluye pagos cuyo estado no sea `active`. La vista administrativa del Emulator también muestra efectivo $1,022, tarjeta $208, comisión absorbida $8.96 y consumo de empleado $48. Esos valores son coherentes con el cálculo canónico que se usa en reportes, pero **no permiten cerrar una reconciliación financiera correcta mientras exista la diferencia documentada abajo**.

## Discrepancia demostrada

La orden de prueba `e2e-matrix-discount-order` tiene bruto $80 y neto $64, pero conserva un pago de tarjeta activo con `chargedAmount: 80`, `appliedAmount: 80`, `discountAmount: 0` y descuento de orden de $16. Corresponde a la ejecución anterior a la corrección del descuento. El normalizador de reportes la interpreta como venta neta de $64, por lo que la tarjeta del panel queda en $208 mientras que la suma de cargos registrados en los pagos activos es $224: diferencia de **$16**.

La orden posterior `e2e-matrix-discount-fix-20261124` sí registra neto y pago de $64, descuento de $16 y comisión absorbida de $2.56. No se modificaron fórmulas ni se alteraron los registros para ocultar el caso anterior. Para reconciliar completamente la prueba, el pago histórico incorrecto debe cancelarse por el flujo autorizado de Backoffice y, si se mantiene el escenario, volver a cobrar por $64 desde la UI. El registro cancelado debe conservarse como auditoría.

## Bloqueos que impiden el cierre

El cierre normal también valida operaciones activas antes de congelar definitivamente la sesión:

- Orden `JvJsL37j4nsVXSi92Zzb`: estado `sent`, saldo pendiente $20, un artículo de Cocina aún enviado.
- Orden `pzFriWm1gZRiaKjghmtX`: estado `sent`, saldo pendiente $244, once artículos activos; varios siguen en `sent`.
- Sesión de Cocina `NwA7KTf3U9Bgh43m0O5f`: estado `open`.
- La pantalla de Cocina muestra comandas activas. No se cancelaron, cobraron, eliminaron ni marcaron listas durante esta auditoría.

No se ejecutó un cierre forzado ni se usó Admin SDK para escribir datos. El corte queda bloqueado hasta que esas comandas se resuelvan por la UI y Cocina se cierre normalmente; luego deben recalcularse los importes usando las nuevas órdenes/pagos que permanezcan en la sesión.

Por esta razón no hay importes de conteo físico ni de terminal confirmados y no se verificó una tarjeta de corte cerrado en Caja Admin/Finanzas. En esta etapa solo se verificó la lectura del resumen de sesión abierta en la interfaz administrativa.

## Resultado sobre Backoffice

- El resumen administrativo lee los pagos generados por TacoPOS 2.0 desde el Emulator y separa efectivo, tarjeta, comisión absorbida y consumo de empleado.
- El pago cancelado de $20 no aparece en los totales activos.
- El panel interpreta el pago pre-corrección como venta neta descontada, pero sus campos de cargo de tarjeta conservan $80. Esto produce el desfase de $16 frente a `chargedAmount` y bloquea una aprobación de corte completa.
- No se afirma que el corte cerrado ni el reporte de Finanzas estén validados: el cierre está impedido por órdenes/Kitchen activas y la discrepancia histórica.

## Preparación de candidato 2.0.0-rc.1

- `pubspec.yaml` permanece en `1.5.13+31`; no se cambió versión.
- Candidato documentado: `2.0.0-rc.1`; `versionCode 32` sigue pendiente de confirmación en Play Console, para la que no se obtuvo acceso de lectura en esta sesión.
- El HEAD `a35c186a24b4ba2ee9ba46c8de27c8f063671a4e` está respaldado en la rama remota y `node tools/verify_release_worktree.js` pasó. Este es el worktree de feature, no un worktree dedicado de release; no se generó AAB.
- El worktree actual no tiene `android/key.properties`. El worktree antiguo `release/android-1.5.11-28` sí tiene configuración y archivo de keystore local, pero pertenece al código `90918ed` de +28. No prueba la firma del candidato 2.0.0 ni se usó para compilar.
- `android/app/google-services.json` apunta al proyecto de producción. El modo Emulator requiere `TACOPOS_FIREBASE_EMULATORS=true`, proyecto `demo-*` y modo debug; `lib/main.dart` rechaza el modo Emulator fuera de debug. El flujo release usa App Check Android Play Integrity según el código. No se verificaron proveedor Play Integrity, certificado de Play App Signing ni Rules/callables desplegadas en producción.
- No se compilaron artefactos, no se cambió `main`, no se desplegó y no se publicó.

## Siguiente secuencia segura

1. Resolver desde la UI la orden previa al fix de descuento: cancelar el pago de $80 en Backoffice, conservarlo como cancelado y registrar de nuevo el pago correcto de $64 si se mantiene esa prueba.
2. Completar o cancelar con el protocolo normal las órdenes activas; procesar Cocina y cerrar su sesión.
3. Volver a leer pagos y órdenes autoritativos del Emulator; exigir diferencia de ventas netas contra pagos activos igual a $0, y conciliar el total real de terminal contra `chargedAmount`.
4. Cerrar caja con conteos de efectivo y terminal derivados de los registros validados; abrir el corte cerrado en Caja Admin y Finanzas y comparar todos los campos persistidos.
5. Antes de un candidato: confirmar `versionCode` en Play Console, preparar worktree dedicado limpio con SHA remoto igual, recuperar la configuración de firma aprobada y verificar huella/certificado contra la identidad de publicación. No compilar ni publicar hasta autorización separada.
