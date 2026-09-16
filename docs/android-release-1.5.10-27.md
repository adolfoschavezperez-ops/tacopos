# TacoPOS Android 1.5.10+27 — Internal Testing

Fecha: 2026-09-16. Release autorizado desde
`fix/android-authoritative-total-on-payment`.

- `applicationId`: `com.renova.tacopos`.
- `versionName`: `1.5.10`.
- `versionCode`: `27`.
- Artefacto: AAB firmado release, `TacoPOS-1.5.10+27.aab`.
- Canal previsto: Google Play Internal Testing; upload manual por el usuario.

## Alcance

Se retiran los totales de captura y se valida el estado autoritativo al entrar
a Cobrar, conservando las fórmulas canónicas. Detalle y pruebas funcionales en
[la auditoría](android-authoritative-total-on-payment.md).

La rama parte de `3c3fb55` (`fix cash session close consistency`), aún ausente
de `main` al iniciar el cierre. El merge incluye ese antecedente ya presente
en el estado validado: modelos/pantalla de caja, repositorio, pruebas y
`firestore.rules`. No se despliegan esas reglas ni ningún servicio Firebase.
No se modifica la versión de Backoffice, Functions ni indexes.

El workflow de GitHub Pages se activa por push a `main`. Los commits de cierre
usan `[skip ci]` para omitir ese despliegue; la validación se ejecuta localmente.
No se modifica el workflow ni se publica Google Play automáticamente.

## Riesgos conocidos

**No hubo prueba física en dispositivo.** El usuario autoriza continuar con
Internal Testing con este riesgo documentado. Las verificaciones funcionales
usan pruebas unitarias/widget y límites Firebase simulados. No prueban una
carrera simultánea entre dispositivos reales.

La auditoría también documenta desbordamiento de las tarjetas existentes del
menú a 1280×900 con la tipografía de pruebas; esas tarjetas no se rediseñaron.

## Validación final previa al commit

- `dart format --output=none --set-exit-if-changed lib test`: correcto,
  205 archivos revisados y 0 cambios pendientes de formato.
- Pruebas dirigidas: **97 aprobadas**.
- Suite completa: **764 aprobadas**.
- `flutter analyze`: **sin incidencias**.
- `applicationId` confirmado en Gradle: `com.renova.tacopos`.
- `pubspec.yaml`: `1.5.10+27`.
- Versión de Backoffice: se conserva en `1.1.27`.

El AAB se genera después del merge y push de `main`, desde el commit publicado.
Su ruta, tamaño, SHA-256 y firma se entregan fuera del repositorio junto con el
cierre. No se genera APK release.
