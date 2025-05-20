import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart'; // 🔧 新增這行

// 主函式，初始化 Flutter 綁定並啟動背景服務與應用程式介面
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();// 確保初始化
  await initializeService();//背景服務函式執行
  runApp(const MyApp());
}
// 初始化背景服務
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  // 定義 Android 的通知頻道（前景服務會用到）
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground', // 頻道 ID：唯一識別這個頻道的字串，日後用來發送通知時指定要用哪個頻道。（注意：這個 ID 一旦建立後，無法再更改頻道設定，除非卸載 App）
    'MY FOREGROUND SERVICE', //  頻道名稱：會顯示在 Android 的通知設定裡，讓使用者知道這是什麼類型的通知。
    description:
        'This channel is used for important notifications.', //  頻道描述：用於向使用者說明這個通知頻道的用途，也會顯示在系統設定裡。
    importance: Importance.max, // 通知顯示優先順序設定，設low會導致鎖屏通知不顯示，要鎖屏通知顯示就要設成max或high
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();//在 flutter_local_notifications 中，要使用通知功能（像 .show()、.initialize() 等），就必須透過這個類別提供的方法來進行操作
// 初始化通知系統（iOS 與 Android）
  if (Platform.isIOS || Platform.isAndroid) {
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        iOS: DarwinInitializationSettings(),
        android: AndroidInitializationSettings('ic_bg_service_small'),
      ),
    );
  }
  // 建立通知頻道（僅 Android）
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
// 設定背景服務的行為（Android 與 iOS 分別處理）
  await service.configure(
    //android初始設定
    androidConfiguration: AndroidConfiguration(
      // 這裡設定 Android 平台上背景服務的行為
      onStart: onStart,//當服務啟動時要執行的函式。這個函式中可以放背景處理邏輯，例如定時通知、資料同步等。

      autoStart: true,//是否在 App 啟動時自動啟動背景服務。設為 true 表示 App 一啟動就會執行背景服務。
      isForegroundMode: true,//是否使用 前景服務 模式，讓 Android 系統不會因為省電或記憶體而強制終止服務。前景服務會顯示常駐通知。

      notificationChannelId: 'my_foreground',//指定前景通知要使用的頻道 ID，這裡要和你建立的 AndroidNotificationChannel ID 一致，否則通知會失效。
      initialNotificationTitle: 'AWESOME SERVICE',//當前景服務剛啟動時顯示的通知標題。
      initialNotificationContent: 'Initializing',//當前景服務剛啟動時顯示的通知內容
      foregroundServiceNotificationId: 888,//指定前景服務通知的 ID，這個 ID 讓你之後可以用同一 ID 來更新通知內容。

      foregroundServiceTypes: [AndroidForegroundType.location],//設定前景服務屬性，這裡設為 location 表示這個服務涉及定位功能（系統會優化資源分配和權限提示）。


    ),
    //ios初始設定
    iosConfiguration: IosConfiguration(
      // 這是 iOS 上背景服務的行為設定。


      autoStart: true,


      onForeground: onStart,// App 在前景時執行的背景邏輯。這對 iOS 很重要，因為 Apple 限制了背景運作的方式


      onBackground: onIosBackground,// 設定當 App 被系統喚醒進行「背景擷取（Background Fetch）」時執行的函式。需要在 Xcode 打開相關 capability 才能生效。
    ),
  );
}

