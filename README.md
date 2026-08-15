<div align="center">

<img src="assets/icons/main_icon.png" width="120" alt="PlayIt Mobile logo" />

# PlayIt Mobile

Reproductor de audio multi-stem para Flutter. / A multi-stem audio player built with Flutter.

**⚠️ Solo reproduce: la separación de stems la hace [PlayIt Desktop](https://github.com/RavilesX/playit).**<br/>
**⚠️ Player only: stem separation is done by [PlayIt Desktop](https://github.com/RavilesX/playit).**

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Desktop-informational)
![Version](https://img.shields.io/badge/version-1.3.0-blue)
[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

</div>

---

## Español

> Port móvil del proyecto original [PlayIt](https://github.com/RavilesX/playit) (GPL-3.0).

**PlayIt Mobile** es un reproductor de audio para Flutter que separa cada canción en 4 stems (batería, voz, bajo y otros) reproducidos en sincronía sample-accurate. El usuario puede silenciar o ajustar el volumen de cada stem de forma independiente (por ejemplo, silenciar la voz para hacer karaoke). Incluye letras sincronizadas mediante archivos LRC.

### ✨ Características

- Reproducción de 4 stems perfectamente sincronizados sobre un único reloj de muestreo.
- Control de volumen y mute independiente por stem.
- Letras sincronizadas (formato LRC), con soporte multi-línea.
- Integración con la sesión multimedia del sistema (notificación, pantalla de bloqueo, controles del auricular, reproducción en segundo plano).
- Selección de biblioteca musical mediante Storage Access Framework (Android) o selector de archivos (escritorio/iOS) — **la app no declara permisos de almacenamiento**, requisito para publicación en Play Store.
- Interfaz adaptable a orientación vertical y horizontal / pantallas anchas.
- Buscador de actualizaciones integrado: consulta las publicaciones de este repositorio (menú ⋮ → *Buscar actualizaciones*). El aviso automático se puede desactivar en *Acerca de*.

### ⚠️ Requisito previo: PlayIt Desktop

> **PlayIt Mobile no separa canciones en stems. Es únicamente un reproductor.**

La separación de audio la hace el proyecto de escritorio [**PlayIt**](https://github.com/RavilesX/playit). PlayIt Mobile solo reproduce carpetas que ya vienen separadas: si intentas abrir un MP3 normal, no aparecerá en la biblioteca.

**Flujo de trabajo completo:**

1. **En el PC** — procesa la canción con PlayIt Desktop. Genera una carpeta por canción con `data.json`, los 4 stems dentro de `separated/`, y opcionalmente la portada y las letras.
2. **Copia esas carpetas al móvil** — por USB, tarjeta SD, o el método que prefieras. Colócalas todas dentro de una misma carpeta contenedora, que será tu biblioteca.

   ```
   Musica/                       ← esta es la carpeta que seleccionas
     Artista - Canción 1/        ← carpeta generada por PlayIt Desktop
     Artista - Canción 2/
     ...
   ```

3. **En el móvil** — pulsa el botón 📂 de la barra superior y selecciona la carpeta contenedora. Android pedirá permiso mediante el selector del sistema; el permiso queda guardado y no hay que repetirlo en cada arranque.
4. La app recorre esa carpeta de forma recursiva buscando archivos `data.json` y arma la biblioteca sola.

**Si una canción no aparece**, casi siempre es porque a su carpeta le falta `data.json` o alguno de los 4 stems. Una canción con stems incompletos se omite a propósito.

### 📁 Estructura esperada de la biblioteca musical

Cada canción vive en su propia carpeta (esto es exactamente lo que produce PlayIt Desktop):

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

### ⚙️ Comandos

```bash
flutter pub get                      # instalar dependencias
flutter run                          # ejecutar en un dispositivo/emulador conectado
flutter analyze                      # linter (reglas flutter_lints)
flutter test                         # ejecutar todos los tests
flutter test test/widget_test.dart   # ejecutar un test específico
flutter build apk                    # build de release para Android
```

### 🏗️ Arquitectura

El estado de la app fluye a través de un único `ChangeNotifierProvider` (`PlayerProvider`), que gestiona la playlist, la canción actual, el estado de reproducción y la sincronización de letras. La posición de reproducción vive en un `ValueNotifier` separado para evitar reconstrucciones de UI a 10 Hz.

Componentes principales:

- **`PlayerProvider`** — estado central de la app.
- **`MediaLibrary`** — abstracción de biblioteca musical, con implementaciones para SAF (Android) y sistema de archivos (escritorio/iOS).
- **`AudioEngine`** — motor de audio sobre `flutter_soloud`, encargado de mantener los 4 stems sincronizados en un mismo engine.
- **`PlayItAudioHandler`** — integración con `audio_service` para la sesión multimedia del sistema.
- **`lrc_parser`** — parser de letras en formato LRC.
- **`player_screen`** — pantalla única, con layouts adaptables según orientación/ancho.


### 🧩 Stack técnico

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![flutter_soloud](https://img.shields.io/badge/flutter__soloud-audio%20engine-orange)
![audio_service](https://img.shields.io/badge/audio__service-sesi%C3%B3n%20multimedia-purple)
![provider](https://img.shields.io/badge/provider-gesti%C3%B3n%20de%20estado-green)
![file_picker](https://img.shields.io/badge/file__picker-selector%20de%20archivos-yellow)
![shared_preferences](https://img.shields.io/badge/shared__preferences-persistencia-lightblue)

---

## English

> Mobile port of the upstream [PlayIt](https://github.com/RavilesX/playit) project (GPL-3.0).

**PlayIt Mobile** is a Flutter multi-stem audio player. Each song is split into 4 stems (drums, vocals, bass, other) that play in sample-accurate sync. Users can mute or adjust each stem independently (e.g. mute vocals for karaoke). It includes synced lyrics via LRC files.

### ✨ Features

- 4-stem playback, sample-accurate, sharing a single audio clock.
- Independent volume/mute control per stem.
- Synced lyrics (LRC format), with multi-line support.
- System media session integration (notification, lock screen, headset controls, background playback).
- Music library selection via Storage Access Framework (Android) or file picker (desktop/iOS) — **the app declares no storage permissions**, a requirement for Play Store publication.
- Adaptive UI for portrait/landscape and wide screens.
- Built-in update checker: queries this repository's releases (⋮ menu → *Buscar actualizaciones*). The automatic prompt can be turned off in *Acerca de*.

### ⚠️ Prerequisite: PlayIt Desktop

> **PlayIt Mobile does not separate songs into stems. It is a player only.**

Source separation is done by the desktop project [**PlayIt**](https://github.com/RavilesX/playit). PlayIt Mobile only plays folders that are already separated: a plain MP3 will not show up in the library.

**Full workflow:**

1. **On your PC** — process the song with PlayIt Desktop. It produces one folder per song containing `data.json`, the 4 stems under `separated/`, and optionally cover art and lyrics.
2. **Copy those folders to your phone** — over USB, an SD card, or whatever you prefer. Put them all inside a single parent folder, which becomes your library.

   ```
   Music/                        ← this is the folder you select
     Artist - Song 1/            ← folder produced by PlayIt Desktop
     Artist - Song 2/
     ...
   ```

3. **On the phone** — tap the 📂 button in the top bar and pick the parent folder. Android asks for access through the system picker; the grant is persisted, so you only do this once.
4. The app walks that folder recursively looking for `data.json` files and builds the library on its own.

**If a song doesn't show up**, it's almost always because its folder is missing `data.json` or one of the 4 stems. Songs with incomplete stems are skipped on purpose.

### 📁 Expected music library layout

Each song lives in its own folder (exactly what PlayIt Desktop produces):

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

### ⚙️ Commands

```bash
flutter pub get                      # install dependencies
flutter run                          # run on connected device/emulator
flutter analyze                      # lint (flutter_lints ruleset)
flutter test                         # run all tests
flutter test test/widget_test.dart   # run a single test file
flutter build apk                    # Android release build
```

### 🏗️ Architecture

App state flows through a single `ChangeNotifierProvider` (`PlayerProvider`), which owns the playlist, current song, playback status, and lyrics sync. Playback position lives in a separate `ValueNotifier` to avoid 10 Hz UI rebuilds.

Key components:

- **`PlayerProvider`** — the app's central state object.
- **`MediaLibrary`** — music library abstraction, with SAF (Android) and filesystem (desktop/iOS) implementations.
- **`AudioEngine`** — audio engine built on `flutter_soloud`, keeping all 4 stems in sync on one engine.
- **`PlayItAudioHandler`** — `audio_service` integration for the system media session.
- **`lrc_parser`** — LRC lyrics parser.
- **`player_screen`** — the app's single screen, with adaptive layouts by orientation/width.


### 🧩 Tech stack

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![flutter_soloud](https://img.shields.io/badge/flutter__soloud-audio%20engine-orange)
![audio_service](https://img.shields.io/badge/audio__service-media%20session-purple)
![provider](https://img.shields.io/badge/provider-state%20management-green)
![file_picker](https://img.shields.io/badge/file__picker-file%20selector-yellow)
![shared_preferences](https://img.shields.io/badge/shared__preferences-persistence-lightblue)

---

## 🤝 Contribuir / Contributing

Las contribuciones son bienvenidas. Lee [CONTRIBUTING.md](CONTRIBUTING.md) antes de abrir un pull request: toda contribución requiere aceptar el [CLA](CLA.md) (una sola vez, con un comentario en tu primer PR). Conservas el copyright de tu código.

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request: every contribution requires accepting the [CLA](CLA.md) (once, via a comment on your first PR). You keep the copyright to your code.

---

## 📄 Licencia / License

### Español

Este proyecto se distribuye bajo la **GNU General Public License v3.0** (GPL-3.0), la misma licencia del proyecto original [PlayIt](https://github.com/RavilesX/playit), del que PlayIt Mobile es el port a móvil.

Esto significa que puedes usar, estudiar, modificar y redistribuir el código libremente, siempre que cualquier obra derivada se distribuya también bajo GPL-3.0 y publique su código fuente. El programa se ofrece **sin ninguna garantía**.

El texto completo de la licencia está en el archivo [LICENSE](LICENSE).

```
PlayIt Mobile — reproductor de audio multi-stem.
Copyright (C) 2026 RavilesX

Este programa es software libre: puedes redistribuirlo y/o modificarlo
bajo los términos de la GNU General Public License publicada por la
Free Software Foundation, ya sea la versión 3 de la licencia o (a tu
elección) cualquier versión posterior.
```

### English

This project is licensed under the **GNU General Public License v3.0** (GPL-3.0) — the same license as the upstream project [PlayIt](https://github.com/RavilesX/playit), of which PlayIt Mobile is the mobile port.

You are free to use, study, modify and redistribute the code, provided any derivative work is also distributed under GPL-3.0 with its source code available. The program comes with **no warranty**.

The full license text is in the [LICENSE](LICENSE) file.

```
PlayIt Mobile — multi-stem audio player.
Copyright (C) 2026 RavilesX

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
```

> Nota: las dependencias de terceros (`flutter_soloud`, `audio_service`, `provider`, …) conservan sus propias licencias. / Note: third-party dependencies keep their own licenses.
