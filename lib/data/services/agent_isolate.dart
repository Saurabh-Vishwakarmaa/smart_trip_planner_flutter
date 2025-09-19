// lib/data/services/agent_isolate.dart
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:smart_trip_planner_flutter/constants.dart';

// In-memory caches to minimize API hits
final _geocodeCache = <String, Map<String, double>?>{};
final _poiCache = <String, Map<String, dynamic>?>{};

// Budget classifier
enum _Budget { low, mid, high }

_Budget _inferBudget(String text) {
  final t = text.toLowerCase();
  if (RegExp(r'\b(low|budget|cheap|economy|student)\b').hasMatch(t)) return _Budget.low;
  if (RegExp(r'\b(luxury|5-?star|upscale|premium|expensive)\b').hasMatch(t)) return _Budget.high;
  return _Budget.mid;
}

double _scorePlace(Map<String, dynamic> r, _Budget b) {
  final rating = (r['rating'] as num?)?.toDouble() ?? 0;
  final count = (r['user_ratings_total'] as num?)?.toDouble() ?? 0;
  final price = (r['price_level'] as num?)?.toDouble() ?? 2; // 0..4
  final wp = switch (b) { _Budget.low => 0.9, _Budget.mid => 0.3, _Budget.high => -0.2 };
  return (rating * 2.0) + (count > 0 ? (math.log(1 + count) * 0.7) : 0) - (wp * price);
}

String _priceSymbol(int? level) {
  if (level == null) return '';
  return List.filled(level + 1, r'$').join();
}

// Optional: disable Wikipedia to reduce calls
const bool kEnableWikiSnippet = false;

void agentWorker(SendPort sendPort) async {
  final port = ReceivePort();
  sendPort.send(port.sendPort);

  await for (final msg in port) {
    late final SendPort reply;
    try {
      if (msg is! List || msg.isEmpty) throw ArgumentError('Invalid message to agent');
      final String prompt = msg[0] as String;
      final String? prevJson = msg.length >= 3 ? msg[1] as String? : null;
      final String? chatHistoryJson = msg.length >= 4 ? msg[2] as String? : null;
      reply = msg.last as SendPort;

      final geminiKey = Secrets.api_key;
      if (geminiKey.isEmpty) {
        reply.send({"type": "error", "ok": false, "data": "Missing GEMINI_API_KEY"});
        continue;
      }

      final model = GenerativeModel(
        model: 'gemini-1.5-flash-latest',
        apiKey: geminiKey,
        generationConfig: GenerationConfig(responseMimeType: 'application/json'),
      );
      final instruction = _promptInstruction(prompt, prevJson, chatHistoryJson);
      final resp = await model.generateContent([Content.text(instruction)]);
      final raw = (resp.text ?? '').trim();
      if (raw.isEmpty) {
        reply.send({"type": "error", "ok": false, "data": "Empty model response"});
        continue;
      }
      var skeleton = _safeDecodeMap(raw);
      if (skeleton.isEmpty) {
        reply.send({"type": "error", "ok": false, "data": "Invalid JSON from model"});
        continue;
      }

      skeleton = _ensureContinuousDays(skeleton);

      final destName = (skeleton['destination']?.toString() ?? '').trim();
      if (destName.isEmpty) {
        reply.send({"type": "error", "ok": false, "data": "destination missing"});
        continue;
      }
      final destCenter = await _geocodeOSM(destName);
      if (destCenter == null) {
        reply.send({"type": "error", "ok": false, "data": "Could not resolve destination: $destName"});
        continue;
      }

      final placesKey = Secrets.places_api_key;
      final enrichment = await _enrichSkeleton(
        skeleton,
        destCenter: destCenter,
        radiusMeters: 25000,
        placesKey: placesKey.isNotEmpty ? placesKey : null,
        onDelta: (partial, aux) {
          // Stream incremental results
          try {
            reply.send({"type": "delta", "ok": true, "data": partial, "aux": aux});
          } catch (_) {}
        },
        budget: _inferBudget('$prompt ${skeleton['title'] ?? ''}'),
      );

      final err = _validateSpecA(enrichment.itinerary);
      if (err != null) {
        reply.send({"type": "error", "ok": false, "data": "Schema error: $err"});
        continue;
      }

      reply.send({
        "type": "done",
        "ok": true,
        "data": enrichment.itinerary,
        "aux": enrichment.aux,
        "tokens": {
          "prompt": resp.usageMetadata?.promptTokenCount ?? 0,
          "completion": resp.usageMetadata?.candidatesTokenCount ?? 0,
          "total": resp.usageMetadata?.totalTokenCount ?? 0,
          "cost": 0
        }
      });
    } catch (e) {
      try { reply.send({"type": "error", "ok": false, "data": e.toString()}); } catch (_) {}
    }
  }
}

// Generic time nudges: none hard-coded; rely on LLM for locality schedules
final _timeRules = <_TimeRule>[]; // previously had Varanasi-specific rules

class _TimeRule {
  final bool Function(String destination, String text) where;
  final List<String> prefer;
  const _TimeRule({required this.where, required this.prefer});
}

bool _containsAny(String s, List<String> kws) {
  final t = s.toLowerCase();
  return kws.any((k) => t.contains(k.toLowerCase()));
}

void _nudgeTimesForKnownActivities(String destination, List<Map<String, dynamic>> items) {
  for (final it in items) {
    final label = [
      it['activity']?.toString() ?? '',
      it['place']?.toString() ?? '',
      it['search']?.toString() ?? '',
      it['location']?.toString() ?? '',
    ].where((e) => e.isNotEmpty).join(' ');
    for (final r in _timeRules) {
      if (r.where(destination, label)) {
        // If time not set or not in a sane window for this activity, set preferred
        final old = it['time']?.toString() ?? '';
        if (old.isEmpty || !_timeLooksSaneFor(r.prefer, old)) {
          it['time'] = r.prefer.first;
        }
        break;
      }
    }
  }
}

