# Plan de actualización — PlayIt Mobile ← PlayIt Desktop

> Base: `DOCUMENTACION_FUNCIONAL.md` del proyecto desktop (agosto 2026, v1.2.7 + cambios sin publicar)
> comparado contra el estado actual de `playit_mobile` (commit `520d374`).
> Fecha de análisis: 2026-08-14.

---

## 0. Alcance

PlayIt Mobile **no** porta nada de esto (fuera de alcance por diseño):

| Función desktop | Motivo |
|---|---|
| Separación con Demucs (§2.2) | No hay stack PyTorch en móvil |
| Descarga de YouTube / yt-dlp (§2.3) | Fuera de alcance + política Play Store |
| Instalador de dependencias (§2.7) | La app no instala nada |
| Editor de sincronización por onda (§2.10) | No se porta el editor |
| Búsqueda de letras en internet (LRCLIB / syncedlyrics, §5.5) | La app no declara permiso de red; las letras vienen en el `.lrc` de la biblioteca |
| Corregir/renombrar canción, `data.json` reescrito (§2.6) | La app es de solo lectura sobre la biblioteca |
| Buscar actualizaciones (§2.11) | Lo gestiona Play Store |

**Sí se porta**: todo lo relativo a **reproducción**, **control de stems** y **visualización
de letras** — incluidos **colores de línea**, **auto-unmute**, ajuste de timing (solo en
memoria), gestión de playlist (orden, búsqueda, duración, info) y persistencia de estado.

**Invariantes que NO se tocan** (ya documentados en `CLAUDE.md`):
- Cero permisos de almacenamiento — todo por SAF.
- `positionNotifier` fuera de `notifyListeners()` (evita rebuilds a 10 Hz y spam a la media session).
- Los 4 stems como voces de un único motor SoLoud (reloj de muestras compartido).
- Fuente empaquetada; nada de `google_fonts` (requiere permiso INTERNET).

---

## 1. Resumen de brechas detectadas

| # | Brecha | Prioridad | Archivos afectados |
|---|---|---|---|
| 1 | El parser LRC **descarta las líneas en blanco** | **P0** | `lrc_parser.dart`, `lrc_line.dart` |
| 2 | El parser **borra las etiquetas `<font color>`** → sin colores de línea | **P0** | `lrc_parser.dart`, `lrc_line.dart`, `lyrics_display.dart` |
| 3 | El centinela `"Letras no encontradas"` se muestra como si fuera letra | **P0** | `lrc_parser.dart`, `player_provider.dart` |
| 4 | **Auto-unmute de voz** inexistente | **P1** | `audio_engine.dart`, `player_provider.dart`, `stem_control.dart` |
| 5 | Tamaño de fuente de letras fijo (28 px) — desktop: 20–100 px ajustable | **P1** | `lyrics_display.dart`, `player_provider.dart` |
| 6 | Sin **modo pantalla completa** de letras | **P1** | nueva `screens/lyrics_fullscreen_screen.dart` |
| 7 | Sin **ordenamiento** de playlist (desktop: 5 modos cíclicos) | **P1** | `player_provider.dart`, `playlist_drawer.dart` |
| 8 | Sin **búsqueda** de canción insensible a acentos | **P1** | nueva `utils/text_fold.dart`, `playlist_drawer.dart` |
| 9 | Sin **duración** por canción en la lista | **P2** | `song.dart`, `media_library.dart`, `playlist_drawer.dart` |
| 10 | Sin **modal de Información** (metadata del `data.json`) | **P2** | `song.dart`, `media_library.dart`, nuevo `widgets/song_info_sheet.dart` |
| 11 | Sin **ajuste de timing** de letras ±0.5 s | **P2** | `player_provider.dart`, `lyrics_display.dart` |
| 12 | Portada: solo `cover.png` (desktop tiene cascada de 4 fallbacks) | **P2** | `media_library.dart` |
| 13 | Sin salto ±5 s | **P2** | `transport_controls.dart`, `player_provider.dart` |
| 14 | Sin persistencia de mutes / volúmenes / repeat / auto-unmute | **P2** | `player_provider.dart`, `audio_engine.dart` |
| 15 | Sin **visualizador de espectro** (§2.9) | **P3** | nueva `widgets/spectrum_visualizer.dart` |
| 16 | Sin limitador anti-clipping al sumar 4 stems (§7.2.1) | **P3** | `audio_engine.dart` |
| 17 | Sin caché ni precarga de portada/letras adyacentes (§6) | **P3** | nueva `services/resource_cache.dart` |
| 18 | El escaneo no deduplica por `(artist, title)` | **P3** | `media_library.dart` |

