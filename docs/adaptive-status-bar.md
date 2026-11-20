# Barra de estado adaptada a la carátula

## Causa

`PlayerArtworkStatusGradient` usaba una máscara horizontal con dos áreas opacas, detrás de la hora y de los indicadores de conectividad. En modo claro aclaraba esas zonas de una portada oscura para hacer legible la tinta negra de iOS. Eso producía dos halos grises, también sin carátula. No era un problema del encuadre ni de la extensión cromática.

## Cambio

- `PlayerAdaptiveStatusBar` elige tinta nativa blanca sobre fondos oscuros y negra sobre fondos claros. Con contraste suficiente su opacidad es cero. Sólo un borde con mezcla de claros y oscuros que no admita ninguna de las dos tintas necesita una protección oscura uniforme, con caída suave; nunca se aclaran los extremos ni se usa la máscara lateral.
- La decisión utiliza las muestras cacheadas del fondo y las interpola durante el cambio de pista, sin decodificar otra vez la imagen.
- `AppStatusBarAppearance` aplica la preferencia de apariencia al sistema y fija por separado el entorno visual de SwiftUI al tema elegido en Settings o al modo del teléfono, leído de la escena. La preferencia del player deja de aplicarse al volver a Library o abrir una herramienta. Las hojas locales del player conservan la apariencia del tema.
- `PlayerReferenceComponents` sustituye el antiguo overlay del player. `NowPlayingView` deja de imponer una apariencia que impediría elegir la tinta del sistema.
- El encuadre, la extensión cromática, el fundido inferior y los controles no cambian.

También se retiró el identificador de accesibilidad del contenedor de navegación, que sobrescribía los cuatro identificadores individuales. No cambia su aspecto ni su posición. Se corrigieron dos fixtures de render anteriores: el retrato debe renderizarse con el overscan que usa producción y el detalle localizado debe alcanzar el punto situado después del fundido.

## Prueba manual

1. Abrir una portada negra en ambos modos del teléfono: indicadores blancos, sin halos grises. Probar también una canción sin portada.
2. Abrir una portada blanca o crema: indicadores negros y fondo original sin manchas.
3. Alternar pistas claras/oscuras y deslizar la portada; revisar el contraste durante el cambio.
4. Volver a Library y abrir Settings, una hoja del player y el menú. El tema y los controles deben conservar su apariencia.
5. Comparar el fundido inferior y las posiciones con la versión anterior.

Validación nativa solicitada en la ejecución [152](https://github.com/SRJW/amp/actions/runs/43929003978), fuente `a992f89df30f4816954d0f38d71edd39426edc25`. Resultado: 37 pruebas de render y movimiento y 38 pruebas de lógica pasaron. De las diez pruebas de interacción, nueve pasaron; falló la espera de alineación que mezclaba geometría con `isHittable`. La ejecución no fue completamente satisfactoria. La revisión posterior separa las medidas de geometría de las pulsaciones reales y añade búsqueda desde el reproductor y arrastre de la selección de navegación; queda pendiente su nueva validación.
