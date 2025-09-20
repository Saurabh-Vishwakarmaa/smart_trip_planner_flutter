import 'dart:isolate';


//this is only for understanding isolate working
void echoWorker(SendPort sendPort) async {
  final port = ReceivePort();
  sendPort.send(port.sendPort);   //gives a channel back

  await for (final msg in port){
    final String text = msg[0] as String; 
    final SendPort replyPort = msg[1];  

    final result = "Echo : ${text}";

    replyPort.send(result);
  }
}