---

## 2. P0 — Correcciones de paridad en el parser LRC

Son bugs reales: hoy la visualización de letras en móvil **no coincide** con la del
desktop para cualquier `.lrc` generado o editado por la versión actual del desktop.

### 2.1 Conservar las líneas en blanco

**Desktop** (`lazy_resources.py:LazyLyricsManager.load_lyrics_lazy`) conserva el bloque
aunque el texto quede vacío: `current_text = [line[time_match.end():]]` produce `['']`,
que es una lista no vacía → la entrada se guarda con html `''` (o `<center></center>`).

**Móvil** (`lib/services/lrc_parser.dart:43`) hace `if (text.trim().isNotEmpty) buffer.add(text)`
y luego `flush()` exige `buffer.isNotEmpty` y `clean.isNotEmpty` → **la línea en blanco
desaparece de la lista**.

**Consecuencias actuales:**
- Durante un interludio instrumental la pantalla sigue mostrando la última línea cantada
  en vez de vaciarse.
- El índice de línea actual queda desalineado respecto al desktop.
- **El auto-unmute es imposible de implementar**: su disparador es justamente la línea en blanco.

**Cambio:** que `flush()` emita la entrada siempre que haya `currentTime`, con
`text` vacío si corresponde. `_updateLyricIndex` no cambia (ya busca por timestamp).

### 2.2 Preservar los colores de línea

**Desktop** define en `lyrics_sync_editor.py:97`:

```python
LYRIC_COLORS = {
    "azul":   "#3AABEF",   # segundo cantante
    "blanco": "#F6F5F4",   # dúo / ambos cantantes
    "rojo":   "#B23A36",   # marcador de auto-unmute (cuenta como línea en blanco)
}
AUTO_UNMUTE_COLOR = "rojo"
DEFAULT_LYRIC_HEX = "#F88FFF"   # rosa por defecto de la app
```

El `.lrc` soporta **dos formatos** (`split_rows` / `join_rows`):

```
[01:23.45]<center><font color="#3AABEF">Texto de la línea</font></center>
[01:27.10]<center><font color="#3AABEF">Renglón 1</font>
<font color="#F6F5F4">Renglón 2</font></center>
```

— es decir, **una etiqueta que envuelve la línea entera** (todos los renglones heredan el
color) **o una etiqueta por renglón** (colores mezclados dentro de una misma línea).

**Móvil** aplica `_tagPattern = RegExp(r'<[^>]+>')` y borra todo → se pierde el color.

**Cambio:** replicar `split_rows` en Dart. `LrcLine` pasa a contener renglones tipados:

```dart
enum LyricColor { defaultColor, azul, blanco, rojo }

class LyricRow {
  final String text;
  final LyricColor color;
  const LyricRow(this.text, this.color);
}

class LrcLine {
  final double timeSeconds;
  final List<LyricRow> rows;

  const LrcLine({required this.timeSeconds, required this.rows});

  /// Texto plano (compatibilidad con el código actual y con la media session).
  String get text => rows.map((r) => r.text).join('\n');

  /// Dispara el auto-unmute: sin texto real, o marcada en rojo.
  /// Réplica exacta de `_current_lyric_is_blank` (audio_player.py:1496).
  bool get isBlankForAutoUnmute =>
      rows.any((r) => r.color == LyricColor.rojo) || text.trim().isEmpty;
}
```

