# Incidente de rendimiento por dispositivo — 25 de noviembre de 2026

## Dictamen

La causa exacta en la tablet de Andrés queda **indeterminada**: no hay tablet física conectada, ni Logcat, perfil de CPU/memoria o export de diagnósticos de ese dispositivo. El único Android conectado durante esta investigación fue `emulator-5554`; por eso sus cifras no se atribuyen al restaurante.

Sí se confirmaron dos condiciones del producto que justifican medir producción:

1. Mesas, Para llevar, Parados y Cocina se suscriben a `orders` sin filtro y convierten/filtran en el cliente. En cada snapshot se procesan documentos históricos ajenos a la sucursal/estado activo. Cocina además conserva un listener de `items` por cada orden operativa activa. No se modificó esta arquitectura de lectura histórica; la optimización de consultas sigue fuera de este cambio.
2. La captura local conserva el borrador en el dispositivo hasta la confirmación del envío. Antes de la confirmación, otros dispositivos pueden ver el encabezado de la orden todavía sin sus artículos. Si el envío queda pendiente o falla, ese borrador local no equivale a una pérdida confirmada ni a una orden sincronizada; se requiere medir persistencia, outbox, callable y confirmación en el dispositivo afectado.

No hay evidencia para afirmar que las lecturas históricas expliquen por sí solas la lentitud exclusiva de una tablet. Tampoco se demostró que memoria, CPU, credenciales del empleado o conectividad sean la causa real. Cambiar de operador en el mismo hardware y conservar la lentitud apunta a comparar dispositivo/proceso, pero no basta para atribuirlo a hardware.

## Sesión y proceso

- Evidencia anterior de +31: tras `force-stop` y relanzamiento se mostró el acceso por PIN mientras Firebase Auth conservó el mismo UID anónimo. El código anterior mantenía la identidad del empleado sólo en `AppSession` en memoria.
- En la candidata actual, `AppSession` persiste únicamente `employeeId`, `restaurantId` y `branchId` mediante almacenamiento seguro; nunca PIN, token ni permisos. Al arrancar o volver de segundo plano, el servicio vuelve a consultar empleado, sucursal, permisos y dispositivo desde servidor. Un error transitorio conserva la identidad persistida y espera/reintenta validación; no habilita operaciones usando permisos no confirmados. Una revocación confirmada limpia la sesión.
- El ensayo Android de 30 minutos sin interacción iniciado a las 20:51:27 hora local terminó a las 21:21:40 con el mismo PID `4322`, `MainActivity` en Mesas y sin evento `employee-session-ended`. Esto demuestra estabilidad en un AVD y la versión debug que estaba instalada durante ese ensayo; no reproduce los cinco minutos reportados en producción.
- En ese ensayo el chequeo de versión de cinco minutos dejó pasar la app: `versionCode=32`, `minimumSupportedVersionCode=32`, `forceUpdate=false`. No generó un cierre de sesión.
- El rechazo periódico de escritura de `activeSessions` visto bajo Rules candidatas es un problema de presencia, no la causa de `signOut`: Live Presence ahora captura y registra el error sin propagarlo al estado de autenticación. No se verificó el estado de Rules productivas.
- El reinicio de proceso online ya restauró la pantalla de Mesas en evidencia anterior. El intento adicional de reiniciar estando offline **no se cuenta como ejecutado**: la prueba `flutter test integration_test` retiró la instalación del AVD; `monkey` informó que no había Activity. No se borraron borradores operativos en ese intento.
- La integración dirigida de Android para refresh de token Firebase y `paused/resumed` pasó `1/1`. Las pruebas unitarias del servicio cubren logout voluntario, revocación de empleado/sucursal/dispositivo, cambio de permisos y fallos transitorios sin limpiar la sesión.

## Diagnóstico local agregado

Se agregó `OperationalDiagnosticsService` con archivo JSONL local de máximo 128 KB, escritura agrupada y pantalla **Administración → Diagnóstico del dispositivo**. No sube registros a Firestore ni altera Rules/Functions. Cada evento incluye fecha UTC, clase de operación, resultado seguro y métricas permitidas. Los UID de dispositivo/empleado/sucursal se representan con etiquetas SHA-256 truncadas; no se escriben IDs de órdenes, rutas de documentos, PIN, tokens, stack traces o mensajes libres de excepción. El archivo queda excluido de Android cloud backup y device transfer.

Recopila:

- Identificador seudónimo derivado del UID de Firebase Auth de la instalación y etiquetas seudónimas de empleado/sucursal; las métricas nativas de CPU, PSS y RX/TX se limitan al UID Android de la app. La etiqueta de instalación depende de que Firebase Auth conserve ese UID.
- Flutter: cantidad y máximo de frames lentos (umbral 32 ms), en ventanas resumidas.
- App/Login: bootstrap Firebase, restauración de sesión, revalidación al volver al foreground, resultado de App Check y política/versión de actualización.
- Operación: attaches/cancels de los listeners instrumentados, snapshot recibido, documentos procesados, resultados tras filtros, `fromCache`/`hasPendingWrites`, profundidad/etapas de `OrderCaptureQueue`, latencia de persistencia local, flush y confirmación de envío.
- Identificadores seudoanónimos para contrastar una misma persona o dispositivo entre registros exportados manualmente por el administrador.

La vista/exportación es local al dispositivo observado y requiere que un administrador abra ese dispositivo; todavía no existe una consola central de todos los equipos ni telemetría remota. Los contadores de snapshot no son una cuenta facturable de Firestore. `documents` informa documentos entregados/procesados por la app; `rxBytesDelta`/`txBytesDelta` son bytes del UID Android, medidos separadamente. Ninguna métrica de lecturas se interpreta como bytes.

### Prueba Android del registro

En el AVD genérico, el arranque produjo `auth.bootstrap=358 ms`, primer frame lento `113 ms`, RSS de runtime `326–405 MB` y PSS `261–317 MB`. En una ventana ociosa de aproximadamente 59 s, la muestra dio CPU `5.07%`, PSS `310 MB`, RX `15,935 B` y TX `4,084 B`; esos bytes incluyen bootstrap/emulador y no son tráfico celular. Después de `force-stop`/relanzamiento sin desinstalar, el archivo pasó de 8 a 13 líneas, con nuevas muestras y sin pérdida de su historial. La evidencia está en `evidence/phase6-device-diagnostics-smoke.jsonl`.

Estas cifras son sólo verificación de la instrumentación y un baseline del AVD; no son criterios para aprobar el dispositivo de Andrés.

## Cambios y validación

- Código: `lib/services/operational_diagnostics_service.dart`, `lib/screens/admin/device_diagnostics_screen.dart`, inicialización en `lib/main.dart`; instrumentación en sesión, Auth/App Check/Update, presencia, Mesas, Cocina, captura y cola; métricas Android en `android/app/src/main/kotlin/com/renova/tacopos/MainActivity.kt`.
- Persistencia local: exclusión del log de backup en `android/app/src/main/res/xml/backup_rules.xml` y `data_extraction_rules.xml`.
- Tests nuevos: `test/operational_diagnostics_service_test.dart` verifica persistencia, campos permitidos, descarte de identificadores/secretos y conteo de listeners.
- Se detectó y corrigió un defecto de la instrumentación: `QuerySnapshot.size` no estaba disponible en los dobles Firestore existentes y convertía snapshots legítimos de Cocina en errores permanentes. Los contadores usan ahora `snapshot.docs.length`, equivalente al número de documentos recibidos.
- Validación final tras esa corrección: `flutter analyze` PASS; suite completa `flutter test` 1066/1066 PASS; pruebas dirigidas de Cocina incremental 32/32 PASS; diagnósticos + sesión 14/14 PASS; `git diff --check` PASS.
- `flutter build apk --debug` con `demo-tacopos-2-0-1` y puertos locales: PASS; instalado sólo en `emulator-5554`. No se generó AAB ni release.
- El ensayo de AVD y las suites no atribuyen el incidente al dispositivo físico. La etiqueta de instalación, CPU/RAM/tráfico y eventos locales permiten recolectar evidencia en una visita, pero no se ha recibido todavía una exportación de la tablet de Andrés.

## Pendiente para determinar la causa en Los Padrinos

La próxima visita debe capturar, desde la tablet afectada y desde una tablet sana, los logs locales de la misma ventana operativa. Para comparar empleado/dispositivo sin compartir credenciales:

1. En una misma tablet, repetir la misma orden con Andrés y con otro mesero; comparar `employeeTag`, `deviceTag`, latencia de persistencia/flush/envío, cantidad local y confirmada.
2. Con el mismo empleado, repetir en la tablet afectada y la sana; comparar PSS, CPU, frames lentos, bytes por UID, snapshots/documentos, listeners y errores de autenticación.
3. Mantener Logcat y hora sincronizados; anotar IDs de orden sólo fuera del archivo de diagnóstico para correlación manual. No borrar caché, almacenamiento local ni outbox.
4. Confirmar que un envío fallido conserva el mismo outbox y submission ID, y que un envío confirmado aparece con las mismas cantidades en Cocina y Caja. Los diagnósticos no sustituyen esta verificación financiera.

Sin esos registros físicos no se autoriza atribuir el incidente a hardware, Internet, empleado, Firebase Auth/App Check ni al histórico de órdenes. La consulta histórica es un riesgo de escala confirmado para planear 2.2, pero una optimización no debe desplegarse como hotfix de esta tablet sin medición comparativa.
