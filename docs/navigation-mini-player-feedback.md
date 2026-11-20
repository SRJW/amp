# Navegación, aviso de favoritos y cambio de pista del mini

Referencias: los dos videos enviados el 20 de noviembre. El segundo muestra el minirreproductor, no el reproductor completo.

## Archivos y cambios

- `AppBottomBar.swift`: cápsula de navegación de 60 pt, etiquetas bajo los cuatro iconos y selección que se mueve entre las secciones. Utiliza Liquid Glass cuando está disponible y habilitado, y un relleno discreto en el resto de casos. Permite arrastrar horizontalmente la selección. El mini, la barra y sus reservas de espacio siguen usando constantes compartidas. Los centros de los iconos no cambian entre Library y Now Playing. Dentro del player no aparecen la cápsula de selección ni las etiquetas.
- `MiniPlayer.swift`: reutiliza la cola de transiciones para conservar la pista saliente y entrante durante 0,45 s y agrupar saltos rápidos. Los textos se desplazan en la dirección del cambio y la carátula se funde en su propio espacio. Play/pausa y el área de progreso quedan fuera de esas capas animadas. Mantiene los gestos de avance/retroceso, apertura y seek. Reduce Motion usa un fundido de 0,16 s.
- `LibraryActions.swift`: distingue confirmaciones de añadir y quitar favoritos mediante un tipo de mensaje y constantes de texto. Conserva la lectura del resultado real de la base de datos.
- `LibraryItems.swift`: aviso de tamaño ajustado al contenido, fondo negro al 84 %, texto blanco, check verde al añadir y corazón al retirar. Duración de 1,8 s y transición de opacidad de 0,2 s. Las constantes de presentación están en `LibraryToastMetrics`.
- `NowPlayingView.swift`: sitúa ese aviso encima de los iconos usando el área segura inferior y las mismas medidas de navegación. No modifica los controles ni la animación de las carátulas del player completo.
- `LibraryInteractionTests.swift`: compara centros y dimensiones de los botones, prueba búsqueda desde el player y el arrastre de selección. Las medidas de geometría se comprueban por separado de las pulsaciones reales. Guarda capturas de ambos estilos de navegación.

## Cómo comprobarlo

1. Alternar Library, Equalizer y Search, y abrir Menu. Arrastrar la selección de Library a Search. Comprobar etiquetas, selección y ausencia de desplazamientos de los iconos al abrir el player.
2. Cambiar de canción con los gestos del mini y con los controles existentes. Los textos deben deslizarse y la portada fundirse; play/pausa y la barra no deben viajar con ellos. Repetir con varios saltos rápidos, Reduce Motion y las pantallas abiertas desde el menú.
3. Arrastrar el progreso y comprobar que no abre el player ni cambia la pista.
4. Añadir y quitar favoritos en el player: revisar texto, icono, tamaño y que el aviso no cubra ninguno de los cuatro botones.

Validación solicitada en [154](https://github.com/SRJW/amp/actions/runs/44800791643), fuente `073a209204b9ed2a5465d1aa38dda4f53d6c0ed8`. Pendiente de resultados nativos y exportación.
