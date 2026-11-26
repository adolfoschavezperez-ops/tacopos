# TacoPOS 2.0.1 — rendimiento y reanudación

Fecha: 26 de noviembre de 2026

## Optimización segura implementada

Mesas, Cocina, Para llevar y Parados conservan el listener global `orders` y el
predicado `isActiveOrder`. No se consulta `operationalActive`, no se aplica un
filtro de sucursal en servidor, no se usa fecha/estado como sustituto y no se
requiere backfill. Así se conserva compatibilidad con órdenes históricas y
escritores de +31/+32. El índice del respaldo `e6d82e3` sigue siendo una
alternativa sombra; no se activó porque documentos/escritores antiguos no
garantizan sus campos.

Los flujos operativos ahora conservan modelos activos y aplican
`QuerySnapshot.docChanges` incrementalmente. El snapshot inicial y un cambio de
sucursal convierten todos los documentos disponibles; un cambio normal
convierte sólo los documentos cambiados. Cocina usa el mismo acumulador y deja
de conservar IDs de todas las órdenes terminales del histórico. IDs terminales
sólo se mantienen cuando una orden que esta suscripción había visto activa
cambia a terminal, para impedir que una lectura provisional obsoleta la
resucite. No se cambió el ordenamiento, la agrupación, la secuencia, lotes,
artículos, cobros o reglas de negocio.

## Medición reproducible

Prueba sintética Flutter `active-order streams decode only incremental history
changes`:

| Medida | Carga inicial | Una orden cambia después |
|---|---:|---:|
| Documentos en snapshot SDK | 2,001 | 2,001 |
| Modelos `PosOrder` convertidos por la app | 2,001 | 1 |
| Órdenes activas devueltas, incluida una legacy sin campos nuevos | 1 | 1 |

Para ese cambio, las conversiones de modelos bajan 2,000 (99.95%) respecto al
reparseo anterior de los 2,001 documentos. La prueba corre tanto el stream de
Mesas como el de Cocina. Esto **no** reduce el primer snapshot, documentos
facturables, bytes de red, tamaño del caché ni la cantidad de listeners. La
telemetría ahora registra `documents` (tamaño completo reportado por SDK) y
`convertedDocuments` (trabajo de conversión en Dart) por separado.

El baseline AVD previo de Fase 6 documentó una sesión idle de 30 minutos, pero
fue anterior a este diff y no midió el rendimiento bajo carga de histórico. No
se presenta como medición antes/después de esta optimización. Las muestras
posteriores a 5/15/30 minutos, CPU/PSS, frames y bytes no se han ejecutado en
este candidato. La prueba sintética mide conteo de conversión, no tiempo de
pared ni tráfico. Las lecturas históricas iniciales siguen siendo el principal
trabajo de Firestore pendiente.

## Manejo de errores de envío

`LocalOrderCaptureSafelyAborted` se desenvuelve hasta su causa original antes
de mostrar el mensaje. `unavailable` y `deadline-exceeded` pueden presentarse
como conectividad; errores de negocio/validación muestran su causa; errores
desconocidos reciben texto neutral. Un `unauthenticated` que menciona App Check
se presenta como problema de validación de instalación, sin cambiar ni relajar
App Check. El texto no confirma que App Check sea la causa: el HTTP 401 requiere
logs/instrumentación de servidor para distinguir Auth de App Check.

Tras esta corrección, `flutter analyze` quedó limpio y la suite Flutter completa
pasó **972/972**. Las pruebas dirigidas de Cocina/streams (37), presentación de
errores (4), sesiones/diagnóstico (14) y el widget de entrada/cobro (31) también
pasaron en las ejecuciones de esta reanudación. La prueba del producto
explícitamente agotado está incluida en la suite completa; no se cambió su
validación.

## Sesiones y Fase 6 pendiente

Las pruebas dirigidas existentes del servicio de sesión y diagnóstico pasan:
restore, revocación, salida voluntaria, fallas transitorias, restauración de
permisos, tags de diagnóstico y cancelación de listeners. La evidencia anterior
registrada en `RESULTS.md` incluye 30 minutos idle en un AVD, refresh de token,
resume y reinicio del proceso online. No hay prueba física reciente de 30
minutos en la tablet de Andrés.

Intenté ejecutar `integration_test/operational_session_android_test.dart` en el
AVD conectado con los emuladores Auth/Firestore demo. El build debug terminó
correctamente; la prueba alcanzó el dispositivo y Auth devolvió un usuario,
pero `LoginGate` no restauró una identidad operativa en los tres segundos de la
prueba (`AppSession.instance.isLoggedIn == false`, línea 56). No se ejecutaron
refresh de token ni pausa/reanudación en esa pasada. Sin la identidad segura
persistida y su fixture autorizada no se puede distinguir ausencia de fixture
de defecto de restauración; esta pasada queda inconclusa, no PASS ni FAIL del
producto. No se escribieron datos de negocio para fabricar esa precondición.

El Emulator activo reporta proyecto demo `demo-tacopos-2-0-1`, con Auth 9101,
Firestore 8082 y Functions 5002. Sin embargo, el proceso Firestore arrancó con
`--rules .firestore.rules.emulator-test`, archivo que no está presente ahora;
por eso su SHA efectivo no puede verificarse contra
`firestore.rules.production-candidate` (`SHA-256
732201CF7C3C8B553EC0E60749F251E3E1AFDAE210847F48A16637C60524DF2F`). No se
reinició para preservar los datos ficticios abiertos. No se hicieron operaciones
de negocio en esta sesión del Emulator.

Continúan sin demostración nueva en esta reanudación: ejecución de APKs
históricos +31/+32 en convivencia, movimiento independiente de consumo de
empleado, respuestas obsoletas/cambio de sucursal en Android real y el ejercicio
de App Check HTTP 401 contra Functions. Las pruebas unitarias/widget de estado
de sesión y sucursal no sustituyen esas pruebas físicas. Los tests de captura
siguen cubriendo el rechazo de producto explícitamente agotado; inventario y
recetas no se cambiaron.

## Próximo paso para reducción real de lecturas

El campo `operationalActive` requiere una transición con comparación dual,
backfill verificable, compatibilidad de escritores Backoffice y clientes
anteriores, y reversión. Esta etapa no cambia consultas a ese campo. Para medir
el ahorro de documentos/bytes hace falta un Emulator controlado con el SHA de
Rules e historial sintético representativo, y después una transición autorizada
con todos los escritores inventariados; no se debe inferir ahorro de red a
partir del conteo de parseos.
