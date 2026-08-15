import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../models/remote_state.dart';
import '../services/remote_discovery.dart';

/// Pairing screen: scan the desktop's QR, or type the same data by hand.
///
/// The manual fields are not a second-class fallback — scanning needs the
/// camera permission, and the remote has to keep working for anyone who
/// denies it (PLAN_REMOTO.md §6.2).
class RemotePairForm extends StatefulWidget {
  /// Called with validated data. The parent does the connecting.
  final Future<void> Function(PairingInfo info) onSubmit;

  /// Opens the QR scanner and returns what it read, or null if the user
  /// backed out. Injected by the parent so this widget never imports the
  /// camera — that keeps it testable and the camera code in one place.
  final Future<PairingInfo?> Function() onScan;

  /// Searches the local network for desktops. Fills in the address field so
  /// the user only has to copy the code — the token never travels by
  /// broadcast, so it still has to be scanned or typed.
  final Future<List<DiscoveredDesktop>> Function() onDiscover;

  /// Pre-fills the fields with the last PC used, if any.
  final PairingInfo? previous;

  final bool busy;

  const RemotePairForm({
    super.key,
    required this.onSubmit,
    required this.onScan,
    required this.onDiscover,
    this.previous,
    this.busy = false,
  });

  @override
  State<RemotePairForm> createState() => _RemotePairFormState();
}

class _RemotePairFormState extends State<RemotePairForm> {
  late final TextEditingController _address = TextEditingController(
    text: widget.previous?.address ?? '',
  );
  late final TextEditingController _token = TextEditingController(
    text: widget.previous?.token ?? '',
  );
  String? _error;
  bool _searching = false;

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.busy) return;
    FocusScope.of(context).unfocus();
    final PairingInfo info;
    try {
      info = PairingInfo.fromManual(_address.text, _token.text);
    } on RemotePairingException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() => _error = null);
    await widget.onSubmit(info);
  }

  Future<void> _scan() async {
    if (widget.busy) return;
    FocusScope.of(context).unfocus();
    final info = await widget.onScan();
    if (info == null || !mounted) return;
    // Fill the fields too: if the connection fails the user can see what was
    // read and fix a digit instead of scanning again.
    setState(() {
      _address.text = info.address;
      _token.text = info.token;
      _error = null;
    });
    await widget.onSubmit(info);
  }

  Future<void> _search() async {
    if (_searching || widget.busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
    });

    final found = await widget.onDiscover();
    if (!mounted) return;
    setState(() => _searching = false);

    if (found.isEmpty) {
      setState(() => _error =
          'No se encontró ninguna PC. Verificá que PlayIt esté abierto con el '
          'modo remoto activo, y que ambos estén en la misma red.');
      return;
    }

    final chosen = found.length == 1 ? found.first : await _pick(found);
    if (chosen == null || !mounted) return;
    setState(() => _address.text = '${chosen.host}:${chosen.port}');
  }

  Future<DiscoveredDesktop?> _pick(List<DiscoveredDesktop> found) {
    return showDialog<DiscoveredDesktop>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          '¿Cuál PC?',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        children: [
          for (final desktop in found)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(desktop),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.computer, color: AppColors.accentBlue),
                title: Text(
                  desktop.name,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${desktop.host}:${desktop.port}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        const Icon(Icons.settings_remote, size: 56, color: AppColors.accentBlue),
        const SizedBox(height: 16),
        const Text(
          'Controlar PlayIt Desktop',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'En la PC abrí Opciones → Modo remoto y escaneá el código QR que '
          'aparece.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentBlue,
              foregroundColor: Colors.black,
              disabledBackgroundColor: AppColors.border,
            ),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Escanear código QR'),
            onPressed: widget.busy ? null : _scan,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(child: Divider(color: AppColors.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'o escribilo a mano',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
            const Expanded(child: Divider(color: AppColors.border)),
          ],
        ),
        const SizedBox(height: 18),
        _Field(
          controller: _address,
          label: 'Dirección de la PC',
          hint: '192.168.1.42:$kDefaultRemotePort',
          icon: Icons.computer,
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _submit(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColors.accentBlue),
            icon: _searching
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accentBlue,
                    ),
                  )
                : const Icon(Icons.wifi_find, size: 18),
            label: Text(
              _searching ? 'Buscando...' : 'Buscar PC en la red',
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: _searching || widget.busy ? null : _search,
          ),
        ),
        const SizedBox(height: 4),
        _Field(
          controller: _token,
          label: 'Código',
          hint: '9f2c 4d1a …',
          icon: Icons.vpn_key,
          // Hex only: keeps a stray space or accent from turning into a 401
          // that looks like the PC rejected a perfectly good code.
          formatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F ]')),
          ],
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.pinkText, fontSize: 13),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentPurple,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.border,
            ),
            icon: widget.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.link),
            label: Text(widget.busy ? 'Conectando...' : 'Conectar'),
            onPressed: widget.busy ? null : _submit,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Ambos equipos tienen que estar en la misma red Wi-Fi. Las redes de '
          'invitados suelen aislar los dispositivos entre sí y no funcionan.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.border, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final ValueChanged<String>? onSubmitted;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.formatters,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      keyboardType: keyboardType,
      inputFormatters: formatters,
      autocorrect: false,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.border),
        prefixIcon: Icon(icon, color: AppColors.accentBlue, size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accentPurple),
        ),
      ),
    );
  }
}