Reglas de parseo (orden importante, igual que `split_rows`):
1. Quitar el envoltorio `<center>…</center>` si existe.
2. Si **toda** la línea encaja en `<font color="X">…</font>`, ese es el color de línea.
3. Partir por `\n`; por cada renglón, `extract_color(renglón) ?? colorDeLínea`.
4. Limpiar el resto de etiquetas HTML del renglón (`<[^>]+>`), incluido el LRC mejorado `<00:12.34>`.
5. El hex se mapea a `LyricColor` **case-insensitive** (desktop compara en minúsculas).

Colores en `lib/constants/app_colors.dart`. **Buena noticia: ya hay paridad de facto** —
`lyricsCurrentColor = 0xFFF88FFF` es exactamente el `DEFAULT_LYRIC_HEX` del desktop, y
`accentBlue = 0xFF3AABEF` es el azul de `LYRIC_COLORS`. Solo faltan blanco y rojo:

```dart
static const Color lyricAzul   = accentBlue;              // #3AABEF (ya existe)
static const Color lyricBlanco = Color(0xFFF6F5F4);       // nuevo
static const Color lyricRojo   = Color(0xFFB23A36);       // nuevo
// lyricsCurrentColor (#F88FFF) = DEFAULT_LYRIC_HEX del desktop → sin cambios
```

### 2.3 Detectar el centinela "Letras no encontradas"

**Desktop** (`audio_player.py:2244`) escribe, cuando no encuentra letra:

```
[00:00.00]<center style="color: #ff2626;">Letras no encontradas</center>
```

y luego `_lyrics_has_error()` (línea 2038) trata la letra como inválida buscando
`"no se encontraron"` / `"letras no encontradas"` en el html.

**Móvil** hoy renderiza literalmente ese texto como si fuera la letra de la canción.

**Cambio:** en `parseLrcBytes`, tras parsear, si alguna línea contiene (fold, case-insensitive)
`"letras no encontradas"` o `"no se encontraron"` → devolver `const []`.
`LyricsDisplay` ya muestra correctamente el estado "Sin letras disponibles".

> Ojo: el centinela usa `style="color: #ff2626;"`, **no** `color="#B23A36"`, así que no
> colisiona con la detección de rojo del auto-unmute. Aun así hay que filtrarlo antes,
> porque si no la única "línea" de la canción tendría texto y bloquearía el auto-unmute.

### 2.4 Tests

Ampliar `test/` (ya existen tests unitarios del parser):
- Línea en blanco `[01:00.00]` sola → se conserva con `rows` vacío / texto vacío.
- Línea con `<center><font color="#3AABEF">…</font></center>` → `LyricColor.azul`.
- Línea multi-renglón con colores mezclados → un `LyricRow` por renglón, colores distintos.
- Línea envuelta en un solo `<font>` con 2 renglones → ambos heredan el color.
- Rojo → `isBlankForAutoUnmute == true` aunque tenga texto.
- Archivo con el centinela → `parseLrcBytes` devuelve lista vacía.
- Hex en mayúsculas (`#3AABEF` vs `#3aabef`) → mismo color.

---

## 3. P1 — Auto-unmute de voz

Función central del desktop (§2.1) y hoy ausente en móvil.

### 3.1 Semántica exacta del desktop

De `audio_player.py:1489-1549`:

- Constante: `AUTO_UNMUTE_FADE_S = 0.5` (duración del fundido).
- Estado: `auto_unmute_enabled` (checkbox, **activado por defecto**) y `_auto_unmute_gain` (0..1).
- Solo actúa **cuando la pista `vocals` está muteada manualmente**. Si el usuario desmutea
  o desactiva la casilla, la ganancia baja a 0 con el mismo fundido (no corta de golpe).
- Objetivo por bloque: `1.0` si la línea activa dispara (blanco o rojo), `0.0` si no.
- **Antes de la primera línea la ganancia es 0** (la voz sigue muteada en la intro):
  `_current_lyric_is_blank` devuelve `False` si ninguna línea tiene `t <= current_time`.