bool _timeLooksSaneFor(List<String> prefer, String current) {
  int hour(String t) => int.tryParse(t.split(':').first) ?? -1;
  final h = hour(current);
  if (h < 0) return false;
  // If any preferred hour window matches roughly, accept
  for (final p in prefer) {
    final hp = hour(p);
    if ((h - hp).abs() <= 1) return true;
  }
  return false;
}

String _lodgingSearchHint(String destination, _Budget budget) {
  // Generic hint; no city-specific places
  final low = budget == _Budget.low;
  final prefix = low ? 'affordable budget hotels and guest houses' : 'best hotels';
  return '$prefix near city center or major attractions in $destination';
}

// >>> UPDATED: prompt — remove city-specific examples; keep rules generic
String _promptInstruction(String prompt, String? prevJson, String? chatHistoryJson) {
  final base = '''
You are a professional travel planner. Return ONLY JSON (no markdown) that follows Spec A:

{
  "destination": "City, Country",
  "title": "string",
  "startDate": "YYYY-MM-DD",
  "endDate": "YYYY-MM-DD",
  "days": [
    {
      "date": "YYYY-MM-DD",
      "summary": "string",
      "items": [
        { "time": "HH:mm", "activity": "string", "place": "Named attraction/POI" },
        { "time": "HH:mm", "activity": "Lunch", "search": "best restaurants near <area>" }
      ]
    }
  ]
}

Rules:
- Use specific, known place names (avoid generic "hotel near ...").
- Day 1 MUST start with Arrival in <destination> and an Accommodation/Check-in item.
- last day of the trip should have the departure at the end after whole schedule or suitable.
- times should be in sync one after another (e.g., 7 then 8 then 9 flow should be like this not random)
- Times must be realistic and respect local schedules (e.g., sunrise activities near dawn; evening ceremonies around sunset; popular sites during opening hours).
- 3–5 items/day with morning/lunch/afternoon/evening cadence.
- DO NOT include route/travel items.
''';

  final refine = prevJson == null
      ? '''
Task: Create an itinerary skeleton for: "$prompt".
- Ensure Day 1 includes Arrival + Accommodation.
- Use realistic times for activities as per local norms.
'''
      : '''
Task: Refine the existing itinerary in-place using: "$prompt".
- Keep destination, dates, and day count unless explicitly requested to change.
- Only adjust items relevant to the user request; preserve unrelated ones.
- If replacing a generic meal or hotel, keep the same time slot but update to a specific named place (with "place") and ensure it's realistic for that time.
- Return the FULL updated JSON per Spec A.
''';

  return '''
$base
$refine

Previous itinerary JSON: ${prevJson ?? "null"}
Chat history: ${chatHistoryJson ?? "null"}
''';
}

// Spec A validator: location must be human-readable
String? _validateSpecA(Map<String, dynamic> j) {
  if (j['title'] is! String) return 'title missing';
  if (j['startDate'] is! String) return 'startDate missing';
  if (j['endDate'] is! String) return 'endDate missing';
  if (j['days'] is! List) return 'days must be list';
  for (final d in (j['days'] as List)) {
    final md = Map<String, dynamic>.from(d as Map);
    if (md['date'] is! String) return 'day.date missing';
    if (md['summary'] is! String) return 'day.summary missing';
    if (md['items'] is! List) return 'day.items must be list';
    for (final it in (md['items'] as List)) {
      final mi = Map<String, dynamic>.from(it as Map);
      if (mi['time'] is! String) return 'item.time missing';
      if (mi['activity'] is! String) return 'item.activity missing';
      if (mi['location'] is! String) return 'item.location missing';
    }
  }
  return null;
}

Map<String, dynamic> _safeDecodeMap(String raw) {
  try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
  final m = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
  if (m != null) { try { return jsonDecode(m.group(0)!) as Map<String, dynamic>; } catch (_) {} }
  return <String, dynamic>{};
}

// Ensure continuous dates
Map<String, dynamic> _ensureContinuousDays(Map<String, dynamic> skel) {
  DateTime? start, end;
  try { start = DateTime.parse('${skel['startDate']}'); end = DateTime.parse('${skel['endDate']}'); } catch (_) {}
  if (start == null || end == null || end.isBefore(start)) return skel;

  final target = <String>[];
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    target.add(d.toIso8601String().substring(0, 10));
  }

  final byDate = <String, Map<String, dynamic>>{};
  for (final e in (skel['days'] as List? ?? const [])) {
    final m = Map<String, dynamic>.from(e as Map);
    final date = '${m['date']}';
    byDate[date] = m;
  }

  final outDays = <Map<String, dynamic>>[];
  for (final date in target) {
    outDays.add(byDate[date] ?? {
      'date': date,
      'summary': 'Explore highlights',
      'items': [
        {'time': '09:00', 'activity': 'Morning exploration', 'place': 'Old town'},
        {'time': '13:00', 'activity': 'Lunch', 'search': 'best restaurants near city center'},
        {'time': '18:30', 'activity': 'Evening stroll', 'place': 'City center'},
      ],
    });
  }

  return {
    'destination': '${skel['destination'] ?? ''}',
    'title': '${skel['title'] ?? 'Trip'}',
    'startDate': target.first,
    'endDate': target.last,
    'days': outDays,
  };
}

/* ----------------------------- Enrichment core ---------------------------- */

