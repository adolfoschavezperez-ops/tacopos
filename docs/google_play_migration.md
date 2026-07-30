# Migracion de tablets actuales a Google Play

Las tablets actuales tienen una APK firmada con la llave debug de Android. Para
usar Google Play como canal privado de actualizacion se requiere una unica
reinstalacion inicial desde Play.

No asumir que las preferencias locales sobreviven a la desinstalacion.

Procedimiento recomendado:

1. Cerrar todas las mesas.
2. Confirmar que no existan ordenes abiertas.
3. Cerrar caja.
4. Anotar sucursal y empleado configurado en cada tablet.
5. Desinstalar TacoPOS debug.
6. Iniciar sesion en Play Store con una cuenta tester autorizada.
7. Abrir el enlace privado de Prueba interna.
8. Instalar TacoPOS desde Google Play.
9. Seleccionar sucursal y empleado.
10. Activar actualizaciones automaticas de Play Store.
11. Confirmar que la tablet aparece en Backoffice Web > Configuracion >
    Dispositivos y versiones.

Despues de esta migracion, las siguientes actualizaciones deben distribuirse por
Google Play subiendo un AAB con mayor `versionCode`.
