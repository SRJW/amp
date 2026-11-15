# Library y reproductor: movimientos de las referencias

Los videos `VIDEO-2026-11-15-09-17-35.mov` y `VIDEO-2026-11-15-09-17-36.mov` se usan como referencia de interacción, conservando las vistas y la estética de amp.

- Índice alfabético: recorrido con el dedo, indicador grande junto al punto de contacto y desplazamiento breve hacia el grupo elegido. Las letras vacías llevan al siguiente grupo disponible; al final se usa el último grupo existente. El índice sigue respetando los filtros y el orden de los resultados. Mantiene ajuste mediante VoiceOver y evita animar el desplazamiento con Reducir movimiento.
- Library → player: tocar una fila reproduce mediante la acción existente y abre el reproductor completo. La lista se amplía ligeramente mientras desaparece; el player entra con zoom y fundido. La duración está en `PlayerMotionTiming.duration` (0,32 s) y las escalas en `PlayerNavigationMotion`.
- Título → All Songs: se monta la lista sin filtros y se sitúa la canción antes de cerrar el player. Así el movimiento inverso termina en la fila correcta, con su resaltado. Una petición cancelada no puede cerrar un player abierto después.
- Mini reproductor: 88 pt totales, con carátula de 44 pt, margen vertical de 14 pt en su fila y zona de progreso de 16 pt. La reserva inferior compartida crece a 164 pt y también deja espacio en Settings. No cambia el tamaño de la carátula ni sus gestos.

## Comprobación

1. All Songs ordenado por título: arrastrar el índice de A a Z y de vuelta. El indicador debe seguir al dedo y desaparecer al soltar. Probar letras sin canciones y títulos con acentos/números.
2. Tocar una canción: comprobar apertura con zoom/fundido y reproducción de la fila elegida. Volver mediante su título: la fila debe aparecer centrada y resaltada. Repetir con una canción fuera de pantalla y con un filtro previo que la excluya.
3. Abrir/cerrar rápidamente el player y probar el gesto de bajar: no debe quedar una capa invisible bloqueando Library. Con Reducir movimiento, las pantallas deben usar fundido sin zoom.
4. Revisar el margen de la carátula en el mini y comprobar arrastre de progreso, cambio de pista horizontal y apertura al tocar. Llegar a las últimas opciones de Settings y verificar que siguen siendo accesibles.

La comprobación nativa existente de canción fuera de pantalla ahora también arrastra el índice en ambas direcciones y verifica la apertura directa desde una fila. Las pruebas de lógica cubren las letras vacías y una petición de regreso que se cancela al reabrir el player.
