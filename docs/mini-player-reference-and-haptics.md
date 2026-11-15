# Mini reproductor de la referencia y respuesta háptica del índice

## Apariencia

La tarjeta del mini mide 96 pt, con una carátula de 64 pt, 16 pt de margen vertical y esquinas de 32 pt. La columna central contiene título, artista/álbum y avance; play/pausa ocupa la columna derecha. El progreso ya no recorre la parte inferior de la carátula. Las dimensiones están en `MiniPlayerMetrics` y `ArtworkSize.miniPlayer`.

El material y los colores siguen los ajustes de amp, incluido el color de la carátula y los modos claro/oscuro. La fila inferior de navegación conserva su distribución. La reserva inferior compartida se deriva de la nueva altura (172 pt) y Settings sigue dejando margen al final.

Se mantienen tocar carátula/texto para abrir el player, gesto hacia arriba, cambios de pista con gestos horizontales, play/pausa, arrastre del progreso con previsualización y acciones de VoiceOver. El progreso es independiente de los botones y sus gestos.

## Toques hápticos

Settings → Music Library → Navigation → **Alphabet scrolling haptics** activa/desactiva los toques del índice. Está activado por defecto y se guarda con `library.alphabet.haptics` en UserDefaults.

El índice utiliza la respuesta de selección del sistema al cambiar de letra durante el arrastre. No repite pulsos mientras el dedo permanece en la misma letra ni al soltar. Tampoco añade pulsos al regreso programático desde el player ni a los ajustes de VoiceOver.

## Comprobación

1. Comprobar portada completa dentro de su rectángulo, textos a la derecha y progreso debajo del texto. Revisar también otra portada con Colours from artwork y ambos modos del teléfono.
2. Pausar/reproducir desde el mini, arrastrar el avance y comprobar que no abre el player ni cambia de pista. Deslizar izquierda/derecha sobre texto o portada; tocar ambas zonas o deslizar arriba debe abrir el player.
3. Recorrer A–Z lentamente y detener el dedo: en un iPhone compatible debe sentirse un toque breve por cambio de letra, sin vibración continua.
4. Desactivar Alphabet scrolling haptics, reiniciar amp y volver al índice: debe continuar desactivado y el desplazamiento debe seguir funcionando. Volver a activarlo.

La prueba de interfaz del mini comprueba separación de las zonas de progreso/portada/play, play/pausa, búsqueda, cambio de pista y apertura por texto, portada y gesto vertical. La prueba del índice comprueba además desactivar/reactivar su preferencia y conservarla tras relanzar. La sensación física de la vibración se comprueba en el teléfono.
