import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_trip_planner_flutter/data/services/speechservice.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:smart_trip_planner_flutter/data/local/local_store.dart';
import 'package:smart_trip_planner_flutter/presentation/provider/connectivity_provider.dart';
import 'package:smart_trip_planner_flutter/presentation/provider/agent_provider.dart';
import 'package:smart_trip_planner_flutter/presentations/screens/profile_screen.dart'; 



class AgentScreen extends ConsumerStatefulWidget {
  const AgentScreen({super.key});
  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
  final _ctrl = TextEditingController();
  String? _lastPrompt;
  late final SpeechService speech;
  

  @override
  void initState() {
    super.initState();
    speech = SpeechService()..init();
  }

  @override
  void dispose() {
    speech.stop();
    _ctrl.dispose();
    super.dispose();
  }

  // Mic handler that uses the SAME instance
  void _onMicPressed() async {
    await speech.toggle(
      currentText: _ctrl.text,
      onText: (text, isFinal) {
        _ctrl.text = text;
        _ctrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _ctrl.text.length),
        );
        if (isFinal) speech.stop();
        setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentStateProvider);
    final hasItinerary = state.hasValue && (state.value?.itinerary.isNotEmpty ?? false);
    final isError = state.hasError;
    final isOnline = ref.watch(onlineProvider);
    final readOnly = ref.watch(agentReadOnlyProvider);
    final savedTrips = ref.watch(savedTripsProvider).maybeWhen(
      data: (list) => list,
      orElse: () => const <SavedTrip>[],
    );
    