class _Enrichment {
  _Enrichment(this.itinerary, this.aux);
  final Map<String, dynamic> itinerary; // Spec A
  final Map<String, dynamic> aux;       // keyed "d:i" -> {lat,lon,mapLink,address,rating,userRatings,dist,duration,snippet}
}

Future<_Enrichment> _enrichSkeleton(
  Map<String, dynamic> skel, {
  required Map<String, double> destCenter,
  required int radiusMeters,
  String? placesKey,
  void Function(Map<String, dynamic> partialItinerary, Map<String, dynamic> partialAux)? onDelta,
  _Budget budget = _Budget.mid,
}) async {
  final destination = (skel['destination']?.toString() ?? '').trim();
  final title = skel['title']?.toString() ?? (destination.isNotEmpty ? '$destination Trip' : 'Trip');
  final startDate = skel['startDate']?.toString() ?? '';
  final endDate = skel['endDate']?.toString() ?? '';
  final days = (skel['days'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  final outDays = <Map<String, dynamic>>[];
  final aux = <String, dynamic>{};

  for (int dIdx = 0; dIdx < days.length; dIdx++) {
    final d = days[dIdx];
    final date = '${d['date'] ?? ''}';
    final summary = '${d['summary'] ?? ''}';
    var items = (d['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    if (dIdx == 0) {
      _ensureArrivalAndStayOnDay0(destination, budget, items);
    }
    _nudgeTimesForKnownActivities(destination, items);

    final futures = <Future<void>>[];
    final resolved = List<Map<String, dynamic>>.filled(items.length, {});
    final meta = List<Map<String, dynamic>>.filled(items.length, {});

    for (int iIdx = 0; iIdx < items.length; iIdx++) {
      final it = items[iIdx];
      futures.add(() async {
        final time = '${it['time'] ?? ''}';
        final activity = '${it['activity'] ?? ''}';
        final route = it['route'] is Map ? Map<String, dynamic>.from(it['route'] as Map) : null;
        final placeRaw0 = (it['place']?.toString().trim().isNotEmpty ?? false) ? it['place']?.toString() : (route?['to']?.toString());
        final searchRaw0 = it['search']?.toString();

        final actL = activity.toLowerCase();
        final isMeal = actL.contains('lunch') || actL.contains('dinner') || actL.contains('breakfast') || (searchRaw0?.toLowerCase().contains('restaurant') ?? false);
        final isLodging = actL.contains('hotel') || actL.contains('check-in') || actL.contains('check in') || actL.contains('resort') || actL.contains('accommodation') ||
            (placeRaw0?.toLowerCase().contains('hotel') ?? false) || (searchRaw0?.toLowerCase().contains('hotel') ?? false) || (placeRaw0?.toLowerCase().contains('resort') ?? false);

        // Nearby anchor for meals
        Map<String, double> centerForSearch = destCenter;
        String? nearHint;
        if (isMeal) {
          final anchor = await _anchorForMealItem(index: iIdx, rawItems: items, destCenter: destCenter, radius: radiusMeters, placesKey: placesKey);
          if (anchor != null) centerForSearch = anchor;
          final prev = iIdx > 0 ? items[iIdx - 1] : null;
          nearHint = (prev?['place'] ?? prev?['location'])?.toString();
        }

        // Budget-biased search text
        String? searchRaw = (budget == _Budget.low && searchRaw0 != null && searchRaw0.trim().isNotEmpty)
            ? '${searchRaw0.trim()} cheap affordable budget'
            : searchRaw0?.trim();

        // Strengthen weak queries with city/country/type context
        if (searchRaw != null && searchRaw.isNotEmpty) {
          searchRaw = _strengthenQuery(searchRaw, destination, isRestaurant: isMeal, isLodging: isLodging, nearHint: nearHint);
        }

        // For short "place" names, also strengthen to avoid wrong city matches
        String? placeRaw = placeRaw0;
        String? strengthenedPlaceForSearch;
        if (placeRaw != null && _isSingleWeakTerm(placeRaw)) {
          strengthenedPlaceForSearch = _strengthenQuery(placeRaw, destination, isRestaurant: isMeal, isLodging: isLodging, nearHint: nearHint);
        }

        Map<String, dynamic>? poi;

        Future<Map<String, dynamic>?> _retryIfFar(Map<String, dynamic>? candidate, Future<Map<String, dynamic>?> Function() secondTry) async {
          if (candidate == null) return await secondTry();
          if (_tooFarFrom(destCenter, candidate)) {
            final retry = await secondTry();
            if (retry != null && !_tooFarFrom(destCenter, retry)) return retry;
            // keep closer of the two if retry also far
            if (retry != null) {
              final oldD = _haversine(destCenter['lat']!, destCenter['lon']!, (candidate['lat'] as num).toDouble(), (candidate['lon'] as num).toDouble());
              final newD = _haversine(destCenter['lat']!, destCenter['lon']!, (retry['lat'] as num).toDouble(), (retry['lon'] as num).toDouble());
              return newD < oldD ? retry : candidate;
            }
          }
          return candidate;
        }

        if (placeRaw != null && placeRaw.trim().isNotEmpty) {
          // First attempt: exact place; if too weak, use the strengthened variant
          poi = isLodging
              ? await _findLodging(placeRaw, centerForSearch, 2500, placesKey: placesKey, budget: budget)
              : await _findPlacePrecise(placeRaw, centerForSearch, radiusMeters, placesKey: placesKey);

          if (poi == null && strengthenedPlaceForSearch != null) {
            poi = isLodging
                ? await _findLodging(strengthenedPlaceForSearch, centerForSearch, 3000, placesKey: placesKey, budget: budget)
                : await _findPlacePrecise(strengthenedPlaceForSearch, centerForSearch, math.max(radiusMeters, 2500), placesKey: placesKey);
          }

          // Retry with context if far
          poi = await _retryIfFar(poi, () async {
            final q = strengthenedPlaceForSearch ?? _strengthenQuery(placeRaw!, destination, isRestaurant: isMeal, isLodging: isLodging, nearHint: nearHint);
            return isLodging
                ? await _findLodging(q, destCenter, 4000, placesKey: placesKey, budget: budget) ??
                    await _findNamedPOI(q, destCenter, math.max(radiusMeters, 3000))
                : await _findPlacePrecise(q, destCenter, math.max(radiusMeters, 3000), placesKey: placesKey) ??
                    await _findNamedPOI(q, destCenter, math.max(radiusMeters, 3000));
          });

          // OSM fallback
          poi ??= await _findNamedPOI(placeRaw, centerForSearch, radiusMeters);
        } else if (searchRaw != null && searchRaw.trim().isNotEmpty) {
          poi = isMeal
              ? await _findRestaurant(searchRaw, centerForSearch, 1800, placesKey: placesKey, budget: budget)
              : (isLodging
                  ? await _findLodging(searchRaw, centerForSearch, 2500, placesKey: placesKey, budget: budget)
                  : await _findPlacePrecise(searchRaw, centerForSearch, radiusMeters, placesKey: placesKey));

          // Retry with destination-bias if far
          poi = await _retryIfFar(poi, () async {
            final q2 = _strengthenQuery(searchRaw!, destination, isRestaurant: isMeal, isLodging: isLodging, nearHint: nearHint);
            return isMeal
                ? await _findRestaurant(q2, destCenter, 3000, placesKey: placesKey, budget: budget) ??
                    await _findNamedPOI(q2, destCenter, math.max(radiusMeters, 2500))
                : (isLodging
                    ? await _findLodging(q2, destCenter, 3500, placesKey: placesKey, budget: budget) ??
                        await _findNamedPOI(q2, destCenter, math.max(radiusMeters, 2500))
                    : await _findPlacePrecise(q2, destCenter, math.max(radiusMeters, 2500), placesKey: placesKey) ??
                        await _findNamedPOI(q2, destCenter, math.max(radiusMeters, 2500)));
          });

          poi ??= await _findNamedPOI(searchRaw, centerForSearch, radiusMeters);
        }

        final locationName = poi?['name']?.toString() ??
            placeRaw?.toString() ??
            searchRaw?.toString() ??
            (activity.isNotEmpty ? activity : 'Place');

        final m = <String, dynamic>{};
        if (poi != null) {
          if (poi['name'] != null) m['name'] = poi['name'];
          m['lat'] = poi['lat'];
          m['lon'] = poi['lon'];
          m['address'] = poi['address'] ?? locationName;
          m['mapLink'] = poi['mapLink'] ?? _mapsSearchLink(poi['lat'] as double, poi['lon'] as double);
          if (poi['rating'] != null) m['rating'] = poi['rating'];
          if (poi['userRatings'] != null) m['userRatings'] = poi['userRatings'];
          if (poi['priceLevel'] != null) {
            m['priceLevel'] = poi['priceLevel'];
            m['price'] = _priceSymbol((poi['priceLevel'] as num?)?.toInt());
          }
          if (kEnableWikiSnippet) {
            m['snippet'] = await _wikiSnippet(locationName, poi['lat'] as double, poi['lon'] as double);
          }
        }

        resolved[iIdx] = {'time': time, 'activity': activity, 'location': locationName, 'geo': m};
        meta[iIdx] = m;
      }());
    }

    await Future.wait(futures);

    final orderedIndex = _orderByProximity(resolved, meta);
    final orderedItems = <Map<String, dynamic>>[];
    for (int k = 0; k < orderedIndex.length; k++) {
      final idx = orderedIndex[k];
      orderedItems.add(resolved[idx]);
      if (k > 0) {
        final prevIdx = orderedIndex[k - 1];
        final aLat = (meta[prevIdx]['lat'] as num?)?.toDouble();
        final aLon = (meta[prevIdx]['lon'] as num?)?.toDouble();
        final bLat = (meta[idx]['lat'] as num?)?.toDouble();
        final bLon = (meta[idx]['lon'] as num?)?.toDouble();
        if (aLat != null && aLon != null && bLat != null && bLon != null) {
          final dir = await _osrmRoute(aLat, aLon, bLat, bLon);
          if (dir.isNotEmpty) {
            meta[idx]['distanceText'] = dir['distanceText'];
            meta[idx]['durationText'] = dir['durationText'];
          }
        }
      }
      aux['$dIdx:$idx'] = meta[idx];
    }

    outDays.add({'date': date, 'summary': summary, 'items': orderedItems});

    if (onDelta != null) {
      onDelta(
        {'title': title, 'startDate': startDate, 'endDate': endDate, 'days': List<Map<String, dynamic>>.from(outDays)},
        Map<String, dynamic>.from(aux),
      );
    }
  }

  return _Enrichment({'title': title, 'startDate': startDate, 'endDate': endDate, 'days': outDays}, aux);
}

/* --------------------------- Ordering + utilities -------------------------- */

List<int> _orderByProximity(List<Map<String, dynamic>> items, List<Map<String, dynamic>> meta) {
  // Group by time slot: morning (<12), afternoon (12..16), evening (>=17)
  int slotOf(String time) {
    final hh = int.tryParse(time.split(':').first) ?? 9;
    if (hh < 12) return 0; // morning
    if (hh < 17) return 1; // afternoon
    return 2; // evening
  }
  final groups = <int, List<int>>{0: [], 1: [], 2: []};
  for (var i = 0; i < items.length; i++) {
    groups[slotOf('${items[i]['time'] ?? '09:00'}')]!.add(i);
  }

  List<int> orderGroup(List<int> idxs) {
    if (idxs.length <= 2) return idxs;
    // greedy nearest neighbor, start at the first with coords else first
    int current = idxs.firstWhere((i) => meta[i]['lat'] != null, orElse: () => idxs.first);
    final remaining = idxs.toSet()..remove(current);
    final order = <int>[current];
    while (remaining.isNotEmpty) {
      double? clat = (meta[current]['lat'] as num?)?.toDouble();
      double? clon = (meta[current]['lon'] as num?)?.toDouble();
      int next = remaining.first;
      double best = double.infinity;
      for (final j in remaining) {
        final lat = (meta[j]['lat'] as num?)?.toDouble();
        final lon = (meta[j]['lon'] as num?)?.toDouble();
        if (clat != null && lat != null) {
          final dist = _haversine(clat, clon ?? 0, lat, lon ?? 0);
          if (dist < best) { best = dist; next = j; }
        } else {
          next = j; break;
        }
      }
      order.add(next);
      remaining.remove(next);
      current = next;
    }
    return order;
  }

  return [
    ...orderGroup(groups[0]!),
    ...orderGroup(groups[1]!),
    ...orderGroup(groups[2]!),
  ];
}

/* ----------------------------- Data source fns ----------------------------- */

// Geocode with cache
Future<Map<String, double>?> _geocodeOSM(String query) async {
  if (_geocodeCache.containsKey(query)) return _geocodeCache[query];
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {'q': query, 'format': 'json', 'limit': '1'});
  try {
    final resp = await http.get(uri, headers: {'User-Agent': 'smart-trip-planner/0.3 (contact@example.com)'}).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) { _geocodeCache[query] = null; return null; }
    final arr = jsonDecode(resp.body) as List;
    if (arr.isEmpty) { _geocodeCache[query] = null; return null; }
    final m = arr.first as Map<String, dynamic>;
    final lat = double.tryParse('${m['lat']}');
    final lon = double.tryParse('${m['lon']}');
    final r = (lat == null || lon == null) ? null : {'lat': lat, 'lon': lon};
    _geocodeCache[query] = r;
    return r;
  } catch (_) { _geocodeCache[query] = null; return null; }
}

Future<Map<String, double>?> _geocodeInRadius(String query, Map<String, double> center, int radiusMeters) async {
  final r = await _geocodeOSM(query);
  if (r == null) return null;
  final km = _haversine(center['lat']!, center['lon']!, r['lat']!, r['lon']!);
  if ((km * 1000) <= radiusMeters) return r;
  return null;
}

// Fallback: find a named POI using OSM Nominatim within a radius
Future<Map<String, dynamic>?> _findNamedPOI(String query, Map<String, double> center, int radius) async {
  final cacheKey = 'named:$query@${center['lat']},${center['lon']}~$radius';
  if (_poiCache.containsKey(cacheKey)) return _poiCache[cacheKey];

  try {
    final params = {
      'q': query,
      'format': 'json',
      'limit': '5',
      'addressdetails': '1',
      'namedetails': '1',
    };
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
    final resp = await http.get(uri, headers: {'User-Agent': 'smart-trip-planner/0.3 (contact@example.com)'}).timeout(const Duration(seconds: 10));
    if (resp.statusCode == 200) {
      final arr = jsonDecode(resp.body) as List;
      Map<String, dynamic>? best;
      double bestDist = double.infinity;
      for (final e in arr) {
        final m = e as Map<String, dynamic>;
        final lat = double.tryParse('${m['lat']}');
        final lon = double.tryParse('${m['lon']}');
        if (lat == null || lon == null) continue;
        final distKm = _haversine(center['lat']!, center['lon']!, lat, lon);
        if (distKm * 1000 <= radius && distKm < bestDist) {
          best = {
            'name': (m['namedetails']?['name'] ?? m['display_name'] ?? query).toString(),
            'lat': lat,
            'lon': lon,
            'address': (m['display_name'] ?? query).toString(),
            'mapLink': _mapsSearchLink(lat, lon),
          };
          bestDist = distKm;
        }
      }
      if (best == null && arr.isNotEmpty) {
        final m = arr.first as Map<String, dynamic>;
        final lat = double.tryParse('${m['lat']}');
        final lon = double.tryParse('${m['lon']}');
        if (lat != null && lon != null) {
          best = {
            'name': (m['namedetails']?['name'] ?? m['display_name'] ?? query).toString(),
            'lat': lat,
            'lon': lon,
            'address': (m['display_name'] ?? query).toString(),
            'mapLink': _mapsSearchLink(lat, lon),
          };
        }
      }
      _poiCache[cacheKey] = best;
      return best;
    }
  } catch (_) {}

  final r = await _geocodeInRadius(query, center, radius);
  if (r != null) {
    final out = {
      'name': query,
      'lat': r['lat']!,
      'lon': r['lon']!,
      'address': query,
      'mapLink': _mapsSearchLink(r['lat']!, r['lon']!),
    };
    _poiCache[cacheKey] = out;
    return out;
  }

  _poiCache[cacheKey] = null;
  return null;
}

// Prefer precise place (any type) using Google Places when available
Future<Map<String, dynamic>?> _findPlacePrecise(String query, Map<String, double> center, int radius, {String? placesKey}) async {
  final cacheKey = 'place:$query@${center['lat']},${center['lon']}~$radius~${placesKey != null}';
  if (_poiCache.containsKey(cacheKey)) return _poiCache[cacheKey];

  if (placesKey != null) {
    try {
      final params = {
        'query': query,
        'location': '${center['lat']},${center['lon']}',
        'radius': '$radius',
        'key': placesKey,
      };
      final uri = Uri.https('maps.googleapis.com', '/maps/api/place/textsearch/json', params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        final results = (j['results'] as List? ?? []);
        if (results.isNotEmpty) {
          results.sort((a, b) {
            final ra = (a['rating'] as num?)?.toDouble() ?? 0;
            final rb = (b['rating'] as num?)?.toDouble() ?? 0;
            final ca = (a['user_ratings_total'] as num?)?.toInt() ?? 0;
            final cb = (b['user_ratings_total'] as num?)?.toInt() ?? 0;
            final cmp = rb.compareTo(ra);
            return cmp != 0 ? cmp : cb.compareTo(ca);
          });
          final r = results.first as Map<String, dynamic>;
          final name = '${r['name']}';
          final lat = (r['geometry']?['location']?['lat'] as num?)?.toDouble();
          final lon = (r['geometry']?['location']?['lng'] as num?)?.toDouble();
          final rating = (r['rating'] as num?)?.toDouble();
          final userRatings = (r['user_ratings_total'] as num?)?.toInt();
          final placeId = '${r['place_id']}';
          if (lat != null && lon != null) {
            final out = {
              'name': name,
              'lat': lat,
              'lon': lon,
              'address': r['formatted_address'] ?? name,
              'rating': rating,
              'userRatings': userRatings,
              'priceLevel': (r['price_level'] as num?)?.toInt(),
              'mapLink': 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(name)}&query_place_id=$placeId',
            };
            _poiCache[cacheKey] = out;
            return out;
          }
        }
      }
    } catch (_) {}
  }

  final fallback = await _findNamedPOI(query, center, radius);
  _poiCache[cacheKey] = fallback;
  return fallback;
}

