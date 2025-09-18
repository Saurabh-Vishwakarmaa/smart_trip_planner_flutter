// lib/presentation/providers/agent_provider.dart
import 'dart:isolate';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../data/services/agent_isolate.dart';

final agentProvider = FutureProvider<SendPort>((ref) async {
  final receivePort = ReceivePort();
  await Isolate.spawn(agentWorker, receivePort.sendPort);
  return await receivePort.first as SendPort;
});

class AgentNotifier extends StateNotifier<AsyncValue<String>> {
  AgentNotifier(this.ref) : super(const AsyncValue.data(""));

  final Ref ref;

  Future<void> sendPrompt(String prompt) async {
    state = const AsyncValue.loading();

    try {
      final sendPort = await ref.read(agentProvider.future);
      final responsePort = ReceivePort();

      sendPort.send([prompt, responsePort.sendPort]);

      final result = await responsePort.first as Map<String, dynamic>;

      if (result["ok"] == true) {
        state = AsyncValue.data(result["data"]);
      } else {
        state = AsyncValue.error(result["error"], StackTrace.current);
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final agentStateProvider =
    StateNotifierProvider<AgentNotifier, AsyncValue<String>>(
        (ref) => AgentNotifier(ref));
