import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_trip_planner_flutter/presentation/provider/connectivity_provider.dart';
import 'package:smart_trip_planner_flutter/presentation/provider/usage_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider);
    final usage = ref.watch(usageProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Row(
              children: [
                const CircleAvatar(radius: 28, backgroundColor: Color(0xFF10B981), child: Text('S', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                    Text('Shubham', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('smart_trip_planner', style: TextStyle(color: Colors.black54)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: online ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: online ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                  ),
                  child: Text(online ? 'Online' : 'Offline', style: TextStyle(fontSize: 12, color: online ? const Color(0xFF065F46) : const Color(0xFF92400E), fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Usage summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Model usage', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _kv('Calls', usage.calls.toString()),
              _kv('Input tokens', usage.inputTokens.toString()),
              _kv('Output tokens', usage.outputTokens.toString()),
              if (usage.cachedTokens > 0) _kv('Cached tokens', usage.cachedTokens.toString()),
              const Divider(height: 18),
              _kv('Total tokens', usage.totalTokens.toString()),
              _kv('Estimated cost', usage.costUsd == 0 ? '\$0.00 (pricing not set)' : '\$${usage.costUsd.toStringAsFixed(4)}'),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => ref.read(usageProvider.notifier).reset(),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Reset counters'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                  ),
                ],
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // Help
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: const Text(
              'Tip: Set your model pricing in usage_provider.dart (priceInPer1k / priceOutPer1k) to see cost estimates.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(color: Colors.black87))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}