- Volumen resultante de la voz: `volumen_individual["vocals"] × (master/100) × gain`.
- Interpolación **lineal** hacia el objetivo, a razón de `n_frames / (0.5 × sample_rate)` por bloque.

### 3.2 Adaptación a SoLoud

El móvil no mezcla por bloques; cada stem es un voice con su propio volumen. Se traduce
la rampa a `SoLoud.fadeVolume(handle, to, duration)` (existe en flutter_soloud 3.5.4,
`soloud.dart:2060`), llamado **solo cuando cambia el objetivo** — no cada tick.

En `audio_engine.dart`:

```dart
static const autoUnmuteFade = Duration(milliseconds: 500);

bool _autoUnmuteActive = false;   // objetivo actual (evita re-disparar el fade)

/// Sube o baja la voz con un fundido de 0.5 s sin tocar el estado de mute.
/// [active] = true durante los tramos de letra en blanco / rojos.
void setAutoUnmuteGain(bool active) {
  if (active == _autoUnmuteActive) return;
  _autoUnmuteActive = active;
  final h = _handles['vocals'];
  if (h == null || !_soloud.getIsValidVoiceHandle(h)) return;
  final base = (_stemVolumes['vocals'] ?? 1.0) * _masterVolume;
  _soloud.fadeVolume(h, active ? base : 0.0, autoUnmuteFade);
}
```

`_applyVolumes()` debe respetar el estado: cuando `vocals` está muteada **y**
`_autoUnmuteActive` es true, el volumen efectivo es `base`, no `0`. Y al desmutear
manualmente o cambiar de canción hay que resetear `_autoUnmuteActive = false`
(el `fadeVolume` pendiente se pisa con el `setVolume` siguiente, así que el reset debe
ir acompañado de un `setVolume` explícito).

En `player_provider.dart`, dentro de `_updateLyricIndex()` (ya corre a 10 Hz):

```dart
void _applyAutoUnmute() {
  if (!_autoUnmuteEnabled || !(_engine.muteStates['vocals'] ?? false)) {
    _engine.setAutoUnmuteGain(false);
    return;
  }
  final idx = _currentLyricIndex;
  final blank = idx >= 0 && _lyrics[idx].isBlankForAutoUnmute;
  _engine.setAutoUnmuteGain(blank);   // idx < 0 (intro) → false, igual que desktop
}
```

Llamarlo también desde `toggleMute('vocals')`, desde el toggle de la casilla, y resetear
en `playSong` / `stop`.

> **Precisión**: el desktop reevalúa cada 1024 frames (~23 ms); el móvil lo hará a 10 Hz
> (100 ms) reutilizando el timer de posición existente. Con un fundido de 500 ms el
> desfase es imperceptible. **No** crear un timer adicional.

### 3.3 UI

- Checkbox/`Switch` "Auto-unmute" junto al stem de voz o en el `_StemControlsRow`.
  En vertical el espacio es escaso: ponerlo como un icono togglable pequeño sobre el
  control de `vocals` (p. ej. `Icons.record_voice_over` con estado activo/inactivo),
  con tooltip "Auto-unmute: deja oír la voz en los tramos sin letra".
- Estado inicial: **activado** (paridad con desktop, `setChecked(True)`).
- Persistir en `SharedPreferences` (ver §7.14).
- Cuando el auto-unmute está subiendo la voz, dar feedback visual en el control de
  `vocals` (p. ej. el icono tachado parpadea o cambia de opacidad) — el desktop no lo
  tiene, pero en móvil ayuda a entender por qué se oye la voz estando muteada.

---

## 4. P1 — Visualización de letras

### 4.1 Renderizado con color (`lyrics_display.dart`)

Sustituir el `Text` plano por un `Text.rich` que arme un `TextSpan` por `LyricRow`:

```dart
TextSpan _spanFor(LrcLine line, double fontSize, {required bool isCurrent}) => TextSpan(
  children: [
    for (var i = 0; i < line.rows.length; i++) ...[
      if (i > 0) const TextSpan(text: '\n'),
      TextSpan(
        text: line.rows[i].text,
        style: TextStyle(color: _colorOf(line.rows[i].color, isCurrent)),
      ),
    ],
  ],
);
```

- `LyricColor.defaultColor` → `AppColors.lyricDefault` en la línea actual y
  `AppColors.lyricsNextColor` en la siguiente.
- Los colores explícitos (azul/blanco/rojo) se respetan en ambas líneas.
- Una línea en blanco debe renderizar **vacío** (no dejar hueco colapsado: mantener la
  altura reservada para que el layout no salte).

### 4.2 Tamaño de fuente ajustable

Desktop: `LYRICS_FONT_MIN = 20`, `LYRICS_FONT_MAX = 100`, `LYRICS_FONT_DEFAULT = 62`,
paso de ±2 con wrap-around (`audio_player.py:79-81, 2150-2158`).

Móvil (los valores absolutos del desktop no aplican a una pantalla de teléfono):
- Guardar un **factor de escala** `lyricsScale` (0.6–2.5, default 1.0) en el provider,
  persistido en prefs.
- Tamaño base 28 px en portrait, 34 px en el modo pantalla completa; el efectivo es
  `base × lyricsScale`.
- Botones `A-` / `A+` (esquina de la pestaña Letras y en el modo pantalla completa).
  Se descartó el pinch-to-zoom: `GestureDetector.onScaleUpdate` captura también el
  arrastre de un solo dedo, y esa pestaña vive dentro de un `TabBarView` — competiría
  con el swipe horizontal para cambiar de pestaña.

### 4.3 Modo pantalla completa (§2.4)

Nuevo `lib/screens/lyrics_fullscreen_screen.dart`, abierto con **doble toque** sobre la
sección de letras (paridad con el doble clic del desktop) y cerrado con doble toque o
back. Contenido:

- Línea actual a tamaño máximo, siguiente línea +8 px relativos (paridad desktop).
- Fondo negro, `SystemChrome.setEnabledSystemUIMode(immersive)`, `wakelock` mientras dure
  — si no se quiere una dependencia nueva, al menos `KeepScreenOn` vía el foreground service ya activo.
- Bloquear rotación no; **permitir landscape** (es el uso natural en karaoke).
- Controles mínimos superpuestos que se auto-ocultan: play/pausa, ±5 s, botones de mute
  de los 4 stems, `A-`/`A+`.
- **Aviso momentáneo al mutear** (paridad §2.4): al tocar un stem, un `SnackBar`/overlay
  breve arriba a la derecha con `"Batería: Silenciada"` / `"Voz: Activada"`, porque los
  botones grandes de mute no están visibles.
- Restaurar orientación y UI del sistema al salir (`dispose`).

---

## 5. P1 — Gestión de playlist

### 5.1 Ordenamiento (§2.6)

Desktop `_SORT_MODES` (`audio_player.py:424`), botón cíclico + etiqueta del modo activo:

| Índice | Clave | Reverse | Etiqueta |
|---|---|---|---|
| −1 | — | — | `Sin orden` (carpeta recién cargada) |
| 0 | artist | false | `Artista A-Z` |
| 1 | artist | true | `Artista Z-A` |
| 2 | song | false | `Título A-Z` |
| 3 | song | true | `Título Z-A` |
| 4 | random | false | `Aleatorio` (rebaraja en cada invocación) |

Detalles a replicar:
- Clave de orden compuesta: por artista es `(artist.lower(), song.lower())`; por título es
  `(song.lower(), artist.lower())`.
- **Se preserva la canción en reproducción**: se guarda la referencia antes de ordenar y
  después se recalcula `currentIndex` por identidad. En Dart, `Song` implementa `==` por
  `(artist, title)` → usar `indexOf(currentSong)` es suficiente **si** se resuelve antes
  la deduplicación (§7.18); si no, buscar por `identical`.