    return Scaffold(
      appBar: AppBar(
        title: Text(
          state.isLoading
              ? 'Creating Itinerary…'
              : hasItinerary || isError
                  ? (_lastPrompt == null || _lastPrompt!.isEmpty
                      ? 'Itinerary'
                      : (_lastPrompt!.length > 18 ? '${_lastPrompt!.substring(0, 18)}…' : _lastPrompt!))
                  : "",
        ),
        leading: (state.isLoading || hasItinerary || isError)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => ref.invalidate(agentStateProvider),
              )
            : null,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen(name: 'Shubham', email: 'shubham1752004',))),
              child: const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFF10B981),
                child: Text('S', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: state.when(
            loading: () => const _CreatingCard(),
            error: (e, _) => _ChatThread(
              userText: _lastPrompt ?? '',
              child: _AiErrorCard(
                message: isOnline
                    ? 'Oops! The LLM failed to generate answer. Please regenerate.'
                    : 'You are offline. Open a saved trip or reconnect.',
                onRegenerate: () {
                  if (!isOnline) return;
                  final prompt = _lastPrompt ?? _ctrl.text.trim();
                  if (prompt.isNotEmpty) {
                    ref.read(agentStateProvider.notifier).sendPrompt(prompt);
                  }
                },
              ),
            ),
            data: (data) {
              if (data.itinerary.isEmpty) {
                return _HomePrompt(
                  controller: _ctrl,
                  isOnline: isOnline,
                  savedTrips: savedTrips,
                  onOpenSaved: (t) => ref.read(agentStateProvider.notifier).loadFromLocal(t.json),
                  onCreatePressed: () {
                    final text = _ctrl.text.trim();
                    if (text.isEmpty) return;
                    if (!isOnline) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline. Open a saved trip or reconnect.')));
                      return;
                    }
                    setState(() => _lastPrompt = text);
                    ref.read(agentStateProvider.notifier).sendPrompt(text);
                  },
                  onMicPressed: _onMicPressed, // <-- pass mic callback here
                );
              }
              return _ChatThread(
                userText: _lastPrompt ?? '',
                child: _AiItineraryCard(
                  itinerary: data.itinerary,
                  aux: data.aux,
                  onCopy: () {
                    final j = const JsonEncoder.withIndent('  ').convert(data.itinerary);
                    Clipboard.setData(ClipboardData(text: j));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                  },
                  onSaveOffline: () async {
                    final it = data.itinerary;
                    final title = (it['title'] ?? 'Trip').toString();
                    final start = (it['startDate'] ?? '').toString();
                    final end = (it['endDate'] ?? '').toString();
                    await LocalStore.instance.saveItinerary(
                      title: title,
                      startDate: start,
                      endDate: end,
                      json: jsonEncode(it),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved offline')));
                      ref.invalidate(savedTripsProvider);
                    }
                  },
                  onRegenerate: () {
                    if (!isOnline) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline. Cannot regenerate.')));
                      return;
                    }
                    final prompt = _lastPrompt ?? _ctrl.text.trim();
                    if (prompt.isNotEmpty) {
                      ref.read(agentStateProvider.notifier).sendPrompt(prompt);
                    }
                  },
                ),
              );
            },
          ),
        ),
      ),
      // Bottom action bar like mock: Follow up to refine + mic + send
      bottomNavigationBar: (hasItinerary && isOnline && !readOnly)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                          label: const Text('Follow up to refine', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          onPressed: () => _showRefineSheet(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _circleAction(
                      context,
                      icon: Icons.mic_none,
                      onTap: () => _showRefineSheet(context),
                    ),
                    const SizedBox(width: 8),
                    _circleAction(
                      context,
                      icon: Icons.send_rounded,
                      onTap: () => _showRefineSheet(context),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _circleAction(BuildContext context, {required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white),
      ),
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
              Expanded(child: TextField(controller: c, decoration: const InputDecoration(hintText: 'Refine (e.g., dinner veg near Assi Ghat 7pm)'))),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                onPressed: () {
                  final text = c.text.trim();
                  if (text.isEmpty) return;
                  final current = ref.read(agentStateProvider).value?.itinerary;
                  setState(() => _lastPrompt = text);
                  Navigator.pop(context);
                  ref.read(agentStateProvider.notifier).sendPrompt(
                        text,
                        prevJson: current == null ? null : jsonEncode(current),
                      );
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

// Home screen
class _HomePrompt extends StatelessWidget {
  const _HomePrompt({
    required this.controller,
    required this.onCreatePressed,
    required this.isOnline,
    required this.savedTrips,
    required this.onOpenSaved,
    required this.onMicPressed, // <-- new param
  });
  final TextEditingController controller;
  final VoidCallback onCreatePressed;
  final bool isOnline;
  final List<SavedTrip> savedTrips;
  final void Function(SavedTrip trip) onOpenSaved;
  final VoidCallback onMicPressed; // <-- new field




  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(child: Text('Hey Shubham 👋', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF10B981)))),
            if (!isOnline)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFF59E0B))),
                child: const Text('Offline mode', style: TextStyle(fontSize: 12, color: Color(0xFF92400E), fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const Text("What’s your vision\nfor the trip?", textAlign: TextAlign.left, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: isOnline
                ? '7 days in Bali next April, 3 people, mid‑range budget, peaceful areas…'
                : 'You are offline. Open a saved trip below.',
            suffixIcon: IconButton(
              onPressed: isOnline ? onMicPressed : null, // <-- use callback
              icon: const Icon(Icons.mic_none),
              tooltip: 'Speak',
            ),
            filled: true,
            fillColor: const Color(0xFFF6FAF9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFBDE7D6)),
            ),
          ),
          readOnly: !isOnline,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: isOnline ? onCreatePressed : null,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
              ),
              child: Center(child: Text(isOnline ? 'Create My Itinerary' : 'Offline — open saved trip', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Offline Saved itineraries', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (savedTrips.isEmpty)
          const Text('No saved trips yet', style: TextStyle(color: Colors.black54))
        else
          for (int i = 0; i < savedTrips.length; i++)
            InkWell(
              onTap: () => onOpenSaved(savedTrips[i]),
              child: _pill('${savedTrips[i].title}, ${savedTrips[i].startDate} → ${savedTrips[i].endDate}', i),
            )
      ],
    );
  }

  Widget _pill(String text,int t) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE5E7EB))),
        child: Row(children: [const Icon(Icons.circle, size: 10, color: Color(0xFF34D399)), const SizedBox(width: 8), Expanded(child: Text(text)),GestureDetector(child: Icon(Icons.delete),onTap: () =>     savedTrips.removeAt(t),)]),
      );
}