// Hotels / lodging (budget-aware)
Future<Map<String, dynamic>?> _findLodging(String queryOrHint, Map<String, double> center, int radius, {String? placesKey, _Budget budget = _Budget.mid}) async {
  final cacheKey = 'lodging:$queryOrHint@${center['lat']},${center['lon']}~$radius~${placesKey != null}~$budget';
  if (_poiCache.containsKey(cacheKey)) return _poiCache[cacheKey];

  if (placesKey != null) {
    try {
      final params = {
        'query': queryOrHint,
        'location': '${center['lat']},${center['lon']}',
        'radius': '$radius',
        'type': 'lodging',
        'key': placesKey,
      };
      final uri = Uri.https('maps.googleapis.com', '/maps/api/place/textsearch/json', params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        final results = (j['results'] as List? ?? []);
        if (results.isNotEmpty) {
          results.sort((a, b) => _scorePlace(Map<String, dynamic>.from(b as Map), budget)
              .compareTo(_scorePlace(Map<String, dynamic>.from(a as Map), budget)));
          var r = Map<String, dynamic>.from(results.first as Map);
          if (budget == _Budget.low) {
            final cheap = results.where((e) => ((e['price_level'] as num?)?.toInt() ?? 2) <= 2).toList();
            if (cheap.isNotEmpty) r = Map<String, dynamic>.from(cheap.first as Map);
          }
          final name = '${r['name']}';
          final lat = (r['geometry']?['location']?['lat'] as num?)?.toDouble();
          final lon = (r['geometry']?['location']?['lng'] as num?)?.toDouble();
          final rating = (r['rating'] as num?)?.toDouble();
          final userRatings = (r['user_ratings_total'] as num?)?.toInt();
          final placeId = '${r['place_id']}';
          if (lat != null && lon != null) {
            final out = {
              'name': name,
              'lat': lat,
              'lon': lon,
              'address': r['formatted_address'] ?? name,
              'rating': rating,
              'userRatings': userRatings,
              'priceLevel': (r['price_level'] as num?)?.toInt(),
              'mapLink': 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(name)}&query_place_id=$placeId',
            };
            _poiCache[cacheKey] = out;
            return out;
          }
        }
      }
    } catch (_) {}
  }

  final fallback = await _findNamedPOI(queryOrHint, center, radius);
  _poiCache[cacheKey] = fallback;
  return fallback;
}

