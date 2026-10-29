import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import '../engine/game.dart';
import '../game/controller.dart';
import '../players/rules_sheet.dart';
import '../theme.dart';
import 'avatar.dart';
import 'card_widget.dart';
import 'chips.dart';

/// The table: the felt, the seats around it with their avatars, cards,
/// chips and last actions, and in the middle the board, the pot and the
/// level.
class TableView extends StatelessWidget {
  const TableView({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final game = controller.game;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final compact = w < 760 || h < 520;
        final seatW = compact ? 150.0 : 178.0;
        final seatH = compact ? 112.0 : 124.0;
        // The seats sit on an ellipse just outside the felt; their bets on
        // a smaller one, inside it.
        final rx = math.max(w / 2 - seatW / 2 - 8, 60.0);
        final ry = math.max(h / 2 - seatH / 2 - 8, 40.0);
        final feltRx = rx - seatW * 0.38;
        final feltRy = ry - seatH * 0.42;
        final betRx = feltRx - 70;
        final betRy = feltRy - 44;
        final seats = game.seats;
        final n = seats.length;
        final winners = <Seat>{};
        if (controller.lastStep case HandOver(:final results)) {
          for (final r in results) {
            if (!r.uncalled) winners.addAll(r.winners);
          }
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // The felt.
            Positioned(
              left: w / 2 - feltRx,
              top: h / 2 - feltRy,
              width: feltRx * 2,
              height: feltRy * 2,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const RadialGradient(
                    colors: [Color(0xFF2E6B4F), Color(0xFF1E4A37)],
                    radius: 0.9,
                  ),
                  borderRadius: BorderRadius.all(
                    Radius.elliptical(feltRx, feltRy),
                  ),
                  border: Border.all(color: const Color(0xFF4A3A2A), width: 10),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 24),
                  ],
                ),
              ),
            ),
            // The board and the pot.
            Positioned.fill(
              child: Center(
                child: _Board(controller: controller, compact: compact),
              ),
            ),
            // Each seat's bet and, for the dealer, the button, between the
            // seat and the board.
            for (var i = 0; i < n; i++)
              if (seats[i].bet > 0 ||
                  (game.button == seats[i] && game.handInProgress))
                Positioned(
                  left: w / 2 + _unit(i, n).dx * betRx - 100,
                  top: h / 2 + _unit(i, n).dy * betRy - 14,
                  width: 200,
                  height: 28,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (game.button == seats[i] && game.handInProgress) ...[
                        const _DealerButton(),
                        const SizedBox(width: 6),
                      ],
                      if (seats[i].bet > 0)
                        ChipPile(seats[i].bet, chipWidth: 16, maxChips: 14),
                    ],
                  ),
                ),
            for (var i = 0; i < n; i++)
              Positioned(
                left: w / 2 + _unit(i, n).dx * rx - seatW / 2,
                top: h / 2 + _unit(i, n).dy * ry - seatH / 2,
                width: seatW,
                height: seatH,
                child: _SeatView(
                  seat: seats[i],
                  controller: controller,
                  compact: compact,
                  winner: winners.contains(seats[i]),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Seat i's place on the ellipse, starting at the bottom and going
  /// clockwise, so the first seat is nearest the viewer.
  static Offset _unit(int i, int n) {
    final angle = math.pi / 2 + 2 * math.pi * i / n;
    return Offset(math.cos(angle), math.sin(angle));
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.controller, required this.compact});

  final GameController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final game = controller.game;
    final theme = Theme.of(context);
    final cardH = compact ? 48.0 : 64.0;
    final step = controller.lastStep;
    String headline;
    if (game.over) {
      headline = '🏆 ${game.winner!.name} wins the tournament';
    } else if (!game.handInProgress) {
      headline = switch (step) {
        HandOver(:final hand, :final results) =>
          'Hand #$hand: ${_winnersLine(results)}',
        Waiting(:final reason) => reason,
        _ =>
          game.seats.length < 2
              ? 'Add players to deal.'
              : 'Press play to deal.',
      };
    } else {
      headline = 'Hand #${game.handNumber} · ${game.street!.label}';
    }
    final next = game.handsToNextLevel;
    final levelLine =
        'Level ${game.level} · blinds ${game.smallBlind}/${game.bigBlind}'
        '${next > 0 && game.level < PokerGame.levels.length ? ' · up in $next hand${next == 1 ? '' : 's'}' : ''}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          headline,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 5; i++) ...[
              if (i < game.board.length)
                CardWidget(game.board[i], height: cardH)
              else
                CardSlot(height: cardH),
              if (i < 4) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (game.pot > 0)
          ChipPile(game.pot, chipWidth: compact ? 16 : 20, maxChips: 30)
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Pot 0',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Aityx.amber,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          levelLine,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
        ),
      ],
    );
  }

  static String _winnersLine(List<PotResult> results) {
    final won = results.where((r) => !r.uncalled).toList();
    if (won.isEmpty) return 'nothing to win.';
    return won
        .map(
          (r) =>
              '${r.winners.map((w) => w.name).join(' & ')} '
              '${r.winners.length > 1 ? 'split' : 'wins'} '
              '${r.amount}${r.hand == null ? '' : ' with ${r.hand!.toLowerCase()}'}',
        )
        .join('; ');
  }
}

