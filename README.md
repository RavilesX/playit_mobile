# PlayIt Mobile

Reproductor de audio multi-stem para Flutter. / A multi-stem audio player built with Flutter.

---

## Español

**PlayIt Mobile** es un reproductor de audio para Flutter que separa cada canción en 4 stems (batería, voz, bajo y otros) reproducidos en sincronía sample-accurate. El usuario puede silenciar o ajustar el volumen de cada stem de forma independiente (por ejemplo, silenciar la voz para hacer karaoke). Incluye letras sincronizadas mediante archivos LRC.

### Características

- Reproducción de 4 stems perfectamente sincronizados sobre un único reloj de muestreo.
- Control de volumen y mute independiente por stem.
- Letras sincronizadas (formato LRC), con soporte multi-línea.
- Integración con la sesión multimedia del sistema (notificación, pantalla de bloqueo, controles del auricular, reproducción en segundo plano).
- Selección de biblioteca musical mediante Storage Access Framework (Android) o selector de archivos (escritorio/iOS) — **la app no declara permisos de almacenamiento**, requisito para publicación en Play Store.
- Interfaz adaptable a orientación vertical y horizontal / pantallas anchas.

### Estructura esperada de la biblioteca musical

Cada canción vive en su propia carpeta:

```
<carpeta de la canción>/
  data.json                 # {"Artista": {"Título de la canción": ...}}
  separated/drums.mp3
  separated/vocals.mp3
  separated/bass.mp3
  separated/other.mp3
  cover.png                 # opcional
  lyrics.lrc                # opcional
```

Los 4 stems son obligatorios para que la canción aparezca en la biblioteca. `cover.png` y `lyrics.lrc` son opcionales.

### Comandos

```bash
flutter pub get                      # instalar dependencias
flutter run                          # ejecutar en un dispositivo/emulador conectado
flutter analyze                      # linter (reglas flutter_lints)
flutter test                         # ejecutar todos los tests
flutter test test/widget_test.dart   # ejecutar un test específico
flutter build apk                    # build de release para Android
```

### Arquitectura

El estado de la app fluye a través de un único `ChangeNotifierProvider` (`PlayerProvider`), que gestiona la playlist, la canción actual, el estado de reproducción y la sincronización de letras. La posición de reproducción vive en un `ValueNotifier` separado para evitar reconstrucciones de UI a 10 Hz.

Componentes principales:

- **`PlayerProvider`** — estado central de la app.
- **`MediaLibrary`** — abstracción de biblioteca musical, con implementaciones para SAF (Android) y sistema de archivos (escritorio/iOS).
- **`AudioEngine`** — motor de audio sobre `flutter_soloud`, encargado de mantener los 4 stems sincronizados en un mismo engine.
- **`PlayItAudioHandler`** — integración con `audio_service` para la sesión multimedia del sistema.
- **`lrc_parser`** — parser de letras en formato LRC.
- **`player_screen`** — pantalla única, con layouts adaptables según orientación/ancho.

Para más detalle técnico, ver [CLAUDE.md](CLAUDE.md).

### Stack técnico

Flutter · `flutter_soloud` (motor de audio) · `audio_service` (sesión multimedia) · `provider` (gestión de estado) · `file_picker` · `shared_preferences`

---

## English

**PlayIt Mobile** is a Flutter multi-stem audio player. Each song is split into 4 stems (drums, vocals, bass, other) that play in sample-accurate sync. Users can mute or adjust each stem independently (e.g. mute vocals for karaoke). It includes synced lyrics via LRC files.

### Features

- 4-stem playback, sample-accurate, sharing a single audio clock.
- Independent volume/mute control per stem.
- Synced lyrics (LRC format), with multi-line support.
- System media session integration (notification, lock screen, headset controls, background playback).
- Music library selection via Storage Access Framework (Android) or file picker (desktop/iOS) — **the app declares no storage permissions**, a requirement for Play Store publication.
- Adaptive UI for portrait/landscape and wide screens.

### Expected music library layout

Each song lives in its own folder:

```
<song folder>/
  data.json                 # {"Artist": {"Song Title": ...}}
  separated/drums.mp3
  separated/vocals.mp3
  separated/bass.mp3
  separated/other.mp3
  cover.png                 # optional
  lyrics.lrc                # optional
```

All 4 stems are mandatory for a song to be listed. `cover.png` and `lyrics.lrc` are optional.

### Commands

```bash
flutter pub get                      # install dependencies
flutter run                          # run on connected device/emulator
flutter analyze                      # lint (flutter_lints ruleset)
flutter test                         # run all tests
flutter test test/widget_test.dart   # run a single test file
flutter build apk                    # Android release build
```

### Architecture

App state flows through a single `ChangeNotifierProvider` (`PlayerProvider`), which owns the playlist, current song, playback status, and lyrics sync. Playback position lives in a separate `ValueNotifier` to avoid 10 Hz UI rebuilds.

Key components:

- **`PlayerProvider`** — the app's central state object.
- **`MediaLibrary`** — music library abstraction, with SAF (Android) and filesystem (desktop/iOS) implementations.
- **`AudioEngine`** — audio engine built on `flutter_soloud`, keeping all 4 stems in sync on one engine.
- **`PlayItAudioHandler`** — `audio_service` integration for the system media session.
- **`lrc_parser`** — LRC lyrics parser.
- **`player_screen`** — the app's single screen, with adaptive layouts by orientation/width.

See [CLAUDE.md](CLAUDE.md) for deeper technical detail.

### Tech stack

Flutter · `flutter_soloud` (audio engine) · `audio_service` (media session) · `provider` (state management) · `file_picker` · `shared_preferences`

---

## Licencia / License

Sin licencia definida aún. / No license defined yet.
