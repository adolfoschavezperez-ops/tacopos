# Google Play Internal testing para TacoPOS

Estos pasos son manuales. No se publican builds automaticamente desde el repo.

1. Crear o usar la cuenta de desarrollador de Google Play.
2. Crear la aplicacion `TacoPOS`.
3. Usar package `com.renova.tacopos`.
4. Activar Play App Signing.
5. Configurar la llave release local como upload key.
6. Crear el canal `Prueba interna`.
7. Crear una lista de testers.
8. Agregar las cuentas Google usadas en las tablets.
9. Crear una version nueva.
10. Subir `build/app/outputs/bundle/release/app-release.aab`.
11. Guardar y publicar solo en Prueba interna.
12. Compartir el enlace de incorporacion con las tablets.
13. Instalar TacoPOS desde Google Play.
14. Verificar que las siguientes versiones tengan mayor `versionCode`.
15. Confirmar que las tablets aparecen en Backoffice Web > Configuracion >
    Dispositivos y versiones.

Para actualizaciones posteriores:

- conservar `applicationId`;
- incrementar `versionCode`;
- firmar con la misma upload key;
- subir AAB, no APK directo;
- no usar descargadores privados ni Firebase App Distribution como actualizador
  de produccion.
