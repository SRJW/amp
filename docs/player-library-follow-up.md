# Ajustes de Library y reproducción después de la compilación 91

Entrega verificada: `v0.1.0-amp.103`, código `82627f628542f9432bfc4c576bfbd93e3cc9bd49`. Compilación, exportación y prueba del editor correctas. Incluye el mini reproductor de 72 pt.

IPA: https://github.com/SRJW/amp/releases/download/v0.1.0-amp.103/amp.ipa

- Customize Library lee directamente el orden guardado: la lista aparece al abrir. Tocar el botón de ojo muestra/oculta el apartado; los tiradores reordenan. La hoja posee sus preferencias para actualizar y guardar el estado de inmediato. El ojo tiene un área táctil propia de 44 pt y una etiqueta accesible de mostrar/ocultar, independiente del tirador de reordenación. Restaurar valores queda dentro de «…».
- El título del player abre All Songs sin filtros. Cada fila tiene un contenedor con identidad estable y admite resaltado; el salto espera al montaje de la lista y corrige su posición tras la medición de filas.
- Scrolling y mini reproductor usan un reloj visual continuo con corrección gradual, que toma la posición y el tiempo del mismo buffer de audio. Las búsquedas reinician ese reloj de inmediato. El motor, los bucles y Now Playing conservan su posición real. El modo estático mantiene su lectura directa y su recorrido. El tono de cada barra de Scrolling también cambia parcialmente bajo el cabezal para evitar saltos de color.
- Library pinta su fondo y contenido con la paleta activa. Colours from artwork también colorea los cinco círculos del transporte, con símbolos elegidos para contraste y un borde oscuro. En ese tema el player deja de forzar modo oscuro: la paleta sigue los modos claro/oscuro del iPhone, también mientras el player está abierto.
- Apariencia: degradado regulable, color, vista previa de la carátula actual; se conservan fundido, desenfoque, detalle, intensidad, saturación y restauración. Las preferencias previas siguen decodificando.
- Playback: fundido automático para todas las canciones, desactivado o solo aleatorio; cambio manual sin fundido, corto regulable (0,5–2 s) o con la duración principal. Los ajustes particulares de álbum/lista se conservan.
- Settings deja espacio adicional al final del contenido para que la barra inferior no cubra opciones.
- Mini reproductor de 72 pt: carátula de 44 pt con 6 pt de margen vertical en su fila, progreso de 16 pt y espacio reservado de 148 pt para el conjunto. Tocar abre el player, deslizar hacia arriba lo abre, izquierda va a la siguiente pista y derecha a la anterior. Arrastrar la línea de avance previsualiza la posición y busca al soltar. Su región es independiente del gesto para cambiar de pista. VoiceOver anuncia la canción y permite ajustar el avance/cambiar pistas.

## Pruebas manuales

1. Library → … → Customize Library: abrir y comprobar que ya aparecen las filas; tocar el ojo de Albums y comprobar que cambia a oculto, reordenar con el tirador, cerrar y volver a abrir. Reiniciar la app y comprobar que conserva los cambios.
2. Reproducir una canción al final de una librería grande; subir la lista hasta el principio. Abrir player y tocar título: la lista debe desplazarse hasta esa canción y resaltarla aproximadamente 1,5 s.
3. En Playback alternar Static y Scrolling; reproducir, pausar y arrastrar waveform. Verificar movimiento continuo, inicio correcto de la nueva pista y retorno de controles al soltar.
4. Activar Colours from artwork; alternar portadas de colores distintos. Verificar fondo/textos de Library, círculos del transporte y legibilidad de símbolos. Cambiar entre modo claro y oscuro del iPhone con el player abierto: los controles deben cambiar de tono conservando los colores de carátula.
5. Appearance: ajustar degradado/color y los controles de fondo; comprobar vista previa, player y persistencia. Restaurar valores.
6. Playback: probar automático desactivado + manual corto; automático con duración elegida + manual desactivado; aleatorio. Verificar también los ajustes particulares de álbum/lista.
7. Llegar al final de Settings con una canción cargada: la última opción debe poder quedar completamente por encima del mini reproductor.
8. En el mini, arrastrar progreso y soltar; verificar que no cambia de canción. Deslizar izquierda/derecha sobre título/portada y comprobar el cambio sin abrir player; tocar y deslizar arriba deben abrirlo.

La consulta real de actualizaciones en GitHub Actions usa autenticación únicamente en el ejecutable de prueba. El token no se incorpora a la app. La validación de respuestas y límites de la app se conserva.

## Validación

- 103: prueba real de mostrar/ocultar, persistencia tras relanzar y título → All Songs sin filtros: correcta (63,868 s, cero fallos). https://github.com/SRJW/amp/actions/runs/43634091798
- 101: los otros cinco flujos seleccionados de librería, mini reproductor, cierre del player, selección/borrado y navegación/segundo plano pasaron. La representación accesible del editor se corrigió después en 103.
- 97, código de reproducción y apariencia conservado: 36 pruebas de lógica, 26 de renderizado y ocho flujos de interfaz correctos, incluidos los dos modos de waveform, controles y salto a una canción fuera de pantalla.

## Tarjeta del Centro de control: diagnóstico pendiente en el iPhone

La apertura desde la tarjeta todavía no está resuelta. El código configura AVAudioSession como playback, activa la sesión, publica Now Playing y registra comandos remotos en la app principal. El IPA original 103 tiene bundle ID `com.erhu` y background mode `audio`.

Para distinguir un fallo de activación de iOS de uno de navegación:

1. Abrir amp y reproducir una canción; volver a Inicio sin cerrar la app.
2. Tocar la carátula de la tarjeta del Centro de control y anotar la hora.
3. Si no se abre, no abrir amp manualmente: ir a Archivos → En mi iPhone → amp → Diagnostics → lifecycle.log.
4. Compartir ese registro. Contiene el bundle ID real, el ejecutable, activación de audio y eventos de primer plano/segundo plano. Abrir amp manualmente antes de recogerlo produciría eventos de primer plano que no pertenecen al toque en la tarjeta.

No se fuerza la presentación del player en todos los retornos a primer plano: se conserva la pantalla al minimizar o cambiar de app, como pidió el usuario.
