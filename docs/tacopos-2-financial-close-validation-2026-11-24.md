# TacoPOS 2.0 — validación financiera de cierre

Fecha de ejecución: 2026-11-24 (zona America/Mexico_City)
Resultado: **VALIDADO EN FIREBASE EMULATOR; ambas sesiones cerradas con diferencia financiera de $0.00.**

## Entorno y límites

- Proyecto exclusivamente ficticio: `demo-tacopos-local-capture`.
- Firestore Emulator: `localhost:8080`; Auth Emulator: `localhost:9099`; Functions Emulator: `localhost:5001`.
- Aplicaciones Android y Backoffice ejecutadas localmente contra Emulator. La autenticación y los reportes de Backoffice se confirmaron en Emulator.
- La inspección final de datos fue de solo lectura mediante Admin SDK, configurado explícitamente para el proyecto `demo-*`.
- No se accedió ni escribió en Firebase productivo. No se cambiaron fórmulas, versiones ni Rules; no se desplegó ni publicó.
- Worktree: `feature/durable-local-order-capture`, base `563ac79b5580d237d3227790ea9873baa8661cef`.

## Sesión de prueba original — 24 de noviembre

Sesión de caja `restaurants/main_restaurant/cashSessions/6RdAyg1nUwoveO70zWSq`, sucursal `aviacion`, estado final `closed`. La sesión de Cocina `NwA7KTf3U9Bgh43m0O5f` también quedó `closed`.

### Corrección del pago pre-fix

- Pago de tarjeta incorrecto por **$80.00** (`bb206096-0913-44e4-b3c8-e25ca20965be`) cancelado desde Backoffice. Se conserva su documento e historial de cancelación; queda excluido de los importes activos.
- Pago correcto por **$64.00** registrado desde el flujo normal (`210e6c1e-478e-46c3-8839-ce238a0da260`).
- Órdenes pendientes procesadas en Cocina y liquidadas desde la aplicación: orden `JvJsL37j4nsVXSi92Zzb` por **$20.00** (`27ed1b2d-5062-4904-bc43-d1d8ac2bb76d`) y orden `pzFriWm1gZRiaKjghmtX` por **$244.00** (`7dc8ad41-8643-4a4c-a228-d889ea995bd3`).
- El corte se cerró desde el flujo normal de Caja con conteos coincidentes con los valores conciliados.

### Conciliación del cierre

| Concepto | Resultado |
|---|---:|
| Ventas brutas | $1,574.00 |
| Descuentos y consumo de empleados mostrados conjuntamente por Finanzas | $80.00 ($32.00 de descuentos + $48.00 de consumo de empleados) |
| Venta neta | $1,494.00 |
| Efectivo aplicado | $1,286.00 |
| Efectivo recibido | $1,322.00 |
| Cambio entregado | $36.00 |
| Tarjeta cargada | $208.00 |
| Comisión absorbida de tarjeta | $8.32 |
| Ingreso monetario esperado en caja/cortes, neto de comisión | $1,485.68 |
| Ingreso real confirmado por Backoffice Finanzas | $1,485.68 |
| Diferencia de efectivo | $0.00 |
| Diferencia de tarjeta | $0.00 |
| Diferencia del corte | **$0.00** |

Comprobación: efectivo aplicado + tarjeta cargada = $1,494.00 de venta neta. El ingreso real de cortes es $1,494.00 menos $8.32 de comisión absorbida = $1,485.68. El efectivo recibido menos cambio es $1,286.00. El pago cancelado anterior de $80.00 no forma parte de esos totales.

## Sesión limpia — 25 de noviembre

Se abrió una sesión nueva con la versión corregida, identidad de mesero registrada y datos ficticios. La fecha del AVD se avanzó temporalmente para abrir un nuevo día operativo y se restauró después a fecha/hora automáticas.

- Caja `nAFVWtMnIxZvR0WnMPf8`, sucursal `aviacion`, fecha operativa `2026-11-25`, estado `closed`.
- Cocina `4ARHEFyQvvQodLRu3eYj`, estado `closed`.
- Orden pagada `readAjrZgB9Z7ysmGPAx`: dos tacos pastor, cantidad total **2**, total **$40.00**, `captureRevision=1`, un lote de Cocina, artículo marcado `ready`, orden `paid`.
- Un pago activo en efectivo por **$40.00** (`20ba15ae-a445-4c8c-b505-9476e96f5d56`); no hubo tarjeta, comisión, descuento ni consumo de empleados.
- El pago y cierre se hicieron desde la UI. Tras cobrar la aplicación volvió a Mesas y la mesa quedó disponible.
- Corte cerrado: efectivo esperado/contado **$40.00**; tarjeta esperada/reportada **$0.00**; total esperado/contado **$40.00**; diferencia **$0.00**.
- No hay faltantes ni duplicados en la orden. Existe además un intento inicial vacío, cancelado desde la UI tras detectar que la identidad del dispositivo no coincidía con el empleado seleccionado; tiene importe cero, sin artículos ni pagos, por lo que no afecta la conciliación.

## Verificación desde Backoffice Finanzas

El reporte se consultó desde Backoffice autenticado contra Emulator con rango `01/11/2026–25/11/2026`. El día 25 sí está incluido: respecto al reporte de los días 1–24, las ventas brutas, netas y el ingreso real aumentan en $40.00.

| Reporte acumulado 1–25 nov. | Resultado |
|---|---:|
| Venta bruta | $1,614.00 |
| Descuentos aplicados (descuentos + consumo de empleados) | $80.00 |
| Venta neta | $1,534.00 |
| Comisión de tarjeta | $8.32 |
| Ingreso real de cortes | $1,525.68 |
| Monetario esperado | $1,525.68 |
| Diferencia | **$0.00** |

La relación del reporte coincide: $1,534.00 de neto menos $8.32 de comisión = $1,525.68 de ingreso real. El nuevo cierre aporta $40.00 a caja y al neto, sin modificar tarjeta ni comisiones.

## Evidencia

- [Caja Admin: corte del 24 de noviembre cerrado](evidence/tacopos-2-cash-admin-closed-2026-11-24.png).
- [Backoffice Finanzas: reporte conciliado del 1 al 25 de noviembre](evidence/tacopos-2-backoffice-finanzas-2026-11-25.png).
- [Histórico: resumen de la sesión abierta antes de resolver las operaciones](evidence/tacopos-2-financial-close-open-session-2026-11-24.png).

## Cambios de código

No se detectó discrepancia financiera después de cancelar el cargo incorrecto y registrar el pago correcto mediante los flujos autorizados; no se cambiaron fórmulas. Se conserva el ajuste de imports de `firebase-admin/firestore` en `functions/src/index.ts`, necesario para el SDK actual de Admin durante la ejecución local de Functions Emulator; el cambio no altera la lógica ni los importes financieros.

## Veredicto

La sesión original y la sesión limpia terminaron con sus sesiones de Caja y Cocina cerradas, y con diferencia financiera de $0.00. Backoffice Finanzas incluye ambas sesiones en el rango y coincide con los cortes. La validación se limita a datos ficticios de Firebase Emulator; no acredita configuración productiva de Rules, App Check, Play Integrity, firma ni publicación.