// Restaurants (budget-aware) – adaptive radius + distance-aware ranking
Future<Map<String, dynamic>?> _findRestaurant(
  String queryOrHint,
  Map<String, double> center,
  int radius, {
  String? placesKey,
  _Budget budget = _Budget.mid,
}) async {
  final cacheKey = 'rest:$queryOrHint@${center['lat']},${center['lon']}~$radius~${placesKey != null}~$budget';
  if (_poiCache.containsKey(cacheKey)) return _poiCache[cacheKey];

  // helper: convert Google result -> POI map
  Map<String, dynamic>? _toPoi(Map r) {
    final name = '${r['name']}';
    final lat = (r['geometry']?['location']?['lat'] as num?)?.toDouble();
    final lon = (r['geometry']?['location']?['lng'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    final rating = (r['rating'] as num?)?.toDouble();
    final userRatings = (r['user_ratings_total'] as num?)?.toInt();
    final placeId = '${r['place_id']}';
    return {
      'name': name,
      'lat': lat,
      'lon': lon,
      'address': r['formatted_address'] ?? name,
      'rating': rating,
      'userRatings': userRatings,
      'priceLevel': (r['price_level'] as num?)?.toInt(),
      'mapLink': 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(name)}&query_place_id=$placeId',
    };
  }

  // Rank by quality and proximity to destination center
  num _rank(Map r) {
    final s = _scorePlace(Map<String, dynamic>.from(r), budget);
    final lat = (r['geometry']?['location']?['lat'] as num?)?.toDouble();
    final lon = (r['geometry']?['location']?['lng'] as num?)?.toDouble();
    if (lat == null || lon == null) return s;
    final dKm = _haversine(center['lat']!, center['lon']!, lat, lon);
    // small distance penalty to prefer close options
    return s - (dKm * 0.08); // tweakable
  }

  if (placesKey != null) {
    try {
      // Try with adaptive radius to keep specificity but avoid wrong city
      final tries = <int>[
        radius,
        math.min(radius * 2, 30000),
        40000, // final broadened search
      ];

      Map<String, dynamic>? chosen;
      for (final rads in tries) {
        final params = {
          'query': queryOrHint,
          'location': '${center['lat']},${center['lon']}',
          'radius': '$rads',
          'type': 'restaurant',
          'key': placesKey,
        };
        final uri = Uri.https('maps.googleapis.com', '/maps/api/place/textsearch/json', params);
        final resp = await http.get(uri).timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) continue;

        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        final results = (j['results'] as List? ?? []);
        if (results.isEmpty) continue;

        // Sort by combined score (quality + proximity), then apply budget filter
        results.sort((a, b) => _rank(b as Map).compareTo(_rank(a as Map)));

        // If low budget, try to select <= $$ when available among top N
        final topN = results.take(8).toList();
        Map<String, dynamic>? pick;
        if (budget == _Budget.low) {
          final cheap = topN.where((e) => ((e['price_level'] as num?)?.toInt() ?? 2) <= 2).toList();
          if (cheap.isNotEmpty) pick = Map<String, dynamic>.from(cheap.first as Map);
        }
        pick ??= Map<String, dynamic>.from(topN.first as Map);

        final candidate = _toPoi(pick);
        if (candidate != null) {
          // Discard if very far (> 45km) which is likely wrong city
          final distKm = _haversine(center['lat']!, center['lon']!, candidate['lat'] as double, candidate['lon'] as double);
          if (distKm <= 45) {
            chosen = candidate;
            break;
          }
          // otherwise continue to next broaden try
        }
      }

      if (chosen != null) {
        _poiCache[cacheKey] = chosen;
        return chosen;
      }
    } catch (_) {/* fall through to OSM */}
  }

  // OSM fallback (no ratings). Prefer closest named restaurant.
  final q = '''
[out:json][timeout:25];
(
  node(around:${math.max(radius, 1500)},${center['lat']},${center['lon']})["amenity"="restaurant"]["name"];
  way(around:${math.max(radius, 1500)},${center['lat']},${center['lon']})["amenity"="restaurant"]["name"];
);
out center 15;
''';
  try {
    final resp = await http.post(
      Uri.parse('https://overpass-api.de/api/interpreter'),
      headers: {'Content-Type': 'text/plain; charset=UTF-8', 'User-Agent': 'smart-trip-planner/0.3 (contact@example.com)'},
      body: q,
    ).timeout(const Duration(seconds: 25));
    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final els = (json['elements'] as List? ?? []);
      Map<String, dynamic>? best;
      double bestDist = double.infinity;
      for (final e in els) {
        final m = e as Map<String, dynamic>;
        double? lat, lon;
        if (m['lat'] != null && m['lon'] != null) { lat = (m['lat'] as num).toDouble(); lon = (m['lon'] as num).toDouble(); }
        else if (m['center'] != null) { lat = (m['center']['lat'] as num).toDouble(); lon = (m['center']['lon'] as num).toDouble(); }
        final name = (m['tags']?['name'] ?? '').toString();
        if (lat == null || lon == null || name.isEmpty) continue;
        final dKm = _haversine(center['lat']!, center['lon']!, lat, lon);
        if (dKm < bestDist) {
          bestDist = dKm;
          best = {'name': name, 'lat': lat, 'lon': lon, 'address': name, 'mapLink': _mapsSearchLink(lat, lon)};
        }
      }
      _poiCache[cacheKey] = best;
      return best;
    }
  } catch (_) {}
  _poiCache[cacheKey] = null;
  return null;
}

