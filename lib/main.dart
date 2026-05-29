import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:siprix_voip_sdk/accounts_model.dart';

//import 'package:firebase_core/firebase_core.dart';
//import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:siprix_voip_sdk/messages_model.dart';
import 'package:siprix_voip_sdk/network_model.dart';
import 'package:siprix_voip_sdk/cdrs_model.dart';
import 'package:siprix_voip_sdk/devices_model.dart';
import 'package:siprix_voip_sdk/logs_model.dart';
import 'package:siprix_voip_sdk/subscriptions_model.dart';
import 'package:siprix_voip_sdk/siprix_voip_sdk.dart';
import 'package:siprix_voip_sdk_example/voip_ios_config.dart';

import 'accouns_model_app.dart';
import 'callkit_event_bridge.dart';
import 'callkit_incoming_fallback.dart';
import 'calls_model_app.dart';
import 'sip_repository.dart';
import 'subscr_model_app.dart';

import 'account_add.dart';
import 'call_add.dart';
import 'subscr_add.dart';
import 'settings.dart';
import 'home.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_notification_service.dart';
import 'firebase_options.dart';
import 'siprix_app_init.dart';
//const FirebaseOptions gFCMOptions = FirebaseOptions(
//      apiKey: '...',            //Copy from `google-services.json` - `client.api_key.current_key`
//      appId: '...',             //Copy from `google-services.json` - `client.client_info.mobilesdk_app_id`
//      messagingSenderId: '...', //Copy from `google-services.json` - `project_info.project_number`
//      projectId: '...',         //Copy from `google-services.json` - `project_info.project_id`
//      storageBucket: '...'      //Copy from `google-services.json` - `project_info.storage_bucket`
//);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //Wait while Firebase initialized
  await _initializeFCM();

  //Create models
  LogsModel logsModel           = LogsModel(true);//Set 'false' when logs won't rendering on UI
  SipRepository.configure(logs: logsModel);
  CdrsModel cdrsModel           = CdrsModel();//List of recent calls (Call Details Records)

  DevicesModel devicesModel      = DevicesModel(logsModel);//List of devices
  NetworkModel networkModel      = NetworkModel(logsModel);//Network state details
  AppAccountsModel accountsModel = AppAccountsModel(logsModel);//List of accounts
  MessagesModel messagesModel    = MessagesModel(accountsModel, logsModel);//List of messages
  AppCallsModel callsModel       = AppCallsModel(accountsModel, logsModel, cdrsModel);//List of calls
  // onCallKitUserHangupSync =
  //     (sipId, uuid) => callsModel.syncAfterCallKitUserHangup(sipId, uuid);
  // resolveSipCallIdForCallKitUuid = callsModel.findSipCallIdByCallKitUuid;
  SubscriptionsModel subscrModel = SubscriptionsModel(accountsModel, createSubscrFromJson, logsModel);//List of subscriptions
  //VuMeterModel vuModel         = VuMeterModel();
  //VoiceMailModel vmModel       = VoiceMailModel(logsModel);

  // Firebase is initialized in [_initializeFCM] before [runApp].

  try {
    // iOS: use GoogleService-Info.plist (Dart options still have iOS placeholders).
    if (Platform.isIOS) {
      await Firebase.initializeApp();
    } else {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {
    // Already initialized by google-services.json / native plugin
  }


  // if (Platform.isAndroid) {
  // await setupAndroidCallNotificationChannel();
  // }

  // FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);


  //Run app
  runApp(
    MultiProvider(providers:[
      ChangeNotifierProvider(create: (context) => accountsModel),
      ChangeNotifierProvider(create: (context) => networkModel),
      ChangeNotifierProvider(create: (context) => devicesModel),
      ChangeNotifierProvider(create: (context) => messagesModel),
      ChangeNotifierProvider(create: (context) => subscrModel),
      ChangeNotifierProvider(create: (context) => callsModel),
      ChangeNotifierProvider(create: (context) => cdrsModel),
      ChangeNotifierProvider(create: (context) => logsModel),
      //ChangeNotifierProvider(create: (context) => vuModel),
      //ChangeNotifierProvider(create: (context) => vmModel),
    ],
    child: const MyApp(),
  ));
}


Future<void> _initializeFCM() async {
  if (Platform.isAndroid) {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  //!!! Method is working in the background isolate!
  //!!! At this moment Activity may not exist or whole App could be completely stopped
  //!!! Code below initializes Siprix, adds saved accounts and refreshes registration (makes app ready to receive incoming call)

  debugPrint("[!!!] Handling a background message id:'${message.messageId}' data:'${message.data}'");

  try{
    debugPrint("Initialize siprix by push notif");
    // Must complete before addAccount/registerAccount — otherwise channel calls race
    // and the native plugin can reject invocations (e.g. "Bad argument. Map with fields expected").
    await _MyAppState._initializeSiprix();

    debugPrint("Read and add accounts by push notif");
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String accJsonStr = prefs.getString('accounts') ?? '';
    if(accJsonStr.isNotEmpty) {
      AppAccountsModel tmpAccsModel = AppAccountsModel();
      await tmpAccsModel.loadFromJson(accJsonStr);
      await tmpAccsModel.refreshRegistration();
    }
  } on Exception catch (err) {
    debugPrint('Error: ${err.toString()}');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  static String _ringtonePath="";

  @override
  State<MyApp> createState() => _MyAppState();

  /// Returns ringtone's path saved on device
  static String getRingtonePath() => _ringtonePath;

  /// Write ringtone file from asset to device
  void writeRingtoneAsset() async {
    _ringtonePath = await writeAssetAndGetFilePath("ringtone.mp3");
  }

  /// Write file from assest to device and returns path to it
  static Future<String> writeAssetAndGetFilePath(String assetsFileName) async {
    var homeFolder = await SiprixVoipSdk().homeFolder();
    var filePath = '$homeFolder$assetsFileName';

    var file = File(filePath);
    var exists = file.existsSync();
    debugPrint("writeAsset: '$filePath' exists:$exists");
    if (exists) return filePath;

    final byteData = await rootBundle.load('assets/$assetsFileName');
    await file.create(recursive: true);
    file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    return filePath;
  }

  /// Returns path and file name for recorded file
  static Future<String> getRecFilePathName(int callId) async {
    String dateTime = DateFormat('yyyyMMdd_HHmmss_').format(DateTime.now());
    var homeFolder = await SiprixVoipSdk().homeFolder();
    var filePath = '$homeFolder$dateTime$callId.mp3';
    return filePath;
  }
}

class _MyAppState extends State<MyApp> {
  /// Android only; must stay nullable without [late] — on iOS we never assign and
  /// [late final] would throw on first read in [dispose].
  AppLifecycleListener? _listener;
  bool _lastIosNetworkLost = false;
  NetworkModel? _iosNetworkModel;

  @override
  void initState() {
    super.initState();

    registerIncomingSipFallbackCallKitListener();

    // Must finish Siprix init before loadFromJson/addAccount. Otherwise a VoIP/FCM
    // wake from kill state can race: accounts register before native init completes
    // and the incoming leg can drop when init or registration runs again.
    _bootAfterFirstFrame();

    if (Platform.isIOS) {
      _listener = AppLifecycleListener(
        onResume: _onIosAppResume,
        onRestart: _onIosAppResume,
      );
      _iosNetworkModel = context.read<NetworkModel>();
      _lastIosNetworkLost = _iosNetworkModel?.networkLost ?? false;
      _iosNetworkModel?.addListener(_onIosNetworkStateChanged);
    } else if (Platform.isAndroid) {
      _listener = AppLifecycleListener(onInactive: _onAndroidAppInactive);
    }
  }

  Future<void> _bootAfterFirstFrame() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final logs = context.read<LogsModel>();
    await _initializeSiprix(logs);
    if (!mounted) return;
    widget.writeRingtoneAsset(); // uses Siprix homeFolder
    _readSavedState();
  }

  /// Wire [onSaveChanges] before any async prefs work so a fast "add account"
  /// cannot run while callbacks are still null.
  void _wireModelPersistence() {
    if (!mounted) return;
    context.read<AppAccountsModel>().onSaveChanges = _saveAccountChanges;
    context.read<SubscriptionsModel>().onSaveChanges = _saveSubscriptionChanges;
    context.read<MessagesModel>().onSaveChanges = _saveMessagesChanges;
    context.read<CdrsModel>().onSaveChanges = _saveCdrsChanges;
  }

  Future<void> _configureFirebaseNotificationsSafely() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    try {
      await FirebaseNotificationService.instance.initialize();

      if (Platform.isAndroid) {
        await setupAndroidCallNotificationChannel();
      }

      if (!mounted) return;
      final calls = context.read<AppCallsModel>();
      final accounts = context.read<AppAccountsModel>();
      FirebaseNotificationService.instance.onForegroundMessage = (data) async {
        debugPrint('[FCM] foreground push: $data');
        if (!mounted || !Platform.isIOS) return;
        try {
          await accounts.refreshRegistrationForWake(reason: 'ios_fcm_foreground');
          debugPrint('[FCM] SIP registration refreshed after foreground push (iOS)');
        } catch (e, st) {
          debugPrint(
              '[FCM] refreshRegistration after foreground push failed: $e\n$st');
        }
      };
      FirebaseNotificationService.instance.onIncomingCallPush = (data) {
        debugPrint('[FCM] foreground incoming_call push: $data');
      };
      FirebaseNotificationService.instance.onTokenRefreshed = (_) async {
        if (!mounted) return;
        try {
          await accounts.syncCurrentTokenToBackend();
          debugPrint('[FCM] token refresh synced to backend');
        } catch (e, st) {
          debugPrint('[FCM] token sync after refresh failed: $e\n$st');
        }
      };
      FirebaseNotificationService.instance.onCallAccepted = (_) async {
        await calls.acceptFirstRingingIncoming();
      };
      FirebaseNotificationService.instance.onCallRejected = (_) async {
        await calls.rejectAllRingingIncoming();
        await FirebaseNotificationService.instance.cancelCallNotification();
      };
      FirebaseNotificationService.instance.onNotificationTapped = (data) {
        debugPrint('[FCM] notification opened (non-call): $data');
      };
    } catch (e, st) {
      debugPrint('Firebase notifications setup failed (non-fatal): $e\n$st');
    }
  }

  @override
  void dispose() {
    _iosNetworkModel?.removeListener(_onIosNetworkStateChanged);
    _iosNetworkModel = null;
    _listener?.dispose();
    super.dispose();
  }

  // Listen to the app lifecycle 'Inactive' state and send calls state to service (Android only)
  void _onAndroidAppInactive() async {
    debugPrint("_onAppLifecycleInactive");
    await SiprixVoipSdk().syncCallsState(context.read<AppCallsModel>());
  }

  /// Re-register SIP accounts after idle so the next incoming INVITE can be routed (iOS).
  void _onIosAppResume() {
    if (!mounted) return;
    context
        .read<AppAccountsModel>()
        .refreshRegistrationForWake(reason: 'ios_app_resume')
        .then((_) {
      debugPrint('[Lifecycle] SIP registration refreshed on resume (iOS)');
    }).catchError((Object e, StackTrace st) {
      debugPrint('[Lifecycle] refreshRegistration on resume failed: $e\n$st');
    });
  }

  void _onIosNetworkStateChanged() {
    if (!Platform.isIOS || !mounted) return;
    final network = _iosNetworkModel;
    if (network == null) return;
    final bool isNowLost = network.networkLost;
    if (_lastIosNetworkLost && !isNowLost) {
      context
          .read<AppAccountsModel>()
          .refreshRegistrationForWake(reason: 'ios_network_regain')
          .catchError((Object e, StackTrace st) {
        debugPrint('[Lifecycle] refreshRegistration on network regain failed: $e\n$st');
      });
    }
    _lastIosNetworkLost = isNowLost;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      routes: <String, WidgetBuilder>{
        CallAddPage.routeName: (BuildContext context) => const CallAddPage(true),
        SettingsPage.routeName: (BuildContext context) => const SettingsPage(),
        AccountPage.routeName: (BuildContext context) => const AccountPage(),
        SubscrAddPage.routeName: (BuildContext context) => const SubscrAddPage(),
      },
      home: const HomePage(),
      title: 'Siprix VoIP app',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
    );
  }

  static Future<void> _initializeSiprix([LogsModel? logsModel]) async {
    await initializeSiprixApp(logs: logsModel);
  }

  Future<void> _readSavedState() async {
    debugPrint('_readSavedState');
    _wireModelPersistence();
    final prefs = await SharedPreferences.getInstance();
    String accJsonStr = prefs.getString('accounts') ?? '';
    String subsJsonStr = prefs.getString('subscriptions') ?? '';
    String cdrsJsonStr = prefs.getString('cdrs') ?? '';
    String msgsJsonStr = prefs.getString('msgs') ?? '';
    await prefs.reload();
    accJsonStr = prefs.getString('accounts') ?? accJsonStr;
    await _loadModels(accJsonStr, cdrsJsonStr, subsJsonStr, msgsJsonStr);
    await _configureFirebaseNotificationsSafely();
  }

  Future<void> _loadModels(String accJsonStr, String cdrsJsonStr,
      String subsJsonStr, String msgsJsonStr) async {
    AppAccountsModel accs = context.read<AppAccountsModel>();
    SubscriptionsModel subs = context.read<SubscriptionsModel>();
    MessagesModel msgs = context.read<MessagesModel>();
    CdrsModel cdrs = context.read<CdrsModel>();

    //Load messages, than accounts, then other models
    msgs.loadFromJson(msgsJsonStr);
    await accs.loadFromJson(accJsonStr);
    subs.loadFromJson(subsJsonStr);
    cdrs.loadFromJson(cdrsJsonStr);

    //Assign contact name resolver
    context.read<AppCallsModel>().onResolveContactName = _resolveContactName;

    //Load devices
    context.read<DevicesModel>().load();
  }

  void _saveCdrsChanges(String cdrsJsonStr) {
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.setString('cdrs', cdrsJsonStr);
    });
  }

  void _saveAccountChanges(String accountsJsonStr) {
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.setString('accounts', accountsJsonStr);
    });
  }

  void _saveSubscriptionChanges(String subscrJsonStr) {
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.setString('subscriptions', subscrJsonStr);
    });
  }

  void _saveMessagesChanges(String msgsJsonStr) {
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.setString('msgs', msgsJsonStr);
    });
  }

  String _resolveContactName(String phoneNumber) {
    return ""; //TODO add own implementation
    //if(phoneNumber=="100") { return "MyFriend100"; } else
    //if(phoneNumber=="101") { return "MyFriend101"; }
    //else                  { return "";        }
  }
}




