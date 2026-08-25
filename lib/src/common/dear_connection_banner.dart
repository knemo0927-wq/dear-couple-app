import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityResultsProvider = StreamProvider<List<ConnectivityResult>>(
  (ref) async* {
    final connectivity = Connectivity();
    yield await connectivity.checkConnectivity();
    yield* connectivity.onConnectivityChanged;
  },
);

class DearConnectionBanner extends ConsumerWidget {
  const DearConnectionBanner({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(connectivityResultsProvider).valueOrNull;
    final offline = results != null &&
        (results.isEmpty ||
            results.every((item) => item == ConnectivityResult.none));
    if (!offline) return child;

    return Column(
      children: [
        Semantics(
          liveRegion: true,
          label: '오프라인. 마지막으로 불러온 내용을 표시하고 있어요.',
          child: const Material(
            color: Color(0xFF5F4A54),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '오프라인 · 마지막으로 불러온 내용을 표시해요',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