// OSRM route
Future<Map<String, String>> _osrmRoute(double fromLat, double fromLon, double toLat, double toLon) async {
  final url = Uri.parse('https://router.project-osrm.org/route/v1/driving/$fromLon,$fromLat;$toLon,$toLat?overview=false');
  try {
    final resp = await http.get(url).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return {};
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final r = (j['routes'] as List).first as Map<String, dynamic>;
    final distM = (r['distance'] as num).toDouble();
    final durS = (r['duration'] as num).toDouble();
    final distance = distM >= 1000 ? '${(distM / 1000).toStringAsFixed(1)} km' : '${distM.toStringAsFixed(0)} m';
    final hours = durS ~/ 3600;
    final mins = ((durS % 3600) / 60).round();
    final duration = hours > 0 ? '${hours}h ${mins}m' : '${mins} mins';
    return {'distanceText': distance, 'durationText': duration};
  } catch (_) { return {}; }
}

// Short description via Wikipedia
Future<String?> _wikiSnippet(String title, double lat, double lon) async {
  try {
    final g = await http.get(Uri.parse('https://en.wikipedia.org/w/api.php?action=query&list=geosearch&gscoord=$lat|$lon&gsradius=800&gslimit=1&format=json'))
      .timeout(const Duration(seconds: 8));
    if (g.statusCode == 200) {
      final j = jsonDecode(g.body) as Map<String, dynamic>;
      final arr = (j['query']?['geosearch'] as List? ?? []);
      final t = arr.isNotEmpty ? arr.first['title']?.toString() : title;
      if (t != null && t.isNotEmpty) {
        final s = await http.get(Uri.parse('https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(t)}'))
          .timeout(const Duration(seconds: 8));
        if (s.statusCode == 200) {
          final js = jsonDecode(s.body) as Map<String, dynamic>;
          return js['extract']?.toString();
        }
      }
    }
  } catch (_) {}
  return null;
}

