# TacoPOS Google Play updates

## Estado tecnico

- `applicationId`: `com.renova.tacopos`
- Archivo Gradle principal: `android/app/build.gradle.kts`
- Version preparada para la siguiente prueba privada: `1.0.3+4`
- `versionName`: `1.0.3`
- `versionCode`: `4`
- La version se incrementa desde `pubspec.yaml`.

La APK release auditada antes de la preparacion estaba firmada con la llave
debug de Android:

- DN: `C=US, O=Android, CN=Android Debug`
- SHA-1: `56:63:67:74:4D:99:B9:3A:69:F9:D7:93:17:FF:45:F5:11:58:27:17`
- SHA-256: `e1:59:99:74:f4:8e:ae:ff:e9:2b:05:7f:38:f8:9e:5c:ca:0b:d2:ec:c3:6a:fa:fd:a6:67:2c:97:b6:e8:d2:b3`

Esa llave no debe usarse como firma definitiva de produccion.

## Firma release

`android/key.properties` es obligatorio para generar `apk --release` o
`appbundle --release`. Si falta, Gradle falla con un mensaje claro para evitar
subir a Google Play una build release firmada con debug.

No se debe subir a Git:

- `android/key.properties`
- archivos `.jks`
- archivos `.keystore`
- contrasenas reales

El repo incluye solo `android/key.properties.example`:

```properties
storePassword=CHANGE_ME
keyPassword=CHANGE_ME
keyAlias=tacopos
storeFile=C:/secure/tacopos/tacopos-release.jks
```

Crear la llave fuera del repo:

```powershell
keytool -genkeypair -v -keystore C:\secure\tacopos\tacopos-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias tacopos
```

Guardar la llave y sus contrasenas en un gestor seguro. Todas las versiones
futuras deben conservar `applicationId`, incrementar `versionCode` y usar la
misma upload key.

## Play App Signing

Para Google Play:

1. Activar Play App Signing al crear la app.
2. Usar la llave release local como upload key.
3. Subir el AAB firmado con esa upload key.
4. Google Play firma los APK distribuidos a tablets.

## Configuracion Firestore

Documento:

`restaurants/main_restaurant/settings/appUpdates`

Campos finales:

- `minimumSupportedVersionCode`: numero.
- `recommendedVersionCode`: numero.
- `forceUpdate`: booleano.
- `updateMessage`: texto mostrado al operador.
- `active`: booleano.
- `publishedAt`: timestamp.
- `releaseNotes`: texto opcional.
- `rolloutGroup`: texto opcional informativo.
- `rolloutGroups`: lista opcional con `pilot`, `operations`, `all`.
- `criticalReason`: texto opcional.

Ejemplo inicial para `versionCode` 3:

```js
{
  minimumSupportedVersionCode: 3,
  recommendedVersionCode: 3,
  forceUpdate: false,
  active: true,
  updateMessage: "TacoPOS esta actualizado.",
  releaseNotes: "Primera version distribuida mediante Google Play.",
  publishedAt: serverTimestamp()
}
```

No guardar URL de APK, hash de APK ni rutas de descarga directa.

## Comportamiento

- Web: no ejecuta Google Play In-App Updates y funciona normalmente.
- Misma version o configuracion inactiva: no muestra actualizacion.
- Login: muestra `TacoPOS · Version <versionName> (<versionCode>)` y el estado
  `Actualizado`, `Hay una actualizacion disponible`, `Esta version ya no es
  compatible` o `No se pudo verificar la version`.
- Version recomendada: muestra `Actualizacion disponible` solo si Google Play
  confirma una version disponible y permite flexible; permite `Recordarme
  despues` e inicia actualizacion flexible con `Actualizar ahora`.
- Flexible descargada: muestra `Actualizacion lista para instalar` y permite
  `Reiniciar y actualizar`.
- Version critica: muestra `Actualizacion necesaria`, bloquea la entrada a la
  operacion e inicia actualizacion inmediata.
- Firestore sin respuesta: registra diagnostico y no bloquea una version que no
  se pudo determinar como obsoleta.
- App no instalada desde Play: muestra `APP_UPDATE_NOT_PLAY_INSTALLED` y evita
  ciclos de actualizacion.
- Version critica no propagada por Play: mantiene el bloqueo administrativo,
  muestra que Google Play todavia no presenta la actualizacion y registra
  `APP_UPDATE_REQUIRED_NOT_AVAILABLE`.

## Registro de dispositivos

Las tablets escriben un registro ligero en:

`restaurants/{restaurantId}/devices/{deviceId}`

`deviceId` usa el UID anonimo de Firebase, no un identificador fisico del
hardware.

Campos:

- `deviceId`
- `deviceName`
- `branchId`
- `branchName`
- `role`
- `platform`
- `appVersionName`
- `appVersionCode`
- `recommendedVersionCode`
- `availableVersionCode`
- `lastSeenAt`
- `lastUpdateCheckAt`
- `employeeId`
- `employeeName`
- `updateStatus`
- `rolloutGroup`
- `updatedAt`

Estados:

- `up_to_date`
- `update_recommended`
- `update_required`
- `play_update_unavailable`
- `unknown`

Nombres esperados para ajustar manualmente en Firestore si hace falta:

- Caja
- Cocina 1
- Cocina 2
- Mesero 1
- Mesero 2
- Administracion
- Respaldo

## Rollout seguro

Usar `devices/{deviceId}.rolloutGroup` y
`settings/appUpdates.rolloutGroups` para preparar grupos:

1. `pilot`: una tablet de prueba.
2. `operations`: Caja y Cocina.
3. `all`: las siete tablets.

Si `rolloutGroups` esta vacio, aplica a todos. Si tiene valores, solo aplica a
los dispositivos cuyo `rolloutGroup` este incluido.

## Versionado sugerido

Google Play compara por `versionCode`.

- `1.0.3+4`: siguiente version para probar actualizaciones desde Google Play.
- `1.0.4+5`: siguiente version menor.
- `1.0.5+6`: siguiente version menor.
- `1.0.6+7`: siguiente version menor.
