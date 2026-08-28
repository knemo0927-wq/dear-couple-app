import 'package:flutter/material.dart';

Future<void> showOmokRulesSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '오목 규칙',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 16),
            const _RuleRow(
              number: '1',
              text: '흑이 먼저 두고, 서로 한 번씩 빈 교차점에 돌을 놓아요.',
            ),
            const _RuleRow(
              number: '2',
              text: '가로·세로·대각선 중 한 방향으로 돌 5개를 먼저 이으면 승리해요.',
            ),
            const _RuleRow(
              number: '3',
              text: '한 턴의 제한 시간은 30초예요. 시간이 끝나면 상대가 승리해요.',
            ),
            const _RuleRow(
              number: '4',
              text: '기권하면 즉시 대국이 종료되고 전적에 기록돼요.',
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: ValueKey('omok-rule-number-$number'),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