/* ------------------------------ Helpers ----------------------------------- */

String _mapsSearchLink(double lat, double lon) =>
    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('$lat,$lon')}';

String _mapsDirLink(String origin, String destination) =>
    'https://www.google.com/maps/dir/?api=1&origin=${Uri.encodeComponent(origin)}&destination=${Uri.encodeComponent(destination)}';

String _esc(String s) => s.replaceAll('"', '\\"');

double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLon = _deg2rad(lon2 - lon1);
  final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
      math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) *
      (math.sin(dLon / 2) * math.sin(dLon / 2));
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}
double _deg2rad(double d) => d * 3.141592653589793 / 180.0;

// Choose a nearby anchor (prev/next item) for meal search; fallback to destination center
Future<Map<String, double>?> _anchorForMealItem({
  required int index,
  required List<Map<String, dynamic>> rawItems,
  required Map<String, double> destCenter,
  required int radius,
  String? placesKey,
}) async {
  Future<Map<String, double>?> resolve(Map<String, dynamic> it) async {
    final place = it['place']?.toString();
    final search = it['search']?.toString();
    final name = (place?.trim().isNotEmpty ?? false)
        ? place!
        : (search?.trim().isNotEmpty ?? false)
            ? search!
            : '';
    if (name.isEmpty) return null;
    final p = await _findPlacePrecise(name, destCenter, radius, placesKey: placesKey) ??
        await _findNamedPOI(name, destCenter, radius);
    if (p == null) return null;
    return {'lat': (p['lat'] as num).toDouble(), 'lon': (p['lon'] as num).toDouble()};
  }

  if (index > 0) {
    final c = await resolve(rawItems[index - 1]);
    if (c != null) return c;
  }
  if (index + 1 < rawItems.length) {
    final c = await resolve(rawItems[index + 1]);
    if (c != null) return c;
  }
  return destCenter;
}

