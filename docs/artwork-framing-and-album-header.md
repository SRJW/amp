# Encuadre de carátulas y cabecera de álbum

## Now Playing

`PlayerArtworkComposition` calcula un rectángulo proporcional que conserva la portada completa según sus dimensiones, el dispositivo y el espacio disponible. En Now Playing, `playerFrame` coloca la imagen nítida usando el 70 % del espacio vertical sobrante; la extensión de la misma portada cubre desde y=0, incluida la status bar. No hay margen vacío encima de la composición ni un desplazamiento fijo para todas las imágenes.

`PlayerAdaptiveArtwork` combina la capa principal con una extensión desenfocada de la misma imagen. Sus bordes se fusionan cuando la proporción requiere espacio adicional. Ambas capas usan la misma imagen ya decodificada. El pequeño overscan que evita costuras durante los cambios de canción se compensa en la capa principal, de modo que no añade zoom permanente a la portada.

`ReferencePlayerBackdrop` conserva la cola, precarga, caché y transiciones existentes. `PlayerFullBleedBackground` conserva la extracción de colores, el fundido inferior y sus ajustes guardados. NowPlayingView, sus textos, waveform y controles no cambian de distribución ni de tamaño.

El área de portada termina justo antes del título: `artworkHeight(in:)` parte del centro del título (60 % H), resta media altura de su texto y un margen de 1,2 % W. Así el fundido llega más abajo que el límite anterior de 55 % H, sin mover título, metadata ni controles. El ajuste guardado Artwork fade conserva su valor y todo su rango dentro de esta nueva área.

El degradado de status usa una pequeña muestra de colores calculada al cargar cada portada, el estilo claro/oscuro actual y la zona segura real de la ventana. Ajusta su intensidad al contraste necesario y desaparece gradualmente. En Now Playing, la protección clara para indicadores negros se limita horizontalmente a las zonas de reloj/señal; no aclara toda la anchura formando una franja gris. No cambia el estilo, visibilidad ni posición de los indicadores de iOS. El detalle de álbum conserva su tratamiento previo.

### Unión superior

La máscara anterior solo fundía el 4 % superior de la imagen nítida, y únicamente cuando había espacio encima. Ahora Now Playing usa una rampa gradual de transparencia con entrada y salida suaves, también cuando la imagen llega al borde superior. Su altura depende del ancho disponible y del espacio sobre la imagen, limitada al 22 % de su alto. No cambia su rectángulo, escala o posición.

Debajo permanece la extensión difuminada de la misma portada. Un degradado del color dominante, con opacidad máxima del 20 %, la matiza en la zona superior y desaparece progresivamente al entrar en la imagen nítida. No añade una franja plana ni oscurece toda la portada. La protección de los indicadores incluye este matiz en su cálculo de contraste.

Las constantes `upperBlendW`, `upperBlendHeadroom`, `upperBlendLimit` y `upperTintOpacity` se encuentran en PlayerArtworkComposition. ReferencePlayerBackdrop reutiliza el color y la imagen que ya carga para cada pista; no introduce otra decodificación, cambio de caché o animación. El fundido inferior y el encuadre permanecen como estaban tras el ajuste anterior. Artistas, álbumes y miniaturas no activan este tratamiento nuevo.

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

## Validación de carátulas

La ejecución [113](https://github.com/SRJW/amp/actions/runs/43734521563) completó 38 pruebas de lógica y 29 de renderizado sin fallos. Incluye el encuadre proporcional, los degradados de status y la separación de la metadata del álbum. También comprobó que reabrir la pista actual conserva el tiempo; su fallo de interfaz posterior fue el interruptor de respuesta háptica, corregido por separado.

La ejecución final [122](https://github.com/SRJW/amp/actions/runs/43742522929), revisión `34c3e48`, terminó correctamente: exportación/publicación y los seis flujos de interfaz de librería. Incluye mini reproductor, índice alfabético, regreso a la pista exacta, contador sin reinicio, persistencia del ajuste háptico, selección/borrado y navegación al volver de segundo plano.

IPA verificada: [v0.1.0-amp.122](https://github.com/SRJW/amp/releases/download/v0.1.0-amp.122/amp.ipa), versión `0.1.0`, compilación `122`, bundle ID `com.erhu`. SHA-256: `e759652353be4ae0dc622817419665e040c25455ea62a53da24fd963999cd279`.

## Validación del fundido superior y composición actual

La [ejecución 133](https://github.com/SRJW/amp/actions/runs/43763363708), revisión `c107a45`, terminó correctamente: compilación para iPhone, exportación/publicación y 32 pruebas de renderizado con cero fallos (23 del player y nueve de movimiento). La prueba nueva mide la transición de píxeles junto al borde superior en portadas claras, oscuras y de colores intensos, comprueba que la imagen sigue presente durante el fundido y que su interior conserva su color. También pasan las comprobaciones de contraste, composición y fundido inferior existentes.

La alineación de navegación incluida mantiene el código verificado por la prueba nativa de la ejecución 131; este último cambio no modifica su geometría.

IPA actual verificada: [v0.1.0-amp.133](https://github.com/SRJW/amp/releases/download/v0.1.0-amp.133/amp.ipa), versión `0.1.0`, compilación `133`, bundle ID `com.erhu`. SHA-256: `8a5f54dae3b50c05ab4ee4c8364307bb8729047aa8011a99e31f7893522abd30`.

En el iPhone, revisar varias portadas con detalles próximos al borde superior, alternar modo claro/oscuro y cambiar de pista en ambas direcciones. Debe mantenerse una unión suave con la extensión superior, indicadores legibles y el mismo encuadre, controles y fundido inferior.
