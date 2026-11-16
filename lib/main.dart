import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:adhan/adhan.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final plugin = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await plugin.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  runApp(const RoutineApp());
}

class RoutineApp extends StatelessWidget {
  const RoutineApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'مُنظّم يومي',
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff087f5b))),
    home: const Directionality(textDirection: TextDirection.rtl, child: RoutineHome()));
}

class RoutineTask {
  RoutineTask(this.title, this.hour, this.minute);
  final String title;
  int hour, minute;
  bool done = false;
}

class RoutineHome extends StatefulWidget {
  const RoutineHome({super.key});
  @override
  State<RoutineHome> createState() => _RoutineHomeState();
}

class _RoutineHomeState extends State<RoutineHome> {
  final tasks = <RoutineTask>[
    RoutineTask('الاستيقاظ', 12, 0),
    RoutineTask('الاستعداد للعمل', 12, 30),
    RoutineTask('استراحة الغداء', 15, 0),
    RoutineTask('العودة للعمل', 15, 40),
    RoutineTask('استراحة صلاة المغرب', 18, 0),
    RoutineTask('نهاية الدوام', 3, 0),
    RoutineTask('وقت الهاتف والراحة', 3, 0),
    RoutineTask('النوم', 4, 0),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (var i = 0; i < tasks.length; i++) {
        tasks[i].done = prefs.getBool('done$i') ?? false;
        tasks[i].hour = prefs.getInt('hour$i') ?? tasks[i].hour;
        tasks[i].minute = prefs.getInt('minute$i') ?? tasks[i].minute;
      }
    });
  }

  Future<void> _persist(int i) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('done$i', tasks[i].done);
    await p.setInt('hour$i', tasks[i].hour);
    await p.setInt('minute$i', tasks[i].minute);
  }

  Future<void> _edit(int i) async {
    final picked = await showTimePicker(context: context,
      initialTime: TimeOfDay(hour: tasks[i].hour, minute: tasks[i].minute));
    if (picked == null) return;
    setState(() { tasks[i].hour = picked.hour; tasks[i].minute = picked.minute; });
    await _persist(i);
  }

  Future<void> _notify(int id, String title, int hour, int minute) async {
    final now = DateTime.now();
    var dt = DateTime(now.year, now.month, now.day, hour, minute);
    if (!dt.isAfter(now)) dt = dt.add(const Duration(days: 1));
    await plugin.zonedSchedule(id, title, 'حان الآن موعد $title',
      tz.TZDateTime.from(dt, tz.local),
      const NotificationDetails(android: AndroidNotificationDetails(
        'routine', 'تذكيرات الروتين',
        channelDescription: 'تنبيهات مواعيد الروتين اليومي',
        importance: Importance.max, priority: Priority.high)),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time);
  }

  Future<void> _maghrib() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _toast('اسمح بالوصول للموقع لحساب موعد المغرب'); return;
      }
      final p = await Geolocator.getCurrentPosition();
      final prayer = PrayerTimes.today(Coordinates(p.latitude, p.longitude),
        CalculationMethod.umm_al_qura.getParameters());
      final now = DateTime.now();
      var when = prayer.maghrib;
      if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
      await plugin.zonedSchedule(99, 'موعد صلاة المغرب', 'حان وقت صلاة المغرب',
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(android: AndroidNotificationDetails(
          'maghrib', 'تذكير المغرب',
          channelDescription: 'تنبيه المغرب حسب موقع الجهاز',
          importance: Importance.max, priority: Priority.high)),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
      _toast('تم ضبط تذكير المغرب حسب موقعك');
    } catch (_) { _toast('تعذر تحديد المغرب. تحقق من تفعيل الموقع'); }
  }

  void _toast(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مُنظّم يومي – أبو إلياس'),
      centerTitle: true, backgroundColor: const Color(0xff087f5b),
      foregroundColor: Colors.white),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xff087f5b), Color(0xff12a878)]),
          borderRadius: BorderRadius.circular(20)),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('رتّب يومك بهدوء 🌿', style: TextStyle(color: Colors.white,
            fontSize: 22, fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          Text('تابع مواعيدك وأنجز يومك خطوة بخطوة',
            style: TextStyle(color: Colors.white))
        ])),
      const SizedBox(height: 12),
      Card(child: ListTile(leading: const Icon(Icons.mosque),
        title: const Text('تذكير صلاة المغرب'),
        subtitle: const Text('حسب موقع جهازك'),
        trailing: FilledButton(onPressed: _maghrib, child: const Text('ضبط')))),
      ...List.generate(tasks.length, (i) {
        final t = tasks[i];
        final formatted = TimeOfDay(hour: t.hour, minute: t.minute).format(context);
        return Card(child: ListTile(
          leading: Checkbox(value: t.done, onChanged: (v) async {
            setState(() => t.done = v ?? false); await _persist(i);
          }),
          title: Text(t.title, style: TextStyle(fontWeight: FontWeight.w600,
            decoration: t.done ? TextDecoration.lineThrough : null)),
          subtitle: Text(formatted),
          trailing: Wrap(children: [
            IconButton(icon: const Icon(Icons.notifications_active_outlined),
              onPressed: () async { await _notify(i+1, t.title, t.hour, t.minute); _toast('تم ضبط التنبيه'); }),
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(i))
          ])));
      }),
      const Padding(padding: EdgeInsets.all(12),
        child: Text('يمكنك تعديل وقت كل موعد وضبط تنبيه له من الأزرار بجانبه.',
          textAlign: TextAlign.center))
    ]));
}