- Cargar una carpeta nueva resetea el modo a `Sin orden`.

UI: botón "Ordenar" en la cabecera del `PlaylistDrawer` + `Text` con el modo activo,
igual que la barra de herramientas del desktop.

### 5.2 Búsqueda (§2.6)

- Nuevo `lib/utils/text_fold.dart` con `foldText(String)`: réplica de `fold_text`
  (`lyrics_sync_editor.py:304`) — normalización **NFD** + descarte de marcas combinantes
  + minúsculas, para que `"canción" == "cancion"`.
  Dart no trae normalización Unicode en el core: implementar el subconjunto latino con
  una tabla de reemplazo (á→a, é→e, í→i, ó→o, ú→u, ü→u, ñ→n, ç→c, …) — es lo único que
  usan artista/título en esta biblioteca. Alternativa: dependencia `diacritic` (pura Dart,
  sin permisos ni assets); **recomendado**, evita mantener la tabla a mano.
- `TextField` en la cabecera del drawer, filtrado incremental de la lista mostrada.
- Debe filtrar por artista **y** título con el texto plegado.
- La lista filtrada mapea al índice real de la playlist (no reproducir por índice del filtro).

---

## 6. P2 — Metadata, duración y portada

### 6.1 Duración por canción (§2.6)

Desktop la lee del header de `separated/other.mp3` con mutagen (`get_song_duration`).

Móvil: leer todo el mp3 por SAF solo para saber la duración es caro. Opciones:

1. **Recomendada**: parsear el header MP3 a mano leyendo solo los primeros ~4 KB del
   archivo. Requiere ampliar el canal SAF con un `readFileRange(uri, offset, length)`
   (`MainActivity.kt` + `saf_storage.dart`) — hoy solo existe lectura completa.
   Con el frame Xing/Info se obtiene la duración exacta; sin él, se estima con el bitrate
   del primer frame y el tamaño del archivo (que SAF ya devuelve en el `walkTree`).
2. Alternativa barata: calcularla al reproducir (`_engine.duration` ya existe) y
   **cachearla** en `SharedPreferences` por `(artist, title)`. La primera vez la fila no
   muestra duración; después sí. Es exactamente el patrón `_refresh_song_duration` del
   desktop (`audio_player.py:939`), que también rellena la duración a posteriori.

Sugerencia: implementar (2) primero (cero cambios nativos) y dejar (1) como mejora.

`Song` gana `final String? duration;` (formato `M:SS`, igual que desktop) y el
`ListTile` la muestra alineada a la derecha.

### 6.2 Modal de información (§2.6)

`songsFromDataJson` hoy descarta el valor de cada canción. Ampliarlo para devolver
también el bloque `metadata`:

```jsonc
{ "Alejandro Sanz": { "Corazón Partío": {
    "path": "...",
    "metadata": { "album": "…", "anio": "2011", "genero": "Latin Pop",
                  "formato": "FLAC", "kbps": 320 } } } }
```

- `Song` gana `final Map<String, dynamic> metadata;` (vacío si no existe).
- Nuevo `widgets/song_info_sheet.dart`: `showModalBottomSheet` con Artista, Canción,
  Álbum, Año, Género, Formato, Kbps.
- **Campos ausentes → `"Desconocido"`** (paridad literal con el desktop; las canciones
  separadas con versiones viejas no tienen el bloque).
- Disparador: pulsación larga sobre la fila de la playlist → menú contextual con
  "Información" y "Copiar" (Artista / Canción / "Artista - Canción"). Se omiten
  "Ir a la carpeta", "Corregir" y "Buscar letras de nuevo" (fuera de alcance §0).

### 6.3 Cascada de portada (§2.5)

Desktop: `cover.png` → cualquier imagen de la carpeta → tag ID3 `APIC` del mp3 principal → default.