class _CreatingCard extends StatelessWidget {
  const _CreatingCard();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        const Text('Creating Itinerary…', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Container(
          height: 240,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Color(0xFFE5E7EB))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Curating a perfect plan for you...'),
          ]),
        ),
      ],
    );
  }
}

// Chat thread shell: User bubble then AI card
class _ChatThread extends StatelessWidget {
  const _ChatThread({required this.userText, required this.child});
  final String userText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (userText.isNotEmpty) _UserBubble(text: userText),
        child,
      ],
    );
  }
}

// User card like mock (“You” bubble)
class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          CircleAvatar(radius: 10, backgroundColor: Color(0xFF10B981), child: Text('S', style: TextStyle(fontSize: 12, color: Colors.white))),
          SizedBox(width: 8),
          Text('You', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        Text(text),
        const SizedBox(height: 6),
        TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: text)), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy'), style: _linkStyle),
      ]),
    );
  }
}

// AI itinerary card like mock
class _AiItineraryCard extends StatelessWidget {
  const _AiItineraryCard({required this.itinerary, required this.aux, required this.onCopy, required this.onSaveOffline, required this.onRegenerate});
  final Map<String, dynamic> itinerary;
  final Map<String, dynamic> aux;
  final VoidCallback onCopy;
  final VoidCallback onSaveOffline;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          CircleAvatar(radius: 10, backgroundColor: Color(0xFFFFC107), child: Icon(Icons.chat_bubble, size: 12, color: Colors.black)),
          SizedBox(width: 8),
          Text('Itinera AI', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        _ItineraryView(itinerary: itinerary, aux: aux),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          TextButton.icon(onPressed: () async => onCopy(), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy'), style: _linkStyle),
          TextButton.icon(onPressed: () async => onSaveOffline(), icon: const Icon(Icons.bookmark_add_outlined, size: 16), label: const Text('Save Offline'), style: _linkStyle),
          TextButton.icon(onPressed: () async => onRegenerate(), icon: const Icon(Icons.refresh, size: 16), label: const Text('Regenerate'), style: _linkStyle),
        ]),
      ]),
    );
  }
}

// AI error card like your image
class _AiErrorCard extends StatelessWidget {
  const _AiErrorCard({required this.message, required this.onRegenerate});
  final String message;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          CircleAvatar(radius: 10, backgroundColor: Color(0xFFFFC107), child: Icon(Icons.chat_bubble, size: 12, color: Colors.black)),
          SizedBox(width: 8),
          Text('Itinera AI', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        Row(children: const [
          Icon(Icons.error_outline, color: Color(0xFFEF4444)),
          SizedBox(width: 6),
          Expanded(child: Text('Oops! The LLM failed to generate answer. Please regenerate.', style: TextStyle(color: Color(0xFFEF4444)))),
        ]),
        const SizedBox(height: 8),
        TextButton.icon(onPressed: onRegenerate, icon: const Icon(Icons.refresh, size: 16), label: const Text('Regenerate'), style: _linkStyle),
      ]),
    );
  }
}

