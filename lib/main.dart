import 'dart:io';
import 'dart:isolate';

import 'package:Nebula/utils/extra.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'controllers/device_controller.dart';
import 'screens/scan_screen.dart';
import 'services/init_services.dart';
import 'utils/snackbar.dart';
import 'widgets/smartwatch_info.dart';
import 'package:get/get.dart';

void main() {
  FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);
  ApplicationController controller = ApplicationController();
  Get.put(controller);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system,
      home: InfoPage(),
    );
  }
}

class InfoPage extends StatefulWidget {
  @override
  _InfoPageState createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  final ApplicationController controller = Get.find();

  @override
  void initState() {
    super.initState();
    connectToDevice();
  }

  Future<void> connectToDevice() async {
    bool isPermissionGranted =
        await NotificationListenerService.isPermissionGranted();

    if (!isPermissionGranted) {
      await NotificationListenerService.requestPermission();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final uuid = prefs.getString('uuid') ?? "";
      final deviceName = prefs.getString('deviceName') ?? "";

      if (uuid.isNotEmpty && deviceName.isNotEmpty) {
        controller.setDeviceInfoName(deviceName);
        controller.myDevice.value =
            BluetoothDevice(remoteId: DeviceIdentifier(uuid));
        await controller.myDevice.value.connectAndUpdateStream();
        setState(() {
          controller.myDevice.value = controller.myDevice.value;
        });
        initServices();
      } else {
        Snackbar.show(ABC.c, "UUID or Device Name is empty", success: false);
      }
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Connect Error:", e),
          success: false);
    }
    await Future.delayed(Duration(seconds: 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Nebula'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[BluetoothDeviceInfoWidget(), ScreenTest()],
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 20.0), // Margine inferiore
        child: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ScanScreen(),
              ),
            );
          },
          child: Icon(Icons.bluetooth_searching),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
    );
  }
}

class ApplicationBinding implements Bindings {
  @override
  void dependencies() {
    Get.lazyPut((() => ApplicationController()));
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  SendPort? _sendPort;
  int _eventCount = 0;
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) async {
    _sendPort = sendPort;
    final customData =
        await FlutterForegroundTask.getData<String>(key: 'customData');
    print('customData: $customData');
    main();
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    FlutterForegroundTask.updateService(
      notificationTitle: 'MyTaskHandler',
      notificationText: 'eventCount: $_eventCount',
    );
    sendPort?.send(_eventCount);
    _eventCount++;
    // main();
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) async {
    print('onDestroy');
  }

  @override
  void onNotificationButtonPressed(String id) {
    print('onNotificationButtonPressed >> $id');
  }

  @override
  void onNotificationPressed() {
    // FlutterForegroundTask.launchApp("/resume-route");
    _sendPort?.send('onNotificationPressed');
  }
}

class ScreenTest extends StatefulWidget {
  const ScreenTest({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => ScreenTestState();
}

class ScreenTestState extends State<ScreenTest> {
  ReceivePort? _receivePort;

  Future<void> _requestPermissionForAndroid() async {
    if (!Platform.isAndroid) {
      return;
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    final NotificationPermission notificationPermissionStatus =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermissionStatus != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        id: 500,
        channelId: 'foreground_service',
        channelName: 'Foreground Service Notification',
        channelDescription:
            'This notification appears when the foreground service is running.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
          backgroundColor: Colors.orange,
        ),
        buttons: [
          const NotificationButton(
            id: 'sendButton',
            text: 'Send',
            textColor: Colors.orange,
          ),
          const NotificationButton(
            id: 'testButton',
            text: 'Test',
            textColor: Colors.grey,
          ),
        ],
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<bool> _stopForegroundTask() {
    return FlutterForegroundTask.stopService();
  }

  bool _registerReceivePort(ReceivePort? newReceivePort) {
    if (newReceivePort == null) {
      return false;
    }

    _closeReceivePort();

    _receivePort = newReceivePort;
    _receivePort?.listen((data) {
      if (data is int) {
        print('eventCount: $data');
      } else if (data is String) {
        if (data == 'onNotificationPressed') {
          Navigator.of(context).pushNamed('/resume-route');
        }
      } else if (data is DateTime) {
        print('timestamp: ${data.toString()}');
      }
    });

    return _receivePort != null;
  }

  void _closeReceivePort() {
    _receivePort?.close();
    _receivePort = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _requestPermissionForAndroid();
      _initForegroundTask();
      if (await FlutterForegroundTask.isRunningService) {
        final newReceivePort = FlutterForegroundTask.receivePort;
        _registerReceivePort(newReceivePort);
      } else {
        _startForegroundTask();
      }
    });
  }

  @override
  void dispose() {
    _closeReceivePort();
    super.dispose();
  }

  Future<bool> _startForegroundTask() async {
    await FlutterForegroundTask.saveData(key: 'customData', value: 'hello');
    final ReceivePort? receivePort = FlutterForegroundTask.receivePort;
    final bool isRegistered = _registerReceivePort(receivePort);
    if (!isRegistered) {
      print('Failed to register receivePort!');
      return false;
    }

    if (await FlutterForegroundTask.isRunningService) {
      return FlutterForegroundTask.restartService();
    } else {
      return FlutterForegroundTask.startService(
        notificationTitle: 'Foreground Service is running',
        notificationText: 'Tap to return to the app',
        callback: startCallback,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(child: _buildContentView());
  }

  Widget _buildContentView() {
    buttonBuilder(String text, {VoidCallback? onPressed}) {
      return ElevatedButton(
        onPressed: onPressed,
        child: Text(text),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // buttonBuilder('start', onPressed: _startForegroundTask),
          // buttonBuilder('stop', onPressed: _stopForegroundTask),
        ],
      ),
    );
  }
}