Móvil implementa hoy solo el nivel 1. Añadir el nivel 2 es casi gratis: en
`SafMediaLibrary.scan()` ya se tiene `byRelPath` con todos los archivos de la carpeta;
basta buscar `cover.png` y, si falta, la primera entrada del mismo directorio con
extensión `.jpg/.jpeg/.png/.bmp/.gif` (orden determinista, alfabético). Igual en
`FileMediaLibrary._scanSync` con un `listSync` del directorio.

Nivel 3 (APIC) queda fuera: implicaría un parser ID3 en Dart y leer un mp3 completo por
SAF. Nivel 4 (imagen por defecto) ya lo cubre `CoverView`.

### 6.4 Ajuste de timing de letras (§2.4)

El desktop desplaza ±0.5 s **reescribiendo el `.lrc`** con aritmética en centisegundos
enteros (`mm×6000 + ss×100 + cc`) para evitar el error de redondeo de float
(`01:59.80 + 0.5` daba `02:00.29`).

Móvil: **no reescribir el archivo**. Guardar un offset en memoria, persistido por canción:

- `Map<String, int> _lyricOffsetCs` (clave `"$artist|$title"`, valor en **centisegundos
  enteros** — misma aritmética que el desktop, para que un `.lrc` compartido entre ambas
  apps cuadre exactamente).
- Se aplica en `_updateLyricIndex`: `currentSecs >= line.timeSeconds + offsetCs / 100.0`.
- UI: botones ⏪/⏩ de 0.5 s en el modo pantalla completa y en el menú de letras, con la
  etiqueta del offset actual y un botón de reset.
- Persistir en `SharedPreferences` (JSON serializado).

### 6.5 Salto ±5 s (§2.1)

Desktop: flechas del teclado. Móvil: dos botones en `transport_controls.dart` (o doble
toque en los laterales de la portada, patrón conocido de los reproductores de vídeo).
`provider.seekTo(position ± 5s)`, con clamp a `[0, duration]`.

---

## 7. P3 — Rendimiento y extras

### 7.1 Visualizador de espectro (§2.9)

flutter_soloud 3.5.4 expone `setVisualizationEnabled()`, `setFftSmoothing()` y
`AudioData`/`getTextureValue` — se puede replicar el mapeo logarítmico de barras estilo
CAVA sin binarios externos, igual que el desktop hizo con NumPy.

- `widgets/spectrum_visualizer.dart` con `CustomPainter`, repintado a ~30 fps con un
  `Ticker` **propio**, nunca vía `notifyListeners()`.
- Barras detrás de los controles en la pantalla principal; **variante circular** en el
  modo pantalla completa (paridad `CircularVisualizerWidget`).
- Debe poder desactivarse (ajuste persistido): en gama baja es coste de batería puro.

### 7.2 Limitador anti-clipping (§7.2.1)

El desktop normaliza por pico cada bloque de 1024 frames cuando la suma de los 4 stems
supera 1.0. SoLoud suma las 4 voices sin esa protección → con master alto puede saturar.
flutter_soloud incluye un filtro **`limiter`** (`lib/src/filters/limiter.dart`) aplicable
al bus global: activarlo es la traducción directa y barata de ese algoritmo.

### 7.3 Caché y precarga (§6)

Desktop cachea audio/portadas/letras con `ResourceCache` LRU y **precarga las canciones
adyacentes** (radio ±2 para letras). El móvil no cachea nada: cada `playSong` lee los 4
stems completos por SAF.

- LRU pequeña (portadas: 20; letras: 50) — no cachear stems (memoria).
- Precargar portada + letras de `currentIndex ± 1` tras arrancar la reproducción, en
  background, sin bloquear.
- Es lo que hace que el cambio de canción se sienta instantáneo.

### 7.4 Deduplicación en el escaneo

Desktop usa la clave `(artist, song)` para evitar duplicados. `Song` ya define `==` y
`hashCode` por ese par, pero `scan()` no filtra. Un `data.json` con varias entradas, o dos
carpetas con la misma canción, produce filas repetidas. Filtrar con un `Set<Song>`
preservando el orden de aparición.

### 7.5 Persistencia de estado

