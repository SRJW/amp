# Alineación de Library y Now Playing

La barra de Library conserva su cápsula, márgenes de 12 pt, altura de 48 pt y padding inferior de 4 pt. Su minirreproductor y sus materiales no cambian.

Now Playing deja de colocar los iconos al 94 % de la altura. `AppNavigationMetrics.centreY` calcula el centro desde el borde inferior real: altura de pantalla menos área segura inferior, padding compartido y media altura de la barra.

`AppNavigationSafeArea` lee el inset de la ventana en RootView y lo comparte por environment. De este modo, ignorar las áreas seguras para dibujar la portada a pantalla completa no pierde la referencia inferior de navegación. Se actualiza al cambiar la ventana o sus áreas seguras.

Los centros horizontales del player usan el mismo ancho interior y margen que Library, tal como se confirmó durante la implementación. Los iconos conservan sus tamaños y colores. Now Playing sigue dibujándolos directamente sobre su fondo, sin cápsula, borde ni material.

No se cambian animaciones, acciones de navegación, waveform ni controles. Los cambios de carátula realizados en la tarea anterior se conservan por separado.

La prueba nativa `testLibraryAndPlayerNavigationShareScreenCoordinates` mide los cuatro botones de Library, abre el player y compara centros X/Y y tamaños con tolerancia de medio punto. Después vuelve a Library y comprueba que sigue en su posición original.

En el iPhone: alternar entre mini reproductor → Now Playing → Library y observar los cuatro centros. Revisar que solo Library tenga Liquid Glass, que el mini conserve su posición y que todos los botones mantengan sus acciones.