// to ensure this is executed
// run app from xcode, then from xcode menu, select Simulate Background Fetch
// iOS 背景抓取時執行的函式
@pragma('vm:entry-point')//對於背景服務函式來說是必要的程式碼，否則在 release 模式下可能不會執行
Future<bool> onIosBackground(ServiceInstance service) async {        //當 iOS 透過 Background Fetch 喚醒你的 app 時，這個函式會執行
  WidgetsFlutterBinding.ensureInitialized();//初始化 Flutter 的綁定。這是使用 Flutter 功能（如 SharedPreferences）前的必要步驟
  DartPluginRegistrant.ensureInitialized();//確保 Flutter plugin（如 shared_preferences）在背景 isolate 中能正確啟用。如果在背景任務中使用 plugin（不是內建 Dart 套件），就需要這行
// 儲存背景執行的時間紀錄到 SharedPreferences
  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final log = preferences.getStringList('log') ?? <String>[];//嘗試讀取名為 'log' 的字串清單，如果沒有就建立一個新的空清單
  log.add(DateTime.now().toIso8601String());//將目前的時間（ISO 8601 格式）新增到清單中，表示這次背景抓取的時間
  await preferences.setStringList('log', log);//將更新後的清單寫回 SharedPreferences 中，達成「紀錄背景執行時間」的目的

  return true;//表示背景任務執行成功（iOS 會根據回傳值決定是否要繼續允許抓取）
}
// 背景服務啟動後執行的主邏輯
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async { //定義背景服務的啟動函式 onStart，當服務啟動時會被執行，service 是當前的背景服務實例，可用來控制它（如通知、停止等）
  // Only available for flutter 3.0.0 and later
  DartPluginRegistrant.ensureInitialized();//確保背景 isolate 中可以使用 Flutter plugin（如 SharedPreferences、通知插件），必須加這行，否則在背景中會發生 plugin 無法使用的錯誤

  // For flutter prior to version 3.0.0
  // We have to register the plugin manually

  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.setString("hello", "world");

  /// OPTIONAL when use custom notification
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();//建立通知插件的實例，用來顯示本機通知（如你設定的前景通知）


// 監聽從 UI 傳來的事件，切換前景／背景／停止服務
  if (service is AndroidServiceInstance) { //檢查目前是否為 Android 服務（因為 iOS 沒有前景／背景概念）
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });//當收到來自前端的 "setAsForeground" 指令時，將服務轉為「前景服務」（顯示持續通知）

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });//當收到 "setAsBackground" 指令時，將服務轉為背景模式（取消通知）
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });//當收到 "stopService" 指令時，停止這個背景服務

  // 每秒執行一次的定時器
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (service is AndroidServiceInstance) {   //確認這是 Android
      if (await service.isForegroundService()) {   //確認目前為「前景服務」狀態


        // 顯示通知（自訂通知），標題為 'COOL SERVICE'，內容為目前時間，888 是通知的 ID（重複使用會更新）
        flutterLocalNotificationsPlugin.show(
          888,
          'COOL SERVICE',
          'Awesome ${DateTime.now()}',
          const NotificationDetails(    //設定通知細節，使用前面建立的通知頻道 my_foreground
            android: AndroidNotificationDetails(
              'my_foreground',
              'MY FOREGROUND SERVICE',
              icon: 'ic_bg_service_small',
              ongoing: true,
              visibility: NotificationVisibility.public,
            ),
          ),
        );

        // 更新系統通知內容
        service.setForegroundNotificationInfo(
          title: "前景通知測試",
          content: "現在時間 ${DateTime.now()}",
        );
      }
    }

    /// you can see this log in logcat
    debugPrint('FLUTTER BACKGROUND SERVICE: ${DateTime.now()}');//使用 debugPrint 印出目前時間到 Logcat（Android 的除錯控制台），可用來確認背景服務是否正常運作，或是否每秒都被觸發

    // 取得裝置資訊（Android 或 iOS）
    final deviceInfo = DeviceInfoPlugin();//初始化 DeviceInfoPlugin 插件，用來抓取目前設備的硬體資訊（例如：型號、OS 版本等）
    String? device;//宣告變數 device，準備存放裝置名稱（例如：Pixel 5、iPhone 14 等）
    if (Platform.isAndroid) {  //如果是 Android 裝置
      final androidInfo = await deviceInfo.androidInfo;//呼叫 androidInfo 取得 Android 裝置資訊
      device = androidInfo.model;//從中取出 model（設備型號），指定給 device 變數
    } else if (Platform.isIOS) {  //如果是 iOS 裝置
      final iosInfo = await deviceInfo.iosInfo;//呼叫 iosInfo 取得 iOS 裝置資訊
      device = iosInfo.model;//從中取出 model（設備型號），指定給 device 變數
    }
    // 傳送更新事件到前端（UI）
    service.invoke(
      'update',  //使用 service.invoke 發送一個名為 "update" 的事件
      {
        "current_date": DateTime.now().toIso8601String(),//目前時間的字串格式（ISO 8601）
        "device": device,//裝置的型號名稱
      },
    );
  });
}
// 主應用程式 UI
class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String text = "Stop Service";

  @override
  void initState() {
    super.initState();
    _checkAndPromptNotificationPermission();
  }
  Future<bool> _isAndroid13OrAbove() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.version.sdkInt >= 33;
  }
  Future<void> _checkAndPromptNotificationPermission() async {
    if (Platform.isAndroid && await _isAndroid13OrAbove()) {
      final status = await Permission.notification.status;

      if (status.isDenied) {
        // 這裡會跳出系統對話框
        final result = await Permission.notification.request();

        if (result.isDenied || result.isPermanentlyDenied) {
          // 使用者拒絕或永久拒絕後再跳自訂對話框提示去設定
          // ignore: use_build_context_synchronously
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("通知權限未開啟"),
              content: const Text("請到設定中開啟通知功能以獲得完整功能"),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await openAppSettings();
                  },
                  child: const Text("前往設定"),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("知道了"),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Service App'),
        ),
        body: Column(
          children: [
            StreamBuilder<Map<String, dynamic>?>(
              stream: FlutterBackgroundService().on('update'),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data!;
                String? device = data["device"];
                DateTime? date =
                DateTime.tryParse(data["current_date"] ?? "");
                return Column(
                  children: [
                    Text(device ?? 'Unknown'),
                    Text(date.toString()),
                  ],
                );
              },
            ),
            ElevatedButton(
              child: const Text("Foreground Mode"),
              onPressed: () =>
                  FlutterBackgroundService().invoke("setAsForeground"),
            ),
            ElevatedButton(
              child: const Text("Background Mode"),
              onPressed: () =>
                  FlutterBackgroundService().invoke("setAsBackground"),
            ),
            ElevatedButton(
              child: Text(text),
              onPressed: () async {
                final service = FlutterBackgroundService();
                var isRunning = await service.isRunning();
                isRunning
                    ? service.invoke("stopService")
                    : service.startService();

                setState(() {
                  text = isRunning ? 'Start Service' : 'Stop Service';
                });
              },
            ),
            const Expanded(child: LogView()),
          ],
        ),
      ),
    );
  }
}
// 顯示從 SharedPreferences 讀取的紀錄清單
class LogView extends StatefulWidget {  //LogView 每秒從 SharedPreferences 讀取 log 清單，並更新 UI 顯示背景服務記錄的時間。這對於監看背景任務執行紀錄特別有用
  const LogView({Key? key}) : super(key: key);

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  late final Timer timer;
  List<String> logs = [];

  @override
  void initState() {
    super.initState();//initState() 是 widget 初始化階段會執行的生命週期方法
    // 每秒重新載入紀錄並更新畫面
    timer = Timer.periodic(const Duration(seconds: 1), (timer) async {  //每秒執行一次的定時器
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.reload();//reload() 會重新讀取資料（避免快取舊值）
      logs = sp.getStringList('log') ?? [];//從 SharedPreferences 中取得 key 為 'log' 的字串清單（背景服務儲存的時間紀錄），若為空則預設為空清單
      if (mounted) { //mounted 是用來確認 widget 是否還在畫面上
        setState(() {}); //setState() 會觸發畫面重繪，顯示最新的 logs
      }
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }//當 widget 被移除時（如畫面關閉），取消定時器避免資源浪費

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs.elementAt(index);
        return Text(log);
      },
    );
  }
}
