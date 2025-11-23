import 'package:flutter/material.dart';
import 'dart:async';

class TaskTimer extends StatefulWidget {
  final String task;

  const TaskTimer({super.key, required this.task});

  @override
  State<TaskTimer> createState() => _TaskTimerState();
}

class _TaskTimerState extends State<TaskTimer> {
  int seconds = 0;
  Timer? timer;
  bool running = false;

  void startTimer() {
    timer = Timer.periodic(Duration(seconds: 1), (_) {
      setState(() => seconds++);
    });
    setState(() => running = true);
  }

  void stopTimer() {
    timer?.cancel();
    setState(() => running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.task, style: TextStyle(fontSize: 22)),
            SizedBox(height: 8),
            Text("${seconds}s", style: TextStyle(fontSize: 28)),
            SizedBox(height: 12),
            running
                ? ElevatedButton(
                    onPressed: stopTimer,
                    child: Text("Stop"),
                  )
                : ElevatedButton(
                    onPressed: startTimer,
                    child: Text("Start"),
                  ),
          ],
        ),
      ),
    );
  }
}
