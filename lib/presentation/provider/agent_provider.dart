// lib/presentation/providers/agent_provider.dart
import 'dart:isolate';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:smart_trip_planner_flutter/data/services/agent_isolate.dart';

class AgentResult {
  AgentResult({required this.itinerary, required this.tokens, required this.aux});
  final Map<String, dynamic> itinerary; // Spec A
  final Map<String, dynamic> tokens;    // usage
  final Map<String, dynamic> aux;       // "d:i" -> meta
}

final agentPortProvider = FutureProvider<SendPort>((ref) async {
  final rp = ReceivePort();
  await Isolate.spawn(agentWorker, rp.sendPort);
  return await rp.first as SendPort;
});

class AgentNotifier extends StateNotifier<AsyncValue<AgentResult>> {
  AgentNotifier(this.ref) : super(AsyncValue.data(AgentResult(itinerary: const {}, tokens: const {}, aux: const {})));
  final Ref ref;

  Future<void> sendPrompt(String prompt, {String? prevJson}) async {
    state = const AsyncValue.loading(); // Creating…
    try {
      final sendPort = await ref.read(agentPortProvider.future);
      final response = ReceivePort();
      sendPort.send([prompt, prevJson, null, response.sendPort]);

      await for (final raw in response) {
        final msg = Map<String, dynamic>.from(raw as Map);
        switch (msg['type']) {
          case 'done':
            state = AsyncValue.data(AgentResult(
              itinerary: Map<String, dynamic>.from(msg['data'] as Map),
              tokens: Map<String, dynamic>.from((msg['tokens'] as Map?) ?? {}),
              aux: Map<String, dynamic>.from((msg['aux'] as Map?) ?? {}),
            ));
            response.close();
            return;
          case 'error':
            state = AsyncValue.error(msg['data'], StackTrace.current);
            response.close();
            return;
        }
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final agentStateProvider = StateNotifierProvider<AgentNotifier, AsyncValue<AgentResult>>((ref) => AgentNotifier(ref));
