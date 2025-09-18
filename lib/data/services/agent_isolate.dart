import "dart:isolate";
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:smart_trip_planner_flutter/constants.dart';
 

 void agentWorker(SendPort sendport) async {
  final port = ReceivePort();
  sendport.send(port.sendPort);

  await for( final msg in port){
    final String prompt = msg[0] as String;
    final SendPort replyPort = msg[1];

    try{
    final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: Secrets.api_key);
   
   final response = await model.generateContent([
  Content.text(
    """
    You are a smart travel planner.
    Always respond ONLY in valid JSON with this schema:
    { "title": string, "startDate": string, "endDate": string, "days": [ { "date": string, "summary": string, "items": [ { "time": string, "activity": string, "location": string } ] } ] }
    User request: $prompt
    """
  )
]);
   final output = response.text ?? "No response from gemini";

   replyPort.send({"ok": true,"data": output});
    } catch (e) {
      replyPort.send({"ok": false, "error": e.toString()});
    
    }
  }
 }