final ButtonStyle _linkStyle = TextButton.styleFrom(
  padding: EdgeInsets.zero,
  minimumSize: const Size(0, 0),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

// ---- Existing itinerary rendering below (kept, styled to match) ----

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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

  String _fmt(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return hhmm;
    int h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final ampm = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    if (h == 0) h = 12;
    final mm = m.toString().padLeft(2, '0');
    return '$h:$mm $ampm';
  }

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
          for (int j = 0; j < items.length; j++)
            _Bullet(
              item: items[j],
              aux: Map<String, dynamic>.from(aux['$index:$j'] as Map? ?? {}),
              slotOf: _slot,
              fmt: _fmt,
            ),
        ]),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.item, required this.aux, required this.slotOf, required this.fmt});
  final Map<String, dynamic> item;
  final Map<String, dynamic> aux;
  final String Function(String) slotOf;
  final String Function(String) fmt;

  bool _isGenericLabel(String s) {
    final l = s.toLowerCase();
    return l.contains('best restaurant') ||
        l.contains('best restaurants') ||
        l.contains('restaurants near') ||
        l.contains('restaurant near') ||
        l.contains('hotel near') ||
        l.contains('hotels near') ||
        l.contains('nearby') ||
        l.contains('around');
  }

  String? _mapLinkOf(Map<String, dynamic> geo) {
    final link = geo['mapLink']?.toString();
    if (link != null && link.isNotEmpty) return link;
    final lat = (geo['lat'] as num?)?.toDouble();
    final lon = (geo['lon'] as num?)?.toDouble();
    if (lat != null && lon != null) {
      return 'https://www.google.com/maps/search/?api=1&query=$lat,$lon';
    }
    return null;
  }

  Map<String, dynamic> _geo() {
    if (aux.isNotEmpty) return aux;
    final g = item['geo'];
    if (g is Map) return Map<String, dynamic>.from(g);
    return const {};
  }

  Widget _chip(IconData icon, String text, {Color color = const Color(0xFF111827)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.only(right: 6, top: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final time = item['time']?.toString() ?? '';
    final activity = item['activity']?.toString() ?? '';
    final rawLocation = item['location']?.toString() ?? '';
    final slot = time.isNotEmpty ? '${slotOf(time)}: ' : '';

    final geo = _geo();
    final ratingNum = (geo['rating'] as num?);
    final rating = ratingNum != null ? ratingNum.toStringAsFixed(1) : null;
    final userRatings = geo['userRatings']?.toString();
    final price = (geo['price']?.toString().isNotEmpty ?? false)
        ? geo['price'].toString()
        : (() {
            final lvl = (geo['priceLevel'] as num?)?.toInt();
            if (lvl == null) return null;
            return List.filled(lvl + 1, r'$').join();
          })();

    String displayLocation = rawLocation;
    final address = geo['address']?.toString();
    if (displayLocation.isEmpty || _isGenericLabel(displayLocation)) {
      if ((geo['name']?.toString().isNotEmpty ?? false)) {
        displayLocation = geo['name'].toString();
      } else if ((address?.isNotEmpty ?? false)) {
        displayLocation = address!;
      }
    }

    final mapLink = _mapLinkOf(geo);
    final distanceText = aux['distanceText']?.toString();
    final durationText = aux['durationText']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('• '),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$slot$activity • ${time.isNotEmpty ? fmt(time) : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (displayLocation.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: InkWell(
                  onTap: (mapLink != null)
                      ? () async {
                          final url = Uri.parse(mapLink);
                          if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                            await launchUrl(url, mode: LaunchMode.platformDefault);
                          }
                        }
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.place_outlined, size: 16, color: Color(0xFF2563EB)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          displayLocation,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF2563EB), fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (mapLink != null) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.open_in_new, size: 14, color: Color(0xFF2563EB)),
                      ]
                    ],
                  ),
                ),
              ),
            if ((address?.isNotEmpty ?? false) && address != displayLocation)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(address!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ),
            Wrap(children: [
              if (rating != null) _chip(Icons.star_rounded, '$rating${userRatings != null ? ' ($userRatings)' : ''}', color: const Color(0xFFF59E0B)),
              if (price != null && price.isNotEmpty) _chip(Icons.payments_outlined, price),
            ]),
            if (mapLink != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(
                    onTap: () async {
                      final url = Uri.parse(mapLink);
                      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                        await launchUrl(url, mode: LaunchMode.platformDefault);
                      }
                    },
                    child: Row(mainAxisSize: MainAxisSize.min, children: const [
                      Icon(Icons.push_pin_rounded, size: 16, color: Color(0xFFEF4444)),
                      SizedBox(width: 6),
                      Text('Open in maps', style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w700)),
                      SizedBox(width: 4),
                      Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF2563EB)),
                    ]),
                  ),
                  if (distanceText != null || durationText != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${distanceText ?? ''}${(distanceText != null && durationText != null) ? ' | ' : ''}${durationText ?? ''}',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ],
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
