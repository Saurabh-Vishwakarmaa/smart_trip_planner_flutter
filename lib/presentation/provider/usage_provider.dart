import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

class UsageStats {
  final int inputTokens;
  final int outputTokens;
  final int cachedTokens;
  final int calls;
  final double costUsd;

  const UsageStats({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cachedTokens = 0,
    this.calls = 0,
    this.costUsd = 0,
  });

  int get totalTokens => inputTokens + outputTokens;

  UsageStats copyWith({
    int? inputTokens,
    int? outputTokens,
    int? cachedTokens,
    int? calls,
    double? costUsd,
  }) {
    return UsageStats(
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      cachedTokens: cachedTokens ?? this.cachedTokens,
      calls: calls ?? this.calls,
      costUsd: costUsd ?? this.costUsd,
    );
  }

  static const zero = UsageStats();
}

class UsageNotifier extends StateNotifier<UsageStats> {
  UsageNotifier({this.priceInPer1k = 0.0, this.priceOutPer1k = 0.0}) : super(UsageStats.zero);

  // Set your model pricing here (USD per 1K tokens)
  final double priceInPer1k;   // e.g., 0.50
  final double priceOutPer1k;  // e.g., 1.50

  void addCall({int input = 0, int output = 0, int cached = 0}) {
    final current = state;
    final cost = (input / 1000.0) * priceInPer1k + (output / 1000.0) * priceOutPer1k;
    state = current.copyWith(
      inputTokens: current.inputTokens + input,
      outputTokens: current.outputTokens + output,
      cachedTokens: current.cachedTokens + cached,
      calls: current.calls + 1,
      costUsd: double.parse((current.costUsd + cost).toStringAsFixed(4)),
    );
  }

  void reset() => state = UsageStats.zero;
}

final usageProvider = StateNotifierProvider<UsageNotifier, UsageStats>(
  (ref) => UsageNotifier(
    // Set pricing if you want costs; keep 0 for “token-only” display
    priceInPer1k: 0.0,
    priceOutPer1k: 0.0,
  ),
);