/*
//=======================================//
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:siprix_voip_sdk/accounts_model.dart';
import 'package:siprix_voip_sdk/calls_model.dart';
import 'package:siprix_voip_sdk/logs_model.dart';
import 'package:siprix_voip_sdk/siprix_voip_sdk.dart';

void main() async {
  AccountsModel accountsModel = AccountsModel();
  CallsModel callsModel = CallsModel(accountsModel);
  runApp(
    MultiProvider(providers:[
      ChangeNotifierProvider(create: (context) => accountsModel),
      ChangeNotifierProvider(create: (context) => callsModel),
    ],
    child: const MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _initializeSiprix();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Siprix VoIP app',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: Scaffold(body:buildBody())
    );
  }

  Widget buildBody() {
    final accounts = context.watch<AppAccountsModel>();
    final calls = context.watch<AppCallsModel>();
    return Column(children: [
      ListView.separated(
        shrinkWrap: true,
        itemCount: accounts.length,
        separatorBuilder: (BuildContext context, int index) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          AccountModel acc = accounts[index];
          return
            ListTile(title: Text(acc.uri, style: Theme.of(context).textTheme.titleSmall),
                subtitle: Text(acc.regText),
                tileColor: Colors.blue
            );
        },
      ),
      ElevatedButton(onPressed: _addAccount, child: const Icon(Icons.add_card)),
      const Divider(height: 1),
      ListView.separated(
        shrinkWrap: true,
        itemCount: calls.length,
        separatorBuilder: (BuildContext context, int index) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          CallModel call = calls[index];
          return
            ListTile(title: Text(call.nameAndExt, style: Theme.of(context).textTheme.titleSmall),
              subtitle: Text(call.state.name), tileColor: Colors.amber,
              trailing: IconButton(
                onPressed: (){ call.bye(); },
                icon: const Icon(Icons.call_end))
            );
        },
      ),
      ElevatedButton(onPressed: _addCall, child: const Icon(Icons.add_call)),
      const Spacer(),
    ]);
  }

  void _initializeSiprix([LogsModel? logsModel]) async {
    InitData iniData = InitData();
    iniData.license  = "...license-credentials...";
    iniData.logLevelFile = LogLevel.info;
    SiprixVoipSdk().initialize(iniData, logsModel);
  }

  void _addAccount() {
    AccountModel account = AccountModel();
    account.sipServer = "192.168.0.122";
    account.sipExtension = "1016";
    account.sipPassword = "12345";
    account.expireTime = 300;
    context.read<AppAccountsModel>().addAccount(account)
      .catchError(showSnackBar);
  }

  void _addCall() {
    final accounts = context.read<AppAccountsModel>();
    if(accounts.selAccountId==null) return;

    CallDestination dest = CallDestination("1012", accounts.selAccountId!, false);

    context.read<AppCallsModel>().invite(dest)
      .catchError(showSnackBar);
  }

  void showSnackBar(dynamic err) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }
}
*/
