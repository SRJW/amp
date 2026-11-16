# Borde cromático y navegación fija

## Diagnóstico

Las copias ampliadas o reflejadas de la fotografía producían manchas reconocibles sobre la portada. Estirar una tira estrecha había causado estelas. El sistema actual sustituye esas imágenes por datos cromáticos del borde; no añade una nueva fotografía difuminada encima.

Los iconos estaban alineados en reposo, pero existían en dos vistas que recibían escalas diferentes durante la transición. Se sustituye esa duplicación por una fila persistente de botones fuera de las superficies animadas.

## Implementación

- `PlayerArtworkChromaticEdge` analiza una región estrecha del borde superior en una muestra de 40 × 6. Conserva cinco colores suavizados horizontalmente. Cuando detecta un fondo neutro mayoritario presente en ambos extremos, limita los objetos de color localizados que lo interrumpen; así unas flores centrales no convierten un fondo crema en una mancha rosa. Las paletas multicolores sin ese fondo neutro conservan su variación.
- `PlayerArtworkStatusProfile` guarda esta representación al cargar la carátula; `ReferencePlayerBackdrop` la reutiliza con la imagen y las pistas precargadas. No se vuelve a analizar la imagen durante la animación.
- `PlayerArtworkTopExtension` dibuja un campo cromático y la fotografía original una sola vez, con un fundido corto de integración. Si la imagen ya cubre el borde superior, no añade extensión ni máscara superior. No usa reflejos, estiramientos ni blur. El cálculo de contraste utiliza el mismo campo que se dibuja.
- La máscara y la extracción de colores del fundido inferior permanecen intactas. El encuadre, título, metadatos, waveform y controles conservan sus valores.
- `AppFixedNavigation` pertenece a RootView y mantiene una sola instancia de los cuatro botones. AppBottomBar conserva el mini reproductor y la cápsula, reservando el mismo espacio para los botones. Now Playing usa la fila compartida sin añadirle fondo.
- `PlayerPresentationOpacity` funde el reproductor completo sobre la librería estacionaria. Se eliminan las escalas globales y las opacidades duplicadas del fondo y del contenido. Se mantienen la duración y los gestos existentes.
- Music Library y Wi-Fi Transfer muestran `On My iPhone › amp`. No se renombra el bundle, la carpeta de datos ni los créditos de Erhu.

## Comprobación

1. Revisar portadas crema con flores, oscuras con texto brillante y multicolores. La parte superior no debe repetir objetos ni crear estelas. Cambiar de pista en ambas direcciones y alternar el modo del teléfono.
2. Comparar el fundido inferior, el título y los controles con la versión anterior.
3. Abrir el player desde el mini, volver con Library o el título y repetir durante una transición. Los cuatro botones deben conservar sus coordenadas y tamaño; sólo cambia la superficie detrás.
4. Probar búsqueda, ecualizador, menú y cerrar Settings. Verificar que sólo existe una fila accesible de navegación.
5. Abrir Settings → Music Library y revisar el nombre de la carpeta. Las rutas visibles de Wi-Fi Transfer también deben decir amp.

Las pruebas comprueban el fondo crema sin duplicar flores, la conservación de fondos oscuros y de múltiples colores, la invariancia del fundido inferior, la cobertura de toda la pantalla durante la fusión, las coordenadas de navegación y el nombre visible de la carpeta.

## Estado de validación

Código: `6007e400770a10dbe7921e456ab3d01047730c73` en `without-animated-art`.

La ejecución [149](https://github.com/SRJW/amp/actions/runs/43903193501) solicita compilación del dispositivo y la suite `full-player`, incluidas las pruebas de render y navegación. Está pendiente de asignación de ejecutores de macOS. Se probó también la cola Apple Silicon; GitHub Status informa `Actions: degraded_performance` el 16 de noviembre de 2026. No hay todavía resultados nativos ni una nueva IPA verificada de este cambio. Las comprobaciones locales de diferencias (`git diff --check`) pasan; el entorno Linux no ejecuta SwiftUI/UIKit.

La publicación de IPA y las pruebas nativas son trabajos separados: una exportación por sí sola no acredita que las pruebas hayan pasado. Las capturas sintéticas cubren los casos de borde descritos; la apariencia de las canciones concretas debe revisarse en la nueva app cuando esté disponible.
