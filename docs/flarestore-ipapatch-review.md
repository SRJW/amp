# FlareStore: ipapatch y la identidad de firma

## Resultado de la revisión

`ipapatch` es pertinente para el widget de amp: modifica los ejecutables de la app y de sus extensiones para cargar `zxPluginsInject.dylib`. No es una corrección visual ni una implementación de reproducción.

Fuentes examinadas:

- [ipapatch, revisión 2ccafe4](https://github.com/asdfzxcvbn/ipapatch/tree/2ccafe4035bcf9fdade17cf32605d532da6cea6a): README, `ipa.go`, `inject.go`, `patch.go`, `cmd.go`.
- [zxPluginsInject, revisión d849cd5](https://github.com/asdfzxcvbn/zxPluginsInject/tree/d849cd510f9a925d692941b8d43c5efe1ca56649): `Paths.mm`, `SideloadFix.xm`, `SecRebinds.xm` y constructor.
- La versión publicada de la herramienta es v2.1.3. El código fuente de la biblioteca y el binario incluido son materiales separados; no se ha comprobado que el binario se reproduzca a partir de esa revisión exacta.

## Coincidencia con la IPA suministrada

La IPA firmada que el usuario adjuntó corresponde a la compilación 103; no permite afirmar cómo se firmará una compilación posterior.

En esa IPA:

- App y widget conservan `com.erhu` y `com.erhu.playerwidget` en sus Info.plist.
- Los entitlements firmados contienen cinco App Groups reasignados por FlareStore, idénticos y en el mismo orden para ambos ejecutables. Ninguno contiene `com.erhu.player`.
- El perfil de la app contiene esos mismos grupos; no hay perfil incrustado separado en el widget.
- El `application-identifier` firmado de la app no corresponde al bundle ID de su Info.plist.
- El widget incluye `@executable_path/../../Frameworks` en sus rutas de carga, compatible con la ubicación donde ipapatch añade la biblioteca.

`PlayerWidgetStorage` intenta resolver el grupo configurado y grupos del perfil cuyos nombres mantienen `com.erhu.player`; no reconoce los nombres arbitrarios de esa firma. El widget tampoco encuentra por sí mismo un perfil propio. Esto hace que el parche sea una opción concreta para probar, no sólo una recomendación genérica.

## Qué hace y qué no hace el parche

`NSFileManager.containerURLForSecurityApplicationGroupIdentifier` se redirige al primer grupo autorizado que obtiene `LSBundleProxy`, dentro de un subdirectorio con el nombre originalmente solicitado. Si ambos procesos comparten ese primer grupo, ambos pueden llegar al mismo `player.json` y portada.

Si no obtiene un grupo real, usa una carpeta local de Documents. Eso no convierte las carpetas de dos procesos en una carpeta compartida: que la llamada devuelva una URL no demuestra comunicación entre app y widget.

También interviene en UserDefaults, funciones del llavero y CloudKit. Es más amplio que una corrección limitada a WidgetKit. Sus dependencias Mach-O incluidas son bibliotecas del sistema; no requiere instalar Cydia Substrate según sus comandos de carga.

No añade permisos al perfil, no convierte una firma ad hoc en una firma válida para el dispositivo, no cambia el bundle ID al autorizado por el certificado y no contiene una corrección específica para MPNowPlayingInfoCenter o la apertura desde el Centro de control.

## Flujo de prueba adecuado

1. Conservar la IPA normal y generar una copia distinta.
2. Aplicar el modo normal, que incluye app y extensiones:

   ```sh
   ipapatch --input amp.ipa --output amp-flarestore-patched.ipa --noconfirm
   ```

   `--plugins-only` dejaría a la app escribiendo en una ruta distinta o sin acceso: no es adecuado para este mecanismo compartido de amp.
3. Después, FlareStore debe volver a firmar app, widget y biblioteca añadida. Parchear después de la firma final exige firmar de nuevo.
4. Para el fallo de apertura desde la tarjeta de música, usar por separado la opción de Edit de FlareStore que alinea el bundle ID con el identificador autorizado por el perfil.
5. Comprobar en el iPhone que un cambio de canción actualiza título y portada del widget. Verificar también que tocarlo abre el reproductor y que los controles remotos siguen funcionando.

La prueba de la tarjeta de música debe comprobar los logs de entrada a primer plano. El parche de almacenamiento no demuestra que iOS ya pueda enrutar esa apertura.

## Identificador del perfil y com.amp

El identificador relevante es el autorizado por el perfil para la app, es decir, la parte de bundle ID del `application-identifier`. No es el UUID del perfil ni sólo el Team ID. Cambiar arbitrariamente `com.erhu` por `com.amp` no corrige una discrepancia con ese identificador.

Según la indicación del creador de FlareStore, ese identificador sólo puede ocuparlo una app instalada a la vez. No se debe asignar simultáneamente a varias apps. Cambiar el bundle ID también puede crear una instalación con otro contenedor de datos: la biblioteca anterior no migra automáticamente.

No se han cambiado los identificadores fuente ni parcheado/publicado una IPA en esta revisión. La integración de un artefacto opcional puede hacerse en GitHub después de compilar y antes del refirmado final; una prueba de instalación con FlareStore sigue siendo necesaria.
