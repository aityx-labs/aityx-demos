import 'package:flutter/material.dart';

import '../api/poker_api.dart';
import '../game/controller.dart';
import '../theme.dart';

/// A sample situation to try a strategy on: on the button, facing a bet
/// on the flop with top pair.
const sampleSituation = <String, Object?>{
  'street': 'flop',
  'position': 'late',
  'hole': ['Ah', 'Kd'],
  'board': ['Ks', '7c', '2d'],
  'hand': 'strong',
  'made_hand': 'pair',
  'flush_draw': false,
  'straight_draw': 'none',
  'equity': 0.78,
  'pot': 120,
  'current_bet': 40,
  'to_call': 40,
  'pot_odds': 0.25,
  'can_check': false,
  'can_raise': true,
  'raises': 1,
  'stack': 960,
  'big_blind': 10,
  'stack_bb': 96,
  'min_raise': 80,
  'max_raise': 1000,
  'players_in_hand': 3,
  'players_after': 0,
  'random': 0.42,
};

/// Reads a preset's rules, or writes a strategy of your own, starting
/// from [from]: the JSON of its name, tagline and decisions. **Try it**
/// runs the rules on aityx on a sample situation; **Save** keeps them for
/// the players to use.
Future<void> showStrategyEditor(
  BuildContext context,
  GameController controller, {
  required Strategy from,
  Strategy? editing,
  bool writing = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 820),
        child: _StrategyEditor(
          controller: controller,
          from: from,
          editing: editing,
          writing: writing,
        ),
      ),
    ),
  );
}

class _StrategyEditor extends StatefulWidget {
  const _StrategyEditor({
    required this.controller,
    required this.from,
    required this.editing,
    required this.writing,
  });

  final GameController controller;
  final Strategy from;

  /// A new strategy, started from [from]: named after it, as yours.
  final bool writing;

  /// The custom strategy being changed, or null for a new one.
  final Strategy? editing;

  @override
  State<_StrategyEditor> createState() => _StrategyEditorState();
}

class _StrategyEditorState extends State<_StrategyEditor> {
  late final _text = TextEditingController(
    text: widget.from.toEditable(
      as: widget.writing ? 'My ${widget.from.name.split(' ').last}' : null,
    ),
  );
  String? _message;
  bool _failed = false;
  bool _trying = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _tryIt() async {
    final Strategy strategy;
    try {
      strategy = Strategy.parse(_text.text, id: 'try');
    } on FormatException catch (e) {
      setState(() {
        _message = e.message;
        _failed = true;
      });
      return;
    }
    setState(() {
      _trying = true;
      _message = null;
    });
    try {
      final r = await widget.controller.api.act(strategy, sampleSituation);
      setState(() {
        _failed = false;
        _message =
            'On the sample (A♥ K♦ on K♠ 7♣ 2♦, top pair, 40 to call into a pot '
            'of 120, 78% equity): ${r.kind.label.toLowerCase()}'
            '${r.kind.id == 'raise' ? ' to ${r.raiseTo}' : ''}'
            '${r.rule == null ? '' : ', rule ${r.rule}'}'
            '${r.why == null ? '' : ': ${r.why}'}'
            '${r.tookMs == null ? '' : ' (${r.tookMs} ms)'}';
      });
    } on ApiException catch (e) {
      setState(() {
        _failed = true;
        _message = e.message;
      });
    } finally {
      if (mounted) setState(() => _trying = false);
    }
  }

  void _save() {
    try {
      widget.controller.saveCustom(_text.text, replacing: widget.editing);
      Navigator.of(context).pop();
    } on FormatException catch (e) {
      setState(() {
        _message = e.message;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final editing = widget.editing;
    return Column(
      children: [
        AppBar(
          title: Text(
            editing != null
                ? 'Edit ${editing.name}'
                : widget.writing
                ? 'A strategy of your own, from ${widget.from.name}'
                : '${widget.from.name}: the rules',
          ),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'The decisions of the table model, run on aityx at every turn: '
            '"action" is a decision table over the situation (the first '
            'matching row wins; "why" explains it), "raise_to" the total bet '
            'when raising, and the rest whatever they need. Change the rules '
            "and save them as a strategy of your own; a preset's rules "
            'stay as they are.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('strategy-text'),
              controller: _text,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontFamily: 'RobotoMono',
                fontSize: 12.5,
                height: 1.4,
              ),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: scheme.surfaceContainerLowest,
              ),
            ),
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (_failed ? scheme.error : Aityx.green).withValues(
                  alpha: 0.12,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: _failed ? scheme.error : Aityx.green,
                    width: 3,
                  ),
                ),
              ),
              child: Text(_message!, style: theme.textTheme.bodySmall),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _trying ? null : _tryIt,
                icon: _trying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.science_outlined),
                label: const Text('Try it on aityx'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('save-strategy'),
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(editing != null ? 'Save' : 'Save as mine'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
