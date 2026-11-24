# TacoPOS Android 2.0.0-rc.1 — notas internas de candidata

## Alcance

Candidata arquitectónica para captura local persistente de órdenes y envío atómico al servidor. Busca conservar el borrador ante desconexiones y reinicios, confirmar el resultado del servidor antes de retirar el envío pendiente y resolver una respuesta perdida mediante el mismo identificador idempotente. Mantiene las operaciones financieras existentes; no introduce fórmulas, modalidades ni optimizaciones de consultas históricas de TacoPOS 2.1.

## No distribuir hasta cumplir estas condiciones

- Confirmación de Play Console para `versionCode 32` y verificación del certificado de carga registrado y de Play App Signing.
- Rules mínima de protección de marcadores activa y las dos callables de captura desplegadas selectivamente, con App Check comprobado.
- Prueba de instalación de la pista interna en tablet física, incluyendo App Check Play Integrity.
- Fuente final comprometida, respaldada en GitHub, worktree limpio y guard de procedencia aprobado.

## Prueba física previa a ampliar distribución

Usar tablet de prueba y restaurante/datos de prueba autorizados. Antes de empezar, registrar versión, SHA del AAB, estado de conectividad, usuario/sucursal, sesión de Caja/Cocina y número/identidad de envíos pendientes. No borrar almacenamiento local para recuperar un error.

1. Instalar desde Google Play Internal Testing; confirmar paquete, `2.0.0-rc.1`/código autorizado, Play Integrity y login. Conservar la instalación/datos previos si se actualiza una tablet con `1.5.13+31`.
2. Crear mesa y capturar artículos para varias personas, sabores y bebidas. Comparar líneas e identificadores antes del envío.
3. Activar modo avión antes de enviar; capturar varios artículos; cerrar la app desde el sistema, volver a abrir y verificar cantidades, IDs y estado pendiente recuperados sin duplicados.
4. Restaurar red, enviar una sola vez y verificar la confirmación autoritativa, artículos y lote en Cocina, cantidades y total en Orden, y que el outbox solo se retire tras confirmar.
5. Repetir con pérdida de respuesta después del commit: bloquear respuesta de red, conservar ID de envío, reabrir/reintentar, comprobar una sola aplicación de cantidades y un solo lote.
6. Mantener una segunda tablet con `1.5.13+31`; hacer una captura antigua y una nueva en el mismo restaurante. Verificar que +31 conserva su flujo y que la nueva captura se resuelve sin colisión/duplicado. No habilitar actualización obligatoria durante esta prueba.
7. Enviar extras; marcar Siguiente plato y Listo; verificar estados de cada artículo, extras y secuencias. Probar un microcorte y reconexión.
8. Cerrar Caja/Cocina y cobrar una orden de prueba parcial y total con UI. Verificar pagos, saldo, cierre, folios y diferencia cero. No alterar órdenes reales de operación.
9. Repetir la matriz en dos tablets/empleados sobre una orden de prueba; revisar el ledger autoritativo y la ausencia de duplicados antes de ampliar el grupo.

Guardar capturas/logs sin secretos, IDs de órdenes/envíos, cantidades capturadas/servidor/Cocina/cobradas y resultado de cada paso. Detener promoción ante una sola diferencia, marcador pendiente imposible de resolver, fallo App Check, orden duplicada, monto distinto o mesa/caja incoherente.

## Etiquetado y rollback

No crear etiqueta aún. Después de compilar y verificar el artefacto: crear etiqueta anotada e inmutable `tacopos-android-v2.0.0-rc.1+32` en el SHA exacto que produjo el AAB, registrar paquete/versión/firma/SHA-256 en el manifiesto y empujar la etiqueta solo con autorización de distribución.

Para un fallo durante pruebas, pausar la pista/rollout de Play y detener nuevas instalaciones. No intentar downgrade ni desinstalar/borrar datos de tablets con outbox pendiente. Mantener activas las callables necesarias para resolver envíos inciertos; reconciliar los IDs pendientes antes de cualquier retirada de servidor. Reparar con un forward-fix de `versionCode` superior disponible. No activar la actualización obligatoria hasta cerrar la validación y autorizarla expresamente.
