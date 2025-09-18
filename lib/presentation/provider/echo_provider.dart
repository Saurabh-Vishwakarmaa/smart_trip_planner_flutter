import 'dart:isolate';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:smart_trip_planner_flutter/data/services/echo_isolate.dart';

final echoAgentProvider = FutureProvider<SendPort>((ref) async {
final recievePort = ReceivePort();
await Isolate.spawn(echoWorker, recievePort.sendPort);

return await recievePort.first as SendPort;

});

class EchoNotifier extends StateNotifier<AsyncValue<String>>{
  EchoNotifier(this.ref) : super(const AsyncValue.data(""));

  final Ref ref;
  Future<void> sendMessage(String text) async{
        state = const AsyncValue.loading();

        try {
          final sendPort  = await ref.read(echoAgentProvider.future);
          final responsePort = ReceivePort();


     sendPort.send([text,responsePort.sendPort]);
      final result = await responsePort.first as String;
      state = AsyncValue.data(result);

        
        }
        catch(e, st){
          state = AsyncValue.error(e, st);
        }

  }
}
final echoProvider =
    StateNotifierProvider<EchoNotifier, AsyncValue<String>>(
        (ref) => EchoNotifier(ref));
