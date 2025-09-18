import 'dart:isolate';

void echoWorker(SendPort sendPort) async {
  final port = ReceivePort();
  sendPort.send(port.sendPort);   //gives a channel back

  await for (final msg in port){
    final String text = msg[0] as String; //my message
    final SendPort replyPort = msg[1];  // where to send result

    final result = "Echo : ${text}";

    replyPort.send(result);
  }
}