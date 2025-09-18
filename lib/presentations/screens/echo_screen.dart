// lib/presentation/screens/agent_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_trip_planner_flutter/presentation/provider/agent_provider.dart';


class AgentScreen extends ConsumerWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("AI Agent Test")),
      body: Column(
        children: [
          Expanded(
            child: ListView(

              children: [ Center(
                child: state.when(
                  data: (data) => Text(data, style: const TextStyle(fontSize: 18)),
                  error: (e, _) => Text("Error: $e"),
                  loading: () => const CircularProgressIndicator(),
                ),
              ),
              ]
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              onSubmitted: (value) {
                ref.read(agentStateProvider.notifier).sendPrompt(value);
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "Ask me anything...",
              ),
            ),
          ),
        ],
      ),
    );
  }
}
