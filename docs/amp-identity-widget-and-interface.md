# amp: identidad, widgets y correcciones de interfaz

## Identidad y compatibilidad

El proyecto, módulo, ejecutable y fuentes usan `Amp`; los identificadores nuevos son `com.amp`, `com.amp.playerwidget` y `group.com.amp.player`. La web de transferencia muestra `amp Wi-Fi Transfer` tanto en el título de pestaña como en el encabezado. Enlaces actuales y User-Agent apuntan a SRJW/amp.

Los nombres originales sólo permanecen en créditos/licencias, referencias reales a repositorios externos y compatibilidad explícita: enlaces `erhu://`, actividades antiguas, el sello de versiones anteriores, el antiguo grupo compartido, el encabezado de navegadores ya abiertos y los identificadores que iOS guarda para widgets/controles existentes. No son la marca visible ni el bundle ID nuevo. No se alteran el vocabulario de modelos ni metadatos de canciones del usuario.

Dentro del mismo contenedor instalado, `LibraryPaths` copia la carpeta anterior a una ubicación temporal y sólo la activa cuando termina. Conserva el original para rollback y rutas de imágenes absolutas. Si falla la copia, sigue usando la carpeta anterior. No sobreescribe una carpeta nueva existente. Esta migración no puede acceder al sandbox de una app con otra identidad: en FlareStore hay que mantener el mismo Profile App-ID que ya funcionaba para actualizar conservando datos.

## Una sola IPA

La compilación habitual construye ipapatch desde una revisión fijada y verifica el hash de su biblioteca incluida. Aplica el parche a la app y la extensión, vuelve a firmar ad hoc y comprueba firmas, permisos, metadatos, rutas de carga y recursos mediante `verify_flarestore_patch.py`. Sólo publica **amp.ipa**, ya parcheada. La IPA temporal sin parche no se publica. El workflow separado de dos variantes se retiró.

La firma ad hoc comprueba integridad, no autoriza instalación. La IPA se vuelve a firmar en FlareStore con el mismo perfil y la opción Profile App-ID usada por el usuario. Renombrar el bundle base no sustituye ese ajuste de identidad del certificado.

## Widgets

Los tres estilos se eligen individualmente en **mantener pulsado → Edit Widget → Style**: Cover focus, Compact e Immersive. Mantienen botones circulares, símbolos de reproducción y áreas táctiles de al menos 44 pt. Los controles son `AudioPlaybackIntent`: anterior, play/pausa y siguiente se ejecutan en el proceso de audio sin solicitar primer plano ni navegar al reproductor. Tocar la portada/contenido sigue abriendo amp.

El código anterior podía eliminar una portada compartida tras una falta temporal de caché y borraba las imágenes después de sólo cuatro cambios de pista. Ahora conserva la portada válida del mismo tema, limita la miniatura a 360 píxeles, protege los archivos para lecturas tras el primer desbloqueo y no borra portadas recientes que WidgetKit pueda seguir usando. Cada entrada captura su imagen al crear la timeline; un archivo privado conserva la última entrada válida si el acceso compartido falla transitoriamente. Un fallo no sustituye inmediatamente un widget válido por un placeholder oscuro.

El progreso del estilo Compact usa el temporizador de WidgetKit mientras suena; no exige recargar la timeline cada segundo. Los cambios de posición normales no se tratan como cambios de canción. La operación real después de refirmar sigue necesitando prueba en el iPhone.

## Bienvenida y tipografía

Las seis páginas muestran biblioteca, importación, formatos locales, reproductor, waveforms/letras, ecualizador/crossfade y personalización/widgets. El hero usa una marca tipográfica y un botón circular, en lugar del logo cuadrado con esquinas negras. Las tarjetas e ilustraciones usan la paleta existente y respetan las áreas seguras.

La fuente predeterminada es la del sistema, **SF Pro**, también en títulos, artista y datos técnicos del reproductor. Se retiraron Avenir Next y diseños fijados manualmente. Settings conserva System (SF Pro), Rounded, Serif y Monospaced; los números pueden usar dígitos de anchura estable dentro de la fuente elegida.

## Correcciones adicionales

- Al aparecer el teclado, se ocultan tanto la fila de navegación como su superficie; el mini permanece sobre el teclado. Desaparece la cápsula vacía.
- All Songs oculta el indicador de scroll estándar y conserva el índice alfabético con `#` al principio, acorde con los títulos numéricos de la lista.
- Sin carátula, el player usa negro o blanco plano según el modo, con `amp` como marca de agua. Omite la imagen, blur y degradados; texto, iconos y waveform conservan contraste. La transición hacia/desde una portada es un fundido de superficies completas, sin mover controles.

## Verificación

Las pruebas Python de herramientas pasan (10). Se comprueban además las rutas del proyecto, YAML y plists. La suite nativa incluye migración de datos y recuperación tras error, compatibilidad de widgets y enlaces, conservación de imágenes ante fallos de caché, transferencia por Wi-Fi, páginas de bienvenida, posición de navegación, teclado, índice alfabético y fondos sin carátula.

Antes de instalar: comprobar los datos de la IPA exportada (nombre, bundle IDs, release stamp), el parche en ambos ejecutables, firmas ad hoc y que Releases tenga un único `.ipa`. En el iPhone: usar el mismo Profile App-ID, actualizar sin borrar la instalación previa, elegir los tres estilos, probar controles sin primer plano y comprobar el widget tras varias canciones y reposo. Revisar las seis páginas, las opciones de tipografía y el fondo sin portada en ambos modos.

Resultados de compilación, pruebas nativas y archivo final: pendientes de la ejecución de GitHub.
