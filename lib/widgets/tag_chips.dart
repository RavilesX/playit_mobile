import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../utils/tags.dart';

/// A song's queue tags as removable chips plus a "+ tag" button.
///
/// Shared by the local and the remote queue sheets: the two keep their tags
/// in different places (this app's provider vs. the PC's playlist), so the
/// widget only renders and reports, and the caller does the writing.
class TagChips extends StatelessWidget {
  /// Raw comma-separated tag string, as both sides store it.
  final String tags;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  /// False while the tags can't be edited (remote disconnected), which
  /// greys the chips and drops the "+ tag" button.
  final bool enabled;

  const TagChips({
    super.key,
    required this.tags,
    required this.onAdd,
    required this.onRemove,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = splitTags(tags);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in parsed) _TagChip(
          tag: tag,
          enabled: enabled,
          onRemove: () => onRemove(tag),
        ),
        if (enabled)
          ActionChip(
            label: const Text('+ tag', style: TextStyle(fontSize: 11)),
            labelPadding: const EdgeInsets.symmetric(horizontal: 2),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: Colors.transparent,
            side: const BorderSide(color: AppColors.border),
            labelStyle: const TextStyle(color: AppColors.accentBlue),
            onPressed: () async {
              final tag = await showAddTagDialog(context, existing: parsed);
              if (tag != null) onAdd(tag);
            },
          ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String tag;
  final bool enabled;
  final VoidCallback onRemove;

  const _TagChip({
    required this.tag,
    required this.enabled,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    // A tag naming a stem is the one that does something (it mutes that
    // stem when the song plays from the queue), so it reads as active.
    final isStem = stemForTag(tag) != null;
    final color = !enabled
        ? AppColors.border
        : isStem
        ? AppColors.accentPurple
        : Colors.grey;
    return Chip(
      label: Text(tag, style: TextStyle(fontSize: 11, color: color)),
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: Colors.transparent,
      side: BorderSide(color: color),
      deleteIcon: const Icon(Icons.close, size: 13),
      deleteIconColor: color,
      onDeleted: enabled ? onRemove : null,
    );
  }
}

/// Asks for one tag: the four stems as one-tap suggestions (those are the
/// tags that actually mute something) plus free text for anything else.
/// Returns null when dismissed.
Future<String?> showAddTagDialog(
  BuildContext context, {
  List<String> existing = const [],
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final taken = {for (final t in existing) t.toLowerCase()};
      return AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Agregar tag',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Nombrar una pista la silencia al reproducir la canción desde '
              'la cola.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                for (final s in tagSuggestions)
                  ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.transparent,
                    side: const BorderSide(color: AppColors.accentPurple),
                    labelStyle: TextStyle(
                      color: taken.contains(s.toLowerCase())
                          ? AppColors.border
                          : Colors.white,
                    ),
                    onPressed: taken.contains(s.toLowerCase())
                        ? null
                        : () => Navigator.of(ctx).pop(s),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 40,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Otra tag…',
                counterText: '',
                hintStyle: TextStyle(color: AppColors.border),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accentPurple),
                ),
              ),
              onSubmitted: (v) =>
                  Navigator.of(ctx).pop(v.trim().isEmpty ? null : v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.border),
            ),
          ),
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              Navigator.of(ctx).pop(v.isEmpty ? null : v);
            },
            child: const Text(
              'Agregar',
              style: TextStyle(color: AppColors.accentBlue),
            ),
          ),
        ],
      );
    },
  );
}
