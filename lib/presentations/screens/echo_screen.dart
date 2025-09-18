import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'package:url_launcher/url_launcher.dart';
import 'package:smart_trip_planner_flutter/presentation/provider/agent_provider.dart';

class AgentScreen extends ConsumerStatefulWidget {
  const AgentScreen({super.key});
  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          state.isLoading
              ? 'Creating itinerary…'
              : state.hasValue && (state.value?.itinerary.isNotEmpty ?? false)
                  ? 'Itinerary Created 🏝️'
                  : "What's your vision?",
        ),
        leading: state.isLoading || state.hasError
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => ref.invalidate(agentStateProvider))
            : null,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: state.when(
            loading: () => _CreatingCard(),
            error: (e, _) => _ErrorCard(message: e.toString(), onBack: () => ref.invalidate(agentStateProvider)),
            data: (data) {
              if (data.itinerary.isEmpty) {
                return _PromptCard(
                  controller: _ctrl,
                  onCreate: () => ref.read(agentStateProvider.notifier).sendPrompt(_ctrl.text.trim()),
                );
              }
              return _ItineraryView(itinerary: data.itinerary, aux: data.aux);
            },
          ),
        ),
      ),
      bottomNavigationBar: state.hasValue && (state.value?.itinerary.isNotEmpty ?? false)
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showRefineSheet(context),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Follow up to refine'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () { /* TODO: save offline */ },
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('Save Offline'),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  void _showRefineSheet(BuildContext context) {
    final c = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: TextField(controller: c, decoration: const InputDecoration(hintText: 'Ask to adjust timings, add places…'))),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  ref.read(agentStateProvider.notifier).sendPrompt(c.text.trim(), prevJson: null);
                },
                child: const Text('Send'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.controller, required this.onCreate});
  final TextEditingController controller;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: '7 days in Bali next April, 3 people, mid-range budget, prefer peaceful less-crowded places.',
            filled: true,
            fillColor: const Color(0xFFF6FAF9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFBDE7D6))),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: onCreate,
            child: const Text('Create My Itinerary'),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Offline Saved Itineraries', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        // TODO: list saved itineraries
        _pill('Japan Trip, 20 days vacation…'),
        _pill('India Trip, 7 days work trip…'),
        _pill('Europe trip, Paris, Berlin, Dortmund…'),
      ],
    );
  }

  Widget _pill(String text) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE5E7EB))),
    child: Row(children: [const Icon(Icons.circle, size: 10, color: Color(0xFF34D399)), const SizedBox(width: 8), Expanded(child: Text(text))]),
  );
}

class _CreatingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5E7EB))),
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          SizedBox(height: 6),
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Curating a perfect plan for you…'),
        ]),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onBack});
  final String message;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Error', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700)),
        Padding(padding: const EdgeInsets.all(8), child: Text(message, textAlign: TextAlign.center)),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onBack, child: const Text('Back')),
      ]),
    );
  }
}

class _ItineraryView extends StatelessWidget {
  const _ItineraryView({required this.itinerary, required this.aux});
  final Map<String, dynamic> itinerary;
  final Map<String, dynamic> aux;

