// lib/data/services/agent_isolate.dart
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:smart_trip_planner_flutter/constants.dart';

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

      // 1) Get skeleton (non-streaming JSON)
      final model = GenerativeModel(
        model: 'gemini-1.5-flash-latest',
        apiKey: geminiKey,
        generationConfig:  GenerationConfig(responseMimeType: 'application/json'),
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

      // 2) Ensure start..end coverage
      skeleton = _ensureContinuousDays(skeleton);

      // 3) Destination center (bounds)
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

      // 4) Enrich: geocode, restaurant ratings, map links, snippets
      final placesKey = const String.fromEnvironment('GOOGLE_PLACES_API_KEY', defaultValue: '');
      final enrichment = await _enrichSkeleton(
        skeleton,
        destCenter: destCenter,
        radiusMeters: 25000,
        placesKey: placesKey.isNotEmpty ? placesKey : null,
      );

      // 5) Validate Spec A strictly (human-readable locations only)
      final err = _validateSpecA(enrichment.itinerary);
      if (err != null) {
        reply.send({"type": "error", "ok": false, "data": "Schema error: $err"});
        continue;
      }

      reply.send({
        "type": "done",
        "ok": true,
        "data": enrichment.itinerary, // Spec A only
        "aux": enrichment.aux,        // coords, rating, mapLink, duration, distance, snippet
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

String _promptInstruction(String prompt, String? prevJson, String? chatHistoryJson) => '''
You are a professional travel planner.

Output ONLY JSON (no markdown). Return an itinerary SKELETON that tools will enrich.
Schema:
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
        { "time": "HH:mm", "activity": "Lunch", "search": "best restaurants near <area>" },
        { "time": "HH:mm", "activity": "Travel", "route": { "from": "City or landmark", "to": "City or landmark" } }
      ]
    }
  ]
}

Requirements:
- days MUST cover EVERY date from startDate..endDate inclusive.
- 3–5 items/day with realistic times (morning ~09:00, lunch ~13:00, afternoon ~15:00, evening ~18:30).
- Include at least one meal (Lunch/Dinner) most days using "search".
- Use known place names in the destination.

User prompt: $prompt
Previous itinerary JSON: ${prevJson ?? "null"}
Chat history: ${chatHistoryJson ?? "null"}
''';

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
    final items = (d['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    // Resolve all items in parallel to minimize latency
    final futures = <Future<void>>[];
    final resolved = List<Map<String, dynamic>>.filled(items.length, {});
    final meta = List<Map<String, dynamic>>.filled(items.length, {});

    for (int iIdx = 0; iIdx < items.length; iIdx++) {
      final it = items[iIdx];
      futures.add(() async {
        final time = '${it['time'] ?? ''}';
        final activity = '${it['activity'] ?? ''}';
        final route = it['route'] is Map ? Map<String, dynamic>.from(it['route'] as Map) : null;
        final placeRaw = it['place']?.toString();
        final searchRaw = it['search']?.toString();

        if (route != null) {
          // Travel: compute duration/distance; location -> toName
          final fromName = route['from']?.toString() ?? destination;
          final toName = route['to']?.toString() ?? destination;
          final fromGeo = await _geocodeInRadius(fromName, destCenter, radiusMeters);
          final toGeo = await _geocodeInRadius(toName, destCenter, radiusMeters);
          final m = <String, dynamic>{};
          if (fromGeo != null && toGeo != null) {
            final osrm = await _osrmRoute(fromGeo['lat']!, fromGeo['lon']!, toGeo['lat']!, toGeo['lon']!);
            m['lat'] = toGeo['lat'];
            m['lon'] = toGeo['lon'];
            m['distance'] = osrm['distanceText'];
            m['duration'] = osrm['durationText'];
            m['mapLink'] = _mapsDirLink(fromName, toName);
            m['address'] = toName;
          }
          resolved[iIdx] = {'time': time, 'activity': activity.isNotEmpty ? activity : 'Travel', 'location': toName};
          meta[iIdx] = m;
          return;
        }

        // POI / Restaurant
        Map<String, dynamic>? poi;
        if (placeRaw != null && placeRaw.trim().isNotEmpty) {
          poi = await _findNamedPOI(placeRaw, destCenter, radiusMeters);
        } else if (searchRaw != null && searchRaw.trim().isNotEmpty) {
          // If it's a meal, prefer restaurants around the destination center (or later: around previous anchor)
          poi = await _findRestaurant(searchRaw, destCenter, 1800, placesKey: placesKey);
          poi ??= await _findNamedPOI(searchRaw, destCenter, radiusMeters);
        }

        final locationName = poi?['name']?.toString() ??
            placeRaw?.toString() ??
            searchRaw?.toString() ??
            (activity.isNotEmpty ? activity : 'Place');

        final m = <String, dynamic>{};
        if (poi != null) {
          m['lat'] = poi['lat'];
          m['lon'] = poi['lon'];
          m['address'] = poi['address'] ?? locationName;
          m['mapLink'] = poi['mapLink'] ?? _mapsSearchLink(poi['lat'] as double, poi['lon'] as double);
          if (poi['rating'] != null) m['rating'] = poi['rating'];
          if (poi['userRatings'] != null) m['userRatings'] = poi['userRatings'];
          m['snippet'] = await _wikiSnippet(locationName, poi['lat'] as double, poi['lon'] as double);
        }

        resolved[iIdx] = {'time': time, 'activity': activity, 'location': locationName};
        meta[iIdx] = m;
      }());
    }
    await Future.wait(futures);

    // Reorder items for proximity within time slots while keeping meals in their slots
    final orderedIndex = _orderByProximity(resolved, meta);
    final orderedItems = <Map<String, dynamic>>[];
    for (final idx in orderedIndex) {
      orderedItems.add(resolved[idx]);
      aux['$dIdx:$idx'] = meta[idx];
    }

    outDays.add({'date': date, 'summary': summary, 'items': orderedItems});
  }

  return _Enrichment(
    {'title': title, 'startDate': startDate, 'endDate': endDate, 'days': outDays},
    aux,
  );
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

// Nominatim geocode
Future<Map<String, double>?> _geocodeOSM(String query) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {'q': query, 'format': 'json', 'limit': '1'});
  try {
    final resp = await http.get(uri, headers: {'User-Agent': 'smart-trip-planner/0.3 (contact@example.com)'}).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final arr = jsonDecode(resp.body) as List;
    if (arr.isEmpty) return null;
    final m = arr.first as Map<String, dynamic>;
    final lat = double.tryParse('${m['lat']}');
    final lon = double.tryParse('${m['lon']}');
    if (lat == null || lon == null) return null;
    return {'lat': lat, 'lon': lon};
  } catch (_) { return null; }
}

Future<Map<String, double>?> _geocodeInRadius(String query, Map<String, double> center, int radiusMeters) async {
  final r = await _geocodeOSM(query);
  if (r == null) return null;
  final km = _haversine(center['lat']!, center['lon']!, r['lat']!, r['lon']!);
  if ((km * 1000) <= radiusMeters) return r;
  return null;
}

// Named POI via Overpass name match, fallback to geocode
Future<Map<String, dynamic>?> _findNamedPOI(String name, Map<String, double> center, int radius) async {
  final q = '''
[out:json][timeout:25];
(
  node(around:$radius,${center['lat']},${center['lon']})[name~"${_esc(name)}",i];
  way(around:$radius,${center['lat']},${center['lon']})[name~"${_esc(name)}",i];
  relation(around:$radius,${center['lat']},${center['lon']})[name~"${_esc(name)}",i];
);
out center 20;
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
      if (els.isNotEmpty) {
        final m = els.first as Map<String, dynamic>;
        final tags = (m['tags'] as Map?) ?? {};
        final nameOut = '${tags['name'] ?? name}';
        double? lat, lon;
        if (m['lat'] != null && m['lon'] != null) { lat = (m['lat'] as num).toDouble(); lon = (m['lon'] as num).toDouble(); }
        else if (m['center'] != null) { lat = (m['center']['lat'] as num).toDouble(); lon = (m['center']['lon'] as num).toDouble(); }
        if (lat != null && lon != null) {
          return {'name': nameOut, 'lat': lat, 'lon': lon, 'address': tags['addr:full'] ?? tags['addr:street'] ?? nameOut};
        }
      }
    }
  } catch (_) {}
  // fallback to in-bounds geocode
  final g = await _geocodeInRadius(name, center, radius);
  if (g != null) {
    return {'name': name, 'lat': g['lat'], 'lon': g['lon'], 'address': name};
  }
  return null;
}

// Restaurants with ratings using Google Places (if key), else Overpass minimal
Future<Map<String, dynamic>?> _findRestaurant(String queryOrHint, Map<String, double> center, int radius, {String? placesKey}) async {
  // Prefer Google Places Text Search (best ratings + links)
  if (placesKey != null) {
    try {
      final params = {
        'query': queryOrHint,
        'location': '${center['lat']},${center['lon']}',
        'radius': '$radius',
        'type': 'restaurant',
        'key': placesKey,
      };
      final uri = Uri.https('maps.googleapis.com', '/maps/api/place/textsearch/json', params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        final results = (j['results'] as List? ?? []);
        if (results.isNotEmpty) {
          // Choose top by rating then user_ratings_total
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
            return {
              'name': name,
              'lat': lat,
              'lon': lon,
              'address': r['formatted_address'] ?? name,
              'rating': rating,
              'userRatings': userRatings,
              'mapLink': 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(name)}&query_place_id=$placeId',
            };
          }
        }
      }
    } catch (_) {}
  }

  // Minimal Overpass fallback (no ratings)
  final q = '''
[out:json][timeout:25];
(
  node(around:$radius,${center['lat']},${center['lon']})["amenity"="restaurant"]["name"];
  way(around:$radius,${center['lat']},${center['lon']})["amenity"="restaurant"]["name"];
);
out center 10;
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
      if (els.isNotEmpty) {
        final e = els.first as Map<String, dynamic>;
        double? lat, lon;
        if (e['lat'] != null && e['lon'] != null) { lat = (e['lat'] as num).toDouble(); lon = (e['lon'] as num).toDouble(); }
        else if (e['center'] != null) { lat = (e['center']['lat'] as num).toDouble(); lon = (e['center']['lon'] as num).toDouble(); }
        final name = (e['tags']?['name'] ?? 'Restaurant').toString();
        if (lat != null && lon != null) {
          return {'name': name, 'lat': lat, 'lon': lon, 'address': name, 'mapLink': _mapsSearchLink(lat, lon)};
        }
      }
    }
  } catch (_) {}
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
