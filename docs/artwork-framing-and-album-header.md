# Encuadre de carátulas y cabecera de álbum

## Now Playing

`PlayerArtworkComposition` calcula un rectángulo proporcional que conserva la portada completa según sus dimensiones, el dispositivo y el espacio disponible. Solo utiliza el espacio vertical sobrante para dejar margen bajo la zona segura: no desplaza todas las imágenes una cantidad fija.

`PlayerAdaptiveArtwork` combina la capa principal con una extensión desenfocada de la misma imagen. Sus bordes se fusionan cuando la proporción requiere espacio adicional. Ambas capas usan la misma imagen ya decodificada. El pequeño overscan que evita costuras durante los cambios de canción se compensa en la capa principal, de modo que no añade zoom permanente a la portada.

`ReferencePlayerBackdrop` conserva la cola, precarga, caché y transiciones existentes. `PlayerFullBleedBackground` conserva la extracción de colores, el fundido inferior y sus ajustes guardados. NowPlayingView, sus textos, waveform y controles no cambian de distribución ni de tamaño.

El degradado de status usa una pequeña muestra de colores calculada al cargar cada portada, el estilo claro/oscuro actual y la zona segura real de la ventana. Ajusta su intensidad al contraste necesario y desaparece gradualmente. No cambia el estilo, visibilidad ni posición de los indicadores de iOS.

## Álbum

Solo AlbumDetailView activa `separatesMetadata` en CollectionHeroHeader. El layout coloca primero el hero y después un bloque medido de título (máximo dos líneas), artista y datos. No superpone el nombre sobre la foto ni aplica offsets al bloque de texto. Artistas y playlists conservan su colocación anterior.

La portada de álbum reutiliza la composición adaptable y la protección de status. La transición inferior sigue usando la paleta de la colección. Play, Shuffle, Transition Studio y las pistas mantienen sus componentes.

La normalización de presentación colapsa ediciones adyacentes idénticas, por ejemplo `(Remastered) (Remastered)`, conservando ediciones diferentes. Los tags y nombres almacenados permanecen intactos.

## Regreso al player

Preparar la ruta de All Songs bajo el player no inicia una segunda transición de NavigationStack. Tocar una fila que ya está sonando abre el player conservando posición y cola; si estaba pausada la reanuda. La selección de otra canción sigue utilizando la acción de reproducción existente.

## Comprobación

1. Probar portadas cuadradas de 500, 1000 y 2000 px, una horizontal y una vertical: revisar bordes, logos, rostros y ausencia de deformación o zonas vacías. Cambiar rápidamente de pista y hacer el gesto horizontal en ambas direcciones.
2. Alternar modo claro/oscuro con una portada clara y otra oscura. Comprobar hora, señal y batería sin alterar su configuración; revisar que el degradado superior desaparece suavemente y que el inferior conserva los colores y ajustes.
3. Abrir un álbum con título largo y con edición duplicada. Verificar título único debajo de la imagen, artista y datos en ese orden. Desplazar el contenido y probar Play, Shuffle y Transition Studio.
4. Buscar una pista avanzada, tocar título para volver a su fila y tocar esa misma fila: el contador debe continuar, sin volver a cero. Repetir con la pista pausada y con otra canción.

Las pruebas de renderizado comprueban proporciones y límites en distintos tamaños, conservación de los bordes, protección de status en fondos extremos y separación de foto/metadata. La prueba nativa de canción fuera de pantalla también verifica que reabrir la fila actual no reinicia el tiempo.
