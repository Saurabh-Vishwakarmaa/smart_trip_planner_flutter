import 'package:flutter/material.dart';


class ProfileScreen extends StatelessWidget {
  final String name;
  final String email;
  final VoidCallback? onBack;
  final VoidCallback? onLogout;

  const ProfileScreen({
    super.key,
    required this.name,
    required this.email,
    this.onBack,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF4F5F7),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Profile', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ValueListenableBuilder(
            valueListenable: usageStore,
            builder: (_, snap, __) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProfileCard(name: name, email: email),
                  const SizedBox(height: 16),
                  _TokenCard(
                    title: 'Request Tokens',
                    value: snap.prompt,
                    limit: snap.promptLimit,
                    progressColor: const Color(0xFF0E7A57),
                    barBg: const Color(0xFFE7F2EE),
                  ),
                  const SizedBox(height: 12),
                  _TokenCard(
                    title: 'Response Tokens',
                    value: snap.completion,
                    limit: snap.completionLimit,
                    progressColor: const Color(0xFFEB5757),
                    barBg: const Color(0xFFF9E7E7),
                  ),
                  const SizedBox(height: 12),
                  _CostCard(costUSD: snap.costUSD),
                  const Spacer(),
                  _LogoutButton(onLogout: onLogout),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String email;
  const _ProfileCard({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    final initials = name.isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      decoration: _cardDeco,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF0E7A57),
            child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(email, style: const TextStyle(color: Colors.black54)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _TokenCard extends StatelessWidget {
  final String title;
  final int value;
  final int limit;
  final Color progressColor;
  final Color barBg;

  const _TokenCard({
    required this.title,
    required this.value,
    required this.limit,
    required this.progressColor,
    required this.barBg,
  });

  @override
  Widget build(BuildContext context) {
    final pct = limit > 0 ? (value / limit).clamp(0, 1).toDouble() : 0.0;
    return Container(
      decoration: _cardDeco,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('$value/$limit', style: const TextStyle(color: Colors.black54)),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            color: progressColor,
            backgroundColor: barBg,
          ),
        ),
      ]),
    );
  }
}

class _CostCard extends StatelessWidget {
  final double costUSD;
  const _CostCard({required this.costUSD});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _cardDeco,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Expanded(child: Text('Total Cost', style: TextStyle(fontWeight: FontWeight.w600))),
          Text(
            '\$${costUSD.toStringAsFixed(2)} USD',
            style: const TextStyle(
              color: Color(0xFF22C55E),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback? onLogout;
  const _LogoutButton({this.onLogout});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onLogout,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFEB5757),
        side: const BorderSide(color: Color(0xFFEB5757)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      icon: const Icon(Icons.logout),
      label: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

final _cardDeco = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(16),
  boxShadow: const [
    BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 4)),
  ],
);


class UsageSnapshot {
  final int prompt;
  final int completion;
  final double costUSD;

  // limits for the progress right-hand "x/1000"
  final int promptLimit;
  final int completionLimit;

  const UsageSnapshot({
    required this.prompt,
    required this.completion,
    required this.costUSD,
    this.promptLimit = 1000,
    this.completionLimit = 1000,
  });

  double get promptProgress => promptLimit > 0 ? (prompt / promptLimit).clamp(0, 1).toDouble() : 0;
  double get completionProgress => completionLimit > 0 ? (completion / completionLimit).clamp(0, 1).toDouble() : 0;

  UsageSnapshot copyWith({
    int? prompt,
    int? completion,
    double? costUSD,
    int? promptLimit,
    int? completionLimit,
  }) => UsageSnapshot(
        prompt: prompt ?? this.prompt,
        completion: completion ?? this.completion,
        costUSD: costUSD ?? this.costUSD,
        promptLimit: promptLimit ?? this.promptLimit,
        completionLimit: completionLimit ?? this.completionLimit,
      );

  factory UsageSnapshot.fromTokens(Map<String, dynamic> j, {int promptLimit = 1000, int completionLimit = 1000}) {
    return UsageSnapshot(
      prompt: (j['prompt'] ?? j['input'] ?? 0) as int,
      completion: (j['completion'] ?? j['output'] ?? 0) as int,
      costUSD: (j['costUSD'] ?? j['cost'] ?? 0.0).toDouble(),
      promptLimit: promptLimit,
      completionLimit: completionLimit,
    );
  }
}

// Global notifier
final usageStore = ValueNotifier<UsageSnapshot>(const UsageSnapshot(prompt: 0, completion: 0, costUSD: 0.0));

// Call this when isolate returns tokens
void updateUsageFromTokens(Map<String, dynamic> tokens) {
  usageStore.value = UsageSnapshot.fromTokens(tokens);
}


