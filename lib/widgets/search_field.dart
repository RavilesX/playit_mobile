import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Playlist search box, shared by the local playlist drawer and the remote
/// control screen so both filters look and behave the same.
///
/// Owns a controller instead of relying on the field's internal state: the
/// clear button changes the query from the outside, and without a controller
/// the typed text would stay on screen while the list showed everything.
class SearchField extends StatefulWidget {
  final String query;
  final ValueChanged<String> onChanged;
  final String hintText;

  const SearchField({
    super.key,
    required this.query,
    required this.onChanged,
    this.hintText = 'Buscar canción...',
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  @override
  void didUpdateWidget(SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hintText,
        hintStyle: const TextStyle(color: AppColors.border),
        prefixIcon: const Icon(Icons.search, color: AppColors.border, size: 20),
        suffixIcon: widget.query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(
                  Icons.clear,
                  color: AppColors.border,
                  size: 18,
                ),
                onPressed: () => widget.onChanged(''),
              ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
      ),
      onChanged: widget.onChanged,
    );
  }
}
