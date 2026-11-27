# TacoPOS 2.0.1 — reanudación de estabilización (27-11-2026)

## Código respaldado

Rama: `fix/tacopos-2.0.1-operational-stability`

- `e0be170ffa0eceea3752ad93ecfc5c466f9b0796` — instrumentación local de login,
  inicio y suscripciones/dispositivos para medir sin registrar credenciales.
- `9d9fa6617b1dcce1a272a89d5dd5db231de397c9` — conciliación de órdenes sin
  reparación destructiva desde pantallas, clasificación visible de órdenes
  ambiguas, preservación del envío congelado e intento serializado de
  recuperación App Check con el mismo payload e ID de idempotencia.

Ambos commits se subieron a la rama indicada. `origin` se verificó en
`9d9fa6617b1dcce1a272a89d5dd5db231de397c9`. No se modificó `main`, producción,
Rules desplegadas, Functions desplegadas ni versiones. No se añadieron archivos
de evidencia temporal a los commits; los untracked preexistentes se conservaron.

## Validación ejecutada

- `flutter analyze`: PASS.
- `flutter test`: PASS, 979/979.
- Pruebas dirigidas de reconciliación, bloqueadores, ciclo de vida de Mesas,
  Kitchen bundles, captura y errores de envío, diagnósticos y sesiones: PASS,
  104 pruebas.
- Firestore Rules Emulator: PASS, 139/139; proyecto demo y endpoints locales.
  SHA leído de `demo-tacopos-2-0-1`: 
  `732201CF7C3C8B553EC0E60749F251E3E1AFDAE210847F48A16637C60524DF2F`, igual a
  `firestore.rules.production-candidate`.
- Functions: PASS, 117/117, Node `v22.21.0`; Firestore y Auth configurados en
  endpoints `127.0.0.1` de Firebase Emulator. No hubo llamadas a producción.
- `git diff --check`: PASS.

Los tests de Rules y Functions usan IDs de proyectos `demo-*`; el emulador con
los datos ficticios operativos de Fase 6 no se limpió.

## Límites que siguen abiertos

- No se ejecutó la integración Android en este turno. Un AVD dedicado de fase 6
  llegó a conectarse, pero iniciar un tercer AVD dejó aproximadamente 158 MiB
  libres en el host. Se apagó ese AVD normalmente, sin `-wipe-data`; los otros
  dos AVD genéricos no se tocaron. Repetir la integración cuando el host tenga
  recursos suficientes, en el AVD dedicado, con las Rules de SHA indicado.
- No se recuperó una traza Flutter de la aserción al aprobar gastos y no se
  reprodujo el fallo. No se hizo una corrección especulativa.
- La instrumentación de login registra duraciones en builds debug y no prueba
  el origen de los reportes de 3–4 minutos. Falta capturar y comparar una
  ejecución de +32 y una de este candidato en un dispositivo autorizado.
- Las pruebas locales no resuelven los rechazos App Check observados en
  producción. App Check sigue habilitado y no se cambió su política.
- La recuperación de respuesta perdida, persistencia local, idempotencia y
  concurrencia tienen cobertura de pruebas y evidencia histórica de Emulator;
  no se presenta una nueva repetición Android de esos recorridos en este turno.
- La ambigüedad de una orden sin artículos de servidor se conserva como
  bloqueador de revisión para resolución explícita. No se cancelan órdenes ni
  se liberan mesas automáticamente al abrir Mesas o paneles administrativos.

**Dictamen:** las regresiones automatizadas del estado respaldado pasan. Fase 6
no se declara cerrada y el candidato no se declara listo para distribución
hasta reproducir los pendientes físicos/de UI y resolver los incidentes de
gasto, App Check y login con evidencia real.
