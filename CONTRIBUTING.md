# Contribuir a PlayIt Mobile / Contributing to PlayIt Mobile

## Español

Gracias por tu interés. Antes de abrir un pull request:

### 1. Acepta el CLA

Toda contribución requiere aceptar el [Contributor License Agreement](CLA.md).
Se acepta **una sola vez** y cubre todas tus contribuciones futuras: basta un
comentario en tu primer pull request con el texto indicado en la
[sección 7 del CLA](CLA.md#7-cómo-aceptar-este-acuerdo).

Conservas el copyright de tu código. El CLA solo concede al mantenedor los
derechos necesarios para poder relicenciar el proyecto en el futuro (por
ejemplo, para publicarlo en tiendas incompatibles con la GPL-3) sin tener que
pedir permiso a cada contribuyente.

### 2. Requisitos técnicos

Antes de enviar, tu rama debe pasar:

```bash
flutter analyze    # sin issues
flutter test       # todos los tests en verde
```

- Sigue el estilo del código existente (reglas de `flutter_lints`).
- Las cadenas de la interfaz están en español.
- **No añadas permisos de almacenamiento** al manifest de Android: la app se
  publica en Play Store y Google rechaza `MANAGE_EXTERNAL_STORAGE` para apps de
  música. El acceso a archivos va por Storage Access Framework.
- **No añadas `google_fonts`**: requiere el permiso `INTERNET` y descarga en
  tiempo de ejecución. La fuente va empaquetada en `assets/fonts/`.
- Si tu cambio afecta a la arquitectura, actualiza [CLAUDE.md](CLAUDE.md).

### 3. Pull request

- Un pull request por cambio lógico.
- Describe **qué** cambia y **por qué**.
- Si tocas la interfaz, adjunta capturas (vertical y horizontal).
- Si tu código incluye trabajo de terceros, indícalo con su licencia.

---

## English

Thanks for your interest. Before opening a pull request:

### 1. Accept the CLA

Every contribution requires accepting the
[Contributor License Agreement](CLA.md). You accept it **once** and it covers
all your future contributions: post a comment on your first pull request with
the text given in [section 7 of the CLA](CLA.md#7-how-to-accept-this-agreement).

You keep the copyright to your code. The CLA only grants the maintainer the
rights needed to relicense the project in the future (for example, to publish it
on stores incompatible with GPL-3) without having to ask every contributor for
permission.

### 2. Technical requirements

Before submitting, your branch must pass:

```bash
flutter analyze    # no issues
flutter test       # all tests green
```

- Follow the existing code style (`flutter_lints` ruleset).
- UI strings are in Spanish.
- **Do not add storage permissions** to the Android manifest: the app ships on
  the Play Store and Google rejects `MANAGE_EXTERNAL_STORAGE` for music apps.
  File access goes through the Storage Access Framework.
- **Do not add `google_fonts`**: it requires the `INTERNET` permission and
  runtime fetching. The font is bundled in `assets/fonts/`.
- If your change affects the architecture, update [CLAUDE.md](CLAUDE.md).

### 3. Pull request

- One pull request per logical change.
- Describe **what** changes and **why**.
- If you touch the UI, attach screenshots (portrait and landscape).
- If your code includes third-party work, state it along with its license.
