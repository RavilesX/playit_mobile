import '../services/audio_engine.dart';
import 'text_fold.dart';

/// Queue tags: a comma-separated string on the song (desktop stores it the
/// same way, as `song['tags']`), parsed here into the chips the UI shows.
///
/// Pure functions, unit-tested — the provider and both queue sheets (local
/// and remote) share them so a tag means the same thing everywhere.

/// Splits a tag string into trimmed, non-empty tags, in order.
List<String> splitTags(String raw) => [
  for (final part in raw.split(','))
    if (part.trim().isNotEmpty) part.trim(),
];

/// Stem names as the user writes them in a tag, folded (lowercase, no
/// accents) before lookup — desktop's `_TAG_TRACK_ALIASES`. Both languages'
/// spellings are accepted so a tag typed on either side means the same.
const _stemAliases = <String, String>{
  'bateria': 'drums',
  'drums': 'drums',
  'voz': 'vocals',
  'vocal': 'vocals',
  'vocales': 'vocals',
  'vocals': 'vocals',
  'bajo': 'bass',
  'bass': 'bass',
  'otros': 'other',
  'otro': 'other',
  'other': 'other',
};

/// The stem [tag] names, or null when it names none (a plain note like
/// "ensayo" or "tono alto").
String? stemForTag(String tag) => _stemAliases[foldText(tag.trim())];

/// Stems named by [raw]'s tags — the ones to mute when the song is played
/// from the queue (desktop's `_apply_tag_mutes`). Empty means "the tags say
/// nothing about the mix", and the current mute state is left alone.
Set<String> stemsNamedBy(String raw) => {
  for (final tag in splitTags(raw))
    if (stemForTag(tag) != null) stemForTag(tag)!,
};

/// Suggestions offered by the "+ tag" button: the four stems in the app's
/// own wording, which are the tags that actually do something.
const tagSuggestions = <String>['Batería', 'Voz', 'Bajo', 'Otros'];

/// Guard so a tag string can't be used as arbitrary storage — mirrors the
/// desktop server's MAX_TAGS_LEN, which rejects anything longer.
const maxTagsLength = 200;

/// Label for [stem] in the app's Spanish UI, for the auto-mute hint.
String stemLabel(String stem) => switch (stem) {
  'drums' => 'Batería',
  'vocals' => 'Voz',
  'bass' => 'Bajo',
  'other' => 'Otros',
  _ => stem,
};

/// Every stem the mix knows about, for callers applying [stemsNamedBy].
List<String> get allStems => stemNames;