Desktop conserva los mutes entre canciones (`_setup_audio` los restaura) — el móvil ya
lo hace porque `_muteStates` vive en `AudioEngine`, pero **se pierde al cerrar la app**.
Persistir en `SharedPreferences`: mutes de los 4 stems, volúmenes individuales, volumen
maestro (default 0.25 = el `25` del dial desktop), `repeatMode`, `autoUnmuteEnabled`,
`lyricsScale`, modo de orden y offsets de letras.

---

## 8. Orden de implementación sugerido

| Fase | Contenido | Por qué en este orden |
|---|---|---|
| **1** | §2 completa (parser LRC: blancos, colores, centinela) + tests | Es prerrequisito duro del auto-unmute y arregla bugs visibles hoy |
| **2** | §3 auto-unmute (motor + provider + UI + persistencia) | Función estrella pendiente; depende solo de la fase 1 |
| **3** | §4 letras (color en pantalla, escala de fuente, pantalla completa + avisos de mute) | Cierra la paridad de la vista de letras |
| **4** | §5 playlist (orden + búsqueda) | Independiente; alto valor en bibliotecas grandes |
| **5** | §6 metadata, duración, portada, offset de timing, ±5 s | Requiere tocar `Song` y `MediaLibrary`; conviene hacerlo de una sola pasada |
| **6** | §7 rendimiento y extras | Opcional / mejora continua |

Fases 1–4 dan la paridad funcional real. La 5 es completitud. La 6 es pulido.

---

## 9. Verificación

Por cada fase:

```bash
flutter analyze          # debe quedar limpio (flutter_lints)
flutter test             # incluye los tests nuevos del parser
flutter run              # prueba manual en dispositivo
```

Pruebas manuales imprescindibles:

1. **Sincronía de stems** — tras cualquier cambio en `audio_engine.dart`, verificar que
   los 4 stems siguen sin deriva tras varios `seek` y pausas largas. Es el invariante
   más frágil del proyecto.
2. **Auto-unmute** — canción con `.lrc` que tenga líneas en blanco y al menos una roja;
   con `vocals` muteada debe oírse la voz **solo** en esos tramos, entrando y saliendo
   con fundido de ~0.5 s, y **sin sonar en la intro** (antes de la primera línea).
3. **Colores** — `.lrc` con una línea azul, una blanca, una con colores mezclados por
   renglón y una roja: comparar en paralelo contra el desktop.
4. **Rendimiento** — con el visualizador activo y una playlist de 500+ canciones,
   confirmar que `notifyListeners()` no se dispara a 10 Hz (el árbol no debe reconstruirse
   con la posición). Verificar con `flutter run --profile` y el widget rebuild counter.
5. **Cero permisos** — `android/app/src/main/AndroidManifest.xml` no debe ganar ningún
   `<uses-permission>` de almacenamiento en todo este trabajo. Requisito de Play Store.

---

## 10. Riesgos y decisiones abiertas

| Riesgo | Mitigación / decisión pendiente |
|---|---|
| `fadeVolume` de SoLoud podría pisarse con `setVolume` de `_applyVolumes` | Centralizar: mientras `_autoUnmuteActive` sea true, `_applyVolumes` no toca el handle de `vocals`; cualquier cambio de master/volumen individual re-dispara el fade con el nuevo destino |
| El desktop reevalúa el auto-unmute cada ~23 ms; el móvil cada 100 ms | Aceptable con fundido de 500 ms. Si se percibe retraso en el borde de línea, adelantar el disparo ~100 ms en vez de crear un timer nuevo |
| Leer duraciones exige un canal SAF nuevo (`readFileRange`) | Empezar por la vía sin cambios nativos (cachear `_engine.duration` tras reproducir) |
| El visualizador puede costar batería en gama baja | Ajuste para desactivarlo; considerar apagarlo por defecto en portrait |
| Dependencia nueva `diacritic` para el plegado de acentos | Es Dart puro, sin permisos ni assets — compatible con el objetivo Play Store |