// Add Arrival + Accommodation on Day 1 in enrichment (websearch will resolve the stay)
void _ensureArrivalAndStayOnDay0(String destination, _Budget budget, List<Map<String, dynamic>> items) {
  bool hasArrival = items.any((it) {
    final a = (it['activity'] ?? '').toString().toLowerCase();
    return a.contains('arrive') || a.contains('arrival') || a.contains('airport') || a.contains('transfer');
  });
  bool hasStay = items.any((it) {
    final a = (it['activity'] ?? '').toString().toLowerCase();
    final p = (it['place'] ?? '').toString().toLowerCase();
    final s = (it['search'] ?? '').toString().toLowerCase();
    return a.contains('hotel') || a.contains('check-in') || a.contains('check in') || a.contains('accommodation') ||
           p.contains('hotel') || p.contains('resort') || s.contains('hotel');
  });

  if (!hasArrival) {
    items.insert(0, {'time': '09:00', 'activity': 'Arrival', 'place': '$destination Airport'});
  }
  if (!hasStay) {
    final idx = items.length > 1 ? 1 : 0;
    items.insert(idx, {
      'time': '12:00',
      'activity': 'Accommodation: Check-in',
      'search': _lodgingSearchHint(destination, budget),
    });
  }
}

// --- Helpers to strengthen ambiguous queries ---

List<String> _splitDestinationCityCountry(String destination) {
  final parts = destination.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return ['', ''];
  if (parts.length == 1) return [parts.first, ''];
  return [parts.first, parts.sublist(1).join(', ')];
}

bool _isSingleWeakTerm(String s) {
  final t = s.trim();
  if (t.isEmpty) return true;
  // one word or very short
  final words = t.split(RegExp(r'\s+'));
  return words.length < 2 || t.length < 5;
}

String _strengthenQuery(
  String raw,
  String destination, {
  bool isRestaurant = false,
  bool isLodging = false,
  String? nearHint,
}) {
  var q = raw.trim();
  if (q.isEmpty) return q;

  final lc = q.toLowerCase();
  final hasNearOrIn = lc.contains(' near ') || lc.startsWith('near ') || lc.contains(' in ');
  final cityCountry = _splitDestinationCityCountry(destination);
  final city = cityCountry[0];
  final country = cityCountry[1];
  final placeCtx = (city.isNotEmpty && country.isNotEmpty) ? '$city, $country' : city.isNotEmpty ? city : destination;

  // If query is too weak or lacks context, add type and locality
  if (_isSingleWeakTerm(q) || !hasNearOrIn) {
    if (isRestaurant && !lc.contains('restaurant')) {
      q = 'restaurants $q';
    } else if (isLodging && !(lc.contains('hotel') || lc.contains('resort') || lc.contains('guest'))) {
      q = 'hotels $q';
    }
    if (!hasNearOrIn) {
      final hint = (nearHint != null && nearHint.trim().isNotEmpty) ? nearHint.trim() : placeCtx;
      q = '$q in $hint';
    }
  }

  return q;
}

// Distance gate for likely-wrong cities
bool _tooFarFrom(Map<String, double> center, Map<String, dynamic> poi, {double km = 45}) {
  final lat = (poi['lat'] as num?)?.toDouble();
  final lon = (poi['lon'] as num?)?.toDouble();
  if (lat == null || lon == null) return true;
  final dKm = _haversine(center['lat']!, center['lon']!, lat, lon);
  return dKm > km;
}
