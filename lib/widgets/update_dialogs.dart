import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_colors.dart';
import '../services/update_checker.dart';

/// Version of the running build, straight from the packaging (Android
/// versionName / pubspec `version`), so it can't drift from what shipped.
Future<String> currentAppVersion() async =>
    (await PackageInfo.fromPlatform()).version;

Future<void> _openUrl(BuildContext context, String url) async {
  final ok = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el navegador.')),
    );
  }
}

/// Manual check: shows a progress dialog, then the result either way.
Future<void> runManualUpdateCheck(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _CheckingDialog(),
  );

  final current = await currentAppVersion();
  ReleaseInfo? release;
  String? error;
  try {
    release = await UpdateChecker().checkForUpdate(current);
    await UpdateChecker.markChecked();
  } on UpdateCheckException catch (e) {
    error = e.message;
  }

  if (!context.mounted) return;
  Navigator.of(context).pop(); // close the progress dialog

  if (error != null) {
    messenger.showSnackBar(
      SnackBar(content: Text('No se pudo comprobar: $error')),
    );
    return;
  }
  if (release == null) {
    messenger.showSnackBar(
      SnackBar(content: Text('Ya tienes la última versión ($current).')),
    );
    return;
  }
  await showUpdateAvailableDialog(context, release, current);
}

class _CheckingDialog extends StatelessWidget {
  const _CheckingDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      backgroundColor: Colors.black,
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 16),
          Text(
            'Buscando actualizaciones…',
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// Shown when a newer release exists. [skippable] adds the "skip this
/// version" action used by the silent startup check.
Future<void> showUpdateAvailableDialog(
  BuildContext context,
  ReleaseInfo release,
  String currentVersion, {
  bool skippable = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.accentPurple),
      ),
      title: const Text(
        'Actualización disponible',
        style: TextStyle(color: AppColors.accentBlue),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Versión $currentVersion → ${release.version}',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            if (release.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Novedades',
                style: TextStyle(color: AppColors.accentPurple, fontSize: 13),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Text(
                    release.notes.trim(),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (skippable)
          TextButton(
            onPressed: () {
              UpdateChecker.skipVersion(release.version);
              Navigator.of(ctx).pop();
            },
            child: const Text(
              'Omitir versión',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Ahora no', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            _openUrl(context, release.apkUrl ?? release.pageUrl);
          },
          child: Text(
            release.apkUrl != null ? 'Descargar APK' : 'Ver publicación',
            style: const TextStyle(color: AppColors.accentBlue),
          ),
        ),
      ],
    ),
  );
}

/// About box — also where the GPL notice lives, as the license recommends.
Future<void> showAboutPlayItDialog(BuildContext context) async {
  final version = await currentAppVersion();
  final autoCheck = await UpdateChecker.autoCheckEnabled();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => _AboutDialog(version: version, autoCheck: autoCheck),
  );
}

class _AboutDialog extends StatefulWidget {
  final String version;
  final bool autoCheck;
  const _AboutDialog({required this.version, required this.autoCheck});

  @override
  State<_AboutDialog> createState() => _AboutDialogState();
}

class _AboutDialogState extends State<_AboutDialog> {
  late bool _autoCheck = widget.autoCheck;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.accentPurple),
      ),
      title: Row(
        children: [
          Image.asset('assets/icons/main_icon.png', width: 32, height: 32),
          const SizedBox(width: 12),
          const Text(
            'Play It',
            style: TextStyle(color: AppColors.accentBlue),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Versión ${widget.version}',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 12),
          const Text(
            'Reproductor de audio multi-stem.\n'
            'Copyright (C) 2026 RavilesX\n\n'
            'Este programa es software libre bajo la licencia GNU GPL v3, '
            'y se ofrece SIN NINGUNA GARANTÍA.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _autoCheck,
            activeThumbColor: AppColors.accentPurple,
            title: const Text(
              'Buscar actualizaciones al iniciar',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
            subtitle: const Text(
              'Una consulta a GitHub, como mucho una vez al día.',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
            onChanged: (v) {
              setState(() => _autoCheck = v);
              UpdateChecker.setAutoCheckEnabled(v);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _openUrl(context, kRepoUrl),
          child: const Text(
            'Repositorio',
            style: TextStyle(color: Colors.grey),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cerrar',
            style: TextStyle(color: AppColors.accentBlue),
          ),
        ),
      ],
    );
  }
}