  @override
  Widget build(BuildContext context) {
    final title = itinerary['title']?.toString() ?? 'Trip';
    final start = itinerary['startDate']?.toString() ?? '';
    final end = itinerary['endDate']?.toString() ?? '';
    final days = (itinerary['days'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('$title', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('$start → $end', style: const TextStyle(color: Colors.black87)),
        const SizedBox(height: 12),
        for (int i = 0; i < days.length; i++) _DayCard(index: i, day: days[i], aux: aux),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.index, required this.day, required this.aux});
  final int index;
  final Map<String, dynamic> day;
  final Map<String, dynamic> aux;

  String _slot(String hhmm) {
    final hh = int.tryParse(hhmm.split(':').first) ?? 9;
    if (hh < 12) return 'Morning';
    if (hh < 17) return 'Afternoon';
    return 'Evening';
  }
  // String _fmt(String hhmm) {
  //   final parts = hhmm.split(':');
  //   if (parts.length < 2) return hhmm;
  //   final h = int.tryParse(parts[0]) ?? 9;
  //   final m = int.tryParse(parts[1]) ?? 0;
  //   final dt = DateTime(0, 1, 1, h, m);
  //   return DateTime(h)
  // }

  @override
  Widget build(BuildContext context) {
    final date = day['date']?.toString() ?? '';
    final summary = day['summary']?.toString() ?? '';
    final items = (day['items'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE5E7EB))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF10B981))),
              child: Text('Day ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF065F46))),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('$date — $summary', style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 8),
          for (int j = 0; j < items.length; j++) _Bullet(item: items[j], aux: Map<String, dynamic>.from(aux['$index:$j'] as Map? ?? {}), slotOf: _slot, ),
          const SizedBox(height: 6),
          _RouteCta(items: items, aux: aux, dayIndex: index),
        ]),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.item, required this.aux, required this.slotOf});
  final Map<String, dynamic> item;
  final Map<String, dynamic> aux;
  final String Function(String) slotOf;


  @override
  Widget build(BuildContext context) {
    final time = item['time']?.toString() ?? '';
    final activity = item['activity']?.toString() ?? '';
    final location = item['location']?.toString() ?? '';
    final slot = time.isNotEmpty ? '${slotOf(time)}: ' : '';
    final rating = aux['rating'] is num ? (aux['rating'] as num).toStringAsFixed(1) : null;
    final userRatings = aux['userRatings']?.toString();
    final snippet = aux['snippet']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('• '),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$slot$activity • ${time}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (location.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(location, style: const TextStyle(fontSize: 12))),
            if (rating != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text('Rating: $rating (${userRatings ?? "-"})', style: const TextStyle(fontSize: 12, color: Colors.black54))),
            if ((aux['distance']?.toString().isNotEmpty ?? false) || (aux['duration']?.toString().isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  [aux['distance']?.toString(), aux['duration']?.toString()].where((e) => (e ?? '').toString().isNotEmpty).join(' • '),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            if (snippet != null && snippet.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(snippet, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54))),
            if ((aux['mapLink']?.toString().isNotEmpty ?? false))
              TextButton.icon(
                onPressed: () async {
                  final url = Uri.parse(aux['mapLink'] as String);
                  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                    await launchUrl(url, mode: LaunchMode.platformDefault);
                  }
                },
                icon: const Icon(Icons.map, size: 16),
                label: const Text('Open in maps'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _RouteCta extends StatelessWidget {
  const _RouteCta({required this.items, required this.aux, required this.dayIndex});
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> aux;
  final int dayIndex;

  @override
  Widget build(BuildContext context) {
    // pick first travel-like item that has duration/distance
    for (int i = 0; i < items.length; i++) {
      final a = Map<String, dynamic>.from(aux['$dayIndex:$i'] as Map? ?? {});
      if ((a['duration'] != null || a['distance'] != null) && (a['mapLink']?.toString().isNotEmpty ?? false)) {
        final routeLine = [
          if (a['distance'] != null) a['distance'].toString(),
          if (a['duration'] != null) a['duration'].toString()
        ].where((e) => e.isNotEmpty).join(' | ');
        return Container(
          decoration: BoxDecoration(color: const Color(0xFFF6F8FB), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black12)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            const Icon(Icons.place, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                InkWell(
                  onTap: () async {
                    final url = Uri.parse(a['mapLink'] as String);
                    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                      await launchUrl(url, mode: LaunchMode.platformDefault);
                    }
                  },
                  child: Row(mainAxisSize: MainAxisSize.min, children: const [
                    Text('Open in maps', style: TextStyle(color: Colors.blue)),
                    SizedBox(width: 4),
                    Icon(Icons.open_in_new, color: Colors.blue, size: 16),
                  ]),
                ),
                if (routeLine.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(routeLine, style: const TextStyle(fontSize: 12, color: Colors.black54))),
              ]),
            ),
          ]),
        );
      }
    }
    return const SizedBox.shrink();
  }
}
