import 'package:flutter/material.dart';

import 'samples.dart';
import 'voice_input.dart';

/// Where someone types their request, dictates it with the microphone
/// button beside the field, or picks a sample, and sends it.
class RequestBox extends StatefulWidget {
  const RequestBox({super.key, required this.onSubmit, this.voice});

  /// Receives the request's text, trimmed and not empty.
  final ValueChanged<String> onSubmit;

  /// Dictation: the browser's unless a test says.
  final VoiceInput? voice;

  @override
  State<RequestBox> createState() => _RequestBoxState();
}

class _RequestBoxState extends State<RequestBox> {
  final _controller = TextEditingController();
  late final VoiceInput _voice = widget.voice ?? VoiceInput();

  VoiceEngine _engine = VoiceEngine.unsupported;
  VoiceState _state = VoiceState.idle;
  double? _progress;
  String? _error;

  /// The field's text when dictation started; dictated words go after it.
  String _before = '';

  bool get _dictating => _state != VoiceState.idle;

  /// Which dictation the callbacks belong to: one that was abandoned (for
  /// a sample) may still send text, which is then ignored.
  int _session = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _voice.engine().then((engine) {
      if (mounted) setState(() => _engine = engine);
    });
  }

  @override
  void dispose() {
    if (_dictating) _voice.stop();
    _controller.dispose();
    super.dispose();
  }

  void _toggleDictation() {
    if (_state == VoiceState.listening) {
      _voice.stop();
      return;
    }
    if (_dictating) return;
    _before = _controller.text.trim();
    final session = ++_session;
    bool current() => mounted && session == _session;
    setState(() {
      _error = null;
      _state = VoiceState.listening;
    });
    _voice.start(
      onState: (state, progress) {
        if (!current()) return;
        setState(() {
          _state = state;
          _progress = progress;
        });
      },
      onText: (text, isFinal) {
        if (!current()) return;
        final joined = [_before, text.trim()].where((s) => s.isNotEmpty);
        _controller.value = TextEditingValue(
          text: joined.join(' '),
          selection: TextSelection.collapsed(offset: joined.join(' ').length),
        );
      },
      onError: (message) {
        if (current()) setState(() => _error = message);
      },
    );
  }

  /// Puts [sample] in the field, in place of what was there.
  void _useSample(SampleRequest sample) {
    if (_dictating) {
      _session++; // what that dictation still sends is ignored
      _voice.stop();
    }
    setState(() {
      _error = null;
      _state = VoiceState.idle;
      _progress = null;
    });
    _controller.value = TextEditingValue(
      text: sample.text,
      selection: TextSelection.collapsed(offset: sample.text.length),
    );
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || _dictating) return;
    widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSend = _controller.text.trim().isNotEmpty && !_dictating;
    final status = _statusText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 3,
                maxLines: 6,
                readOnly: _dictating,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'Your request',
                  hintText: _engine == VoiceEngine.unsupported
                      ? 'What do you need?'
                      : 'What do you need? Type it, or tap the mic and say it.',
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            if (_engine != VoiceEngine.unsupported) ...[
              const SizedBox(width: 8),
              _MicButton(
                state: _state,
                progress: _progress,
                onPressed: _toggleDictation,
              ),
            ],
          ],
        ),
        if (status != null) ...[
          const SizedBox(height: 8),
          Text(
            status,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _error != null
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            _SampleMenu(onSelected: _useSample),
            const Spacer(),
            FilledButton.icon(
              onPressed: canSend ? _submit : null,
              icon: const Icon(Icons.send_outlined),
              label: const Text('Send'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The line under the field: an error, or what dictation is doing.
  String? _statusText() {
    if (_error != null) return _error;
    return switch (_state) {
      VoiceState.downloading => switch (_progress) {
        final p? =>
          'Downloading the speech model, ${(p * 100).round()}% '
              '(first time only)…',
        null =>
          'Preparing speech recognition on this device (first time only)…',
      },
      VoiceState.starting =>
        'Starting the microphone… allow it if your browser asks.',
      VoiceState.listening =>
        'Listening… tap the stop button when you\'re done.',
      VoiceState.transcribing => 'Turning your words into text…',
      VoiceState.idle => null,
    };
  }
}

/// The microphone beside the field: a mic to start, a stop button while
/// listening, a spinner while it downloads or transcribes.
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.state,
    required this.progress,
    required this.onPressed,
  });

  final VoiceState state;
  final double? progress;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (state) {
      VoiceState.idle => IconButton.filledTonal(
        onPressed: onPressed,
        tooltip: 'Dictate (speech stays on this device)',
        icon: const Icon(Icons.mic_none),
      ),
      VoiceState.listening => IconButton.filled(
        onPressed: onPressed,
        tooltip: 'Stop dictating',
        style: IconButton.styleFrom(
          backgroundColor: scheme.error,
          foregroundColor: scheme.onError,
        ),
        icon: const Icon(Icons.stop),
      ),
      VoiceState.downloading ||
      VoiceState.starting ||
      VoiceState.transcribing => SizedBox.square(
        dimension: 48,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: CircularProgressIndicator(
            strokeWidth: 3,
            value: state == VoiceState.downloading ? progress : null,
            semanticsLabel: switch (state) {
              VoiceState.downloading => 'Downloading the speech model',
              VoiceState.starting => 'Starting the microphone',
              _ => 'Transcribing',
            },
          ),
        ),
      ),
    };
  }
}

/// "Try a sample": a menu of ready-made requests (one for each order
/// policy, one for each other department, and a few for the checks);
/// picking one fills the field.
class _SampleMenu extends StatelessWidget {
  const _SampleMenu({required this.onSelected});

  final ValueChanged<SampleRequest> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget item(SampleRequest sample) => MenuItemButton(
      onPressed: () => onSelected(sample),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(sample.title, style: theme.textTheme.bodyLarge),
              Text(
                sample.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return MenuAnchor(
      style: const MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(460, 480)),
      ),
      menuChildren: [
        heading("ORDERS: THE STORE'S POLICY"),
        for (final s in policySamples) item(s),
        const Divider(),
        heading('THE OTHER DEPARTMENTS'),
        for (final s in departmentSamples)
          if (!policySamples.contains(s)) item(s),
        const Divider(),
        heading('THE CHECKS'),
        for (final s in checkSamples) item(s),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.list_alt),
        label: const Text('Try a sample'),
      ),
    );
  }
}
