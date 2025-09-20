import 'package:google_generative_ai/google_generative_ai.dart';

class TokenUsage {
  final String model;
  final int prompt;
  final int completion;
  final int total;
  final double inputRatePerM;
  final double outputRatePerM;
  final double costUSD;

  const TokenUsage({
    required this.model,
    required this.prompt,
    required this.completion,
    required this.total,
    required this.inputRatePerM,
    required this.outputRatePerM,
    required this.costUSD,
  });

  Map<String, dynamic> toJson() => {
        'model': model,
        'prompt': prompt,
        'completion': completion,
        'total': total,
        'inputRatePerM': inputRatePerM,
        'outputRatePerM': outputRatePerM,
        'costUSD': double.parse(costUSD.toStringAsFixed(4)),
        'cost': double.parse(costUSD.toStringAsFixed(4)), // legacy alias
      };
}

class _Pricing {
  final double inPerM;
  final double outPerM;
  const _Pricing(this.inPerM, this.outPerM);
}

// USD per 1M tokens (Google public pricing)
const Map<String, _Pricing> _pricing = {
  'gemini-1.5-flash-latest': _Pricing(0.35, 0.53),
  'gemini-1.5-flash': _Pricing(0.35, 0.53),
  'gemini-1.5-pro-latest': _Pricing(3.50, 10.50),
  'gemini-1.5-pro': _Pricing(3.50, 10.50),
};

_Pricing _pick(String model) => _pricing[model] ?? _pricing['gemini-1.5-flash-latest']!;

// Rough fallback: ~4 chars/token
int _approxTokens(String s) => s.isEmpty ? 0 : (s.length / 4).ceil();

double _estimateCost({required String model, required int inTok, required int outTok}) {
  final p = _pick(model);
  return (inTok / 1e6) * p.inPerM + (outTok / 1e6) * p.outPerM;
}

TokenUsage buildTokenUsage({
  required String modelId,
  required UsageMetadata? usage,
  String? inputText,
  String? outputText,
}) {
  var inTok = usage?.promptTokenCount ?? 0;
  var outTok = usage?.candidatesTokenCount ?? 0;
  var total = usage?.totalTokenCount ?? 0;

  if (inTok == 0 && outTok == 0) {
    inTok = inputText != null ? _approxTokens(inputText) : 0;
    outTok = outputText != null ? _approxTokens(outputText) : 0;
  }
  if (total == 0) total = inTok + outTok;

  final pr = _pick(modelId);
  final cost = _estimateCost(model: modelId, inTok: inTok, outTok: outTok);

  return TokenUsage(
    model: modelId,
    prompt: inTok,
    completion: outTok,
    total: total,
    inputRatePerM: pr.inPerM,
    outputRatePerM: pr.outPerM,
    costUSD: cost,
  );
}