class _SeatView extends StatelessWidget {
  const _SeatView({
    required this.seat,
    required this.controller,
    required this.compact,
    required this.winner,
  });

  final Seat seat;
  final GameController controller;
  final bool compact;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final game = controller.game;
    final acting = controller.thinking?.seat == seat;
    final folded = seat.status == SeatStatus.folded;
    final out = seat.status == SeatStatus.out;
    final waiting = seat.status == SeatStatus.waiting;
    final champion = game.over && game.winner == seat;
    final strategy = controller.strategyOf(seat);
    final cardH = compact ? 40.0 : 46.0;
    final avatarSize = compact ? 40.0 : 46.0;
    final border = acting
        ? scheme.primary
        : winner || champion
        ? Aityx.amber
        : scheme.outline;
    final plate = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: folded || out || waiting
            ? Aityx.bg1.withValues(alpha: 0.85)
            : Aityx.bg0.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: border,
          width: acting || winner || champion ? 2 : 1,
        ),
        boxShadow: acting
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.35),
                  blurRadius: 12,
                ),
              ]
            : const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  seat.name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: folded || out
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                  ),
                ),
                Text(
                  strategy?.name ?? seat.strategyId,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontSize: compact ? 10 : 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                out ? ordinal(seat.place ?? 0) : '${seat.stack}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: out ? scheme.onSurfaceVariant : Aityx.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _status(game, champion),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: winner || champion
                      ? Aityx.amber
                      : seat.status == SeatStatus.allIn
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                  fontSize: compact ? 10 : 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final cardsWidth = cardH * 0.72 * 1.55;
    final top = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Avatar(
          seat: seat,
          size: avatarSize,
          acting: acting,
          winner: winner || champion,
          dim: out || waiting,
        ),
        const SizedBox(width: 6),
        if (seat.hole.isNotEmpty)
          SizedBox(
            width: cardsWidth,
            height: cardH,
            child: Stack(
              children: [
                CardWidget(seat.hole[0], height: cardH, dim: folded),
                Positioned(
                  left: cardH * 0.72 * 0.55,
                  child: CardWidget(seat.hole[1], height: cardH, dim: folded),
                ),
              ],
            ),
          )
        else if (!out)
          SizedBox(
            width: cardsWidth,
            height: cardH,
            child: Stack(
              children: [
                CardSlot(height: cardH),
                Positioned(
                  left: cardH * 0.72 * 0.55,
                  child: CardSlot(height: cardH),
                ),
              ],
            ),
          ),
        const Spacer(),
        if (!out && seat.stack > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: ChipPile(
              seat.stack,
              label: false,
              chipWidth: 13,
              maxChips: 16,
            ),
          ),
      ],
    );
    return Tooltip(
      message: 'The rules ${seat.name} plays by',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        key: Key('seat-${seat.id}'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => showPlayerRules(context, controller, seat),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: top,
            ),
            const SizedBox(height: 4),
            plate,
          ],
        ),
      ),
    );
  }

  String _status(PokerGame game, bool champion) {
    if (champion) return 'champion';
    if (winner) return 'wins';
    return switch (seat.status) {
      SeatStatus.waiting => 'next hand',
      SeatStatus.out => 'out',
      SeatStatus.folded => 'folded',
      SeatStatus.allIn => seat.lastAction ?? 'all in',
      SeatStatus.active =>
        seat.shownHand ?? seat.lastAction ?? (game.handInProgress ? '' : ' '),
    };
  }
}

/// The dealer button: a white disc with a D.
class _DealerButton extends StatelessWidget {
  const _DealerButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFFAF7F2),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: const Text(
        'D',
        style: TextStyle(
          color: Color(0xFF1B1B22),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
