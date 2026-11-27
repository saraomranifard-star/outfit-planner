import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tz.initializeTimeZones();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await notificationsPlugin.initialize(initSettings);

  final androidImpl = notificationsPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.requestNotificationsPermission();
  await androidImpl?.requestExactAlarmsPermission();

  runApp(const OutfitPlannerApp());
}

// ==================== MODELS ====================

class ClothingItem {
  final String id;
  final String name;
  final String imagePath;
  final List<String> tags;

  ClothingItem({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.tags,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imagePath': imagePath,
        'tags': tags,
      };

  factory ClothingItem.fromJson(Map<String, dynamic> json) => ClothingItem(
        id: json['id'],
        name: json['name'],
        imagePath: json['imagePath'],
        tags: List<String>.from(json['tags']),
      );
}

class DayPlan {
  final String dateKey;
  final List<String> itemIds;
  final int hour;
  final int minute;

  DayPlan({
    required this.dateKey,
    required this.itemIds,
    required this.hour,
    required this.minute,
  });

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'itemIds': itemIds,
        'hour': hour,
        'minute': minute,
      };

  factory DayPlan.fromJson(Map<String, dynamic> json) => DayPlan(
        dateKey: json['dateKey'],
        itemIds: List<String>.from(json['itemIds']),
        hour: json['hour'] ?? 8,
        minute: json['minute'] ?? 30,
      );
}

// ==================== THEME & GLASS WIDGET ====================

class AppColors {
  static const bg = Color(0xFF08080A);
  static const surface = Color(0xFF141418);
  static const crimson = Color(0xFFFF3B5C);
  static const crimsonDark = Color(0xFFE11D48);
  static const textPrimary = Color(0xFFF5F5F7);
  static const textSecondary = Color(0xFF98989F);
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final bool highlightCrimson;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 20,
    this.highlightCrimson = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding ?? const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.08),
                Colors.white.withOpacity(0.03),
              ],
            ),
            border: Border.all(
              color: highlightCrimson
                  ? AppColors.crimson.withOpacity(0.65)
                  : Colors.white.withOpacity(0.11),
              width: highlightCrimson ? 1.4 : 1.0,
            ),
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }
}

// ==================== MAIN APP ====================

class OutfitPlannerApp extends StatelessWidget {
  const OutfitPlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Outfit Planner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.crimson,
          surface: AppColors.surface,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  List<ClothingItem> _items = [];
  Map<String, DayPlan> _plans = {};
  String _selectedTag = 'All';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final itemsStr = prefs.getString('wardrobe_items');
    final plansStr = prefs.getString('outfit_plans');

    setState(() {
      if (itemsStr != null) {
        final List decoded = jsonDecode(itemsStr);
        _items = decoded.map((e) => ClothingItem.fromJson(e)).toList();
      }
      if (plansStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(plansStr);
        _plans = decoded.map((k, v) => MapEntry(k, DayPlan.fromJson(v)));
      }
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'wardrobe_items', jsonEncode(_items.map((e) => e.toJson()).toList()));
    await prefs.setString('outfit_plans',
        jsonEncode(_plans.map((k, v) => MapEntry(k, v.toJson()))));
  }

  Future<void> _addItem(ClothingItem item) async {
    setState(() => _items.insert(0, item));
    await _saveData();
  }

  Future<void> _deleteItem(String id) async {
    setState(() {
      _items.removeWhere((e) => e.id == id);
      _plans.updateAll((key, plan) => DayPlan(
            dateKey: plan.dateKey,
            itemIds: plan.itemIds.where((itemId) => itemId != id).toList(),
            hour: plan.hour,
            minute: plan.minute,
          ));
    });
    await _saveData();
  }

  Future<void> _savePlanAndScheduleReminder(DayPlan plan) async {
    setState(() {
      if (plan.itemIds.isEmpty) {
        _plans.remove(plan.dateKey);
      } else {
        _plans[plan.dateKey] = plan;
      }
    });
    await _saveData();

    final notifId = plan.dateKey.hashCode;
    await notificationsPlugin.cancel(notifId);

    if (plan.itemIds.isEmpty) return;

    final parts = plan.dateKey.split('-').map(int.parse).toList();
    final scheduledDate = tz.TZDateTime(
      tz.local,
      parts[0],
      parts[1],
      parts[2],
      plan.hour,
      plan.minute,
    );

    final outfitNames = plan.itemIds
        .map((id) => _items
            .firstWhere((item) => item.id == id,
                orElse: () =>
                    ClothingItem(id: '', name: 'Item', imagePath: '', tags: []))
            .name)
        .join(', ');

    if (scheduledDate.isAfter(tz.TZDateTime.now(tz.local))) {
      await notificationsPlugin.zonedSchedule(
        notifId,
        'Today\'s Outfit Reminder',
        'Planned look: $outfitNames',
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'outfit_reminders_channel',
            'Outfit Reminders',
            channelDescription: 'Daily reminders for your planned outfits',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  Future<void> _triggerInstantTestNotification() async {
    await notificationsPlugin.show(
      9999,
      'Outfit Planner Reminder',
      'Time to get ready! Tap to view your planned outfit.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'outfit_reminders_channel',
          'Outfit Reminders',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.crimsonDark.withOpacity(0.14),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: -90,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _tabIndex == 0
                      ? _buildWardrobeTab()
                      : CalendarTab(
                          items: _items,
                          plans: _plans,
                          onSavePlan: _savePlanAndScheduleReminder,
                          onTestNotification: _triggerInstantTestNotification,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _openAddPieceSheet,
              backgroundColor: AppColors.crimsonDark,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_a_photo_rounded, size: 20),
              label: const Text('Add Piece',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            )
          : null,
      bottomNavigationBar: _buildGlassNavBar(),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.crimson,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'OUTFIT PLANNER',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2.0,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _tabIndex == 0 ? 'My Wardrobe' : 'Style Calendar',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            borderRadius: 14,
            child: Text(
              '${_items.length} Pieces',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWardrobeTab() {
    final allTags = <String>{'All'};
    for (final item in _items) {
      allTags.addAll(item.tags);
    }

    final filteredItems = _items.where((item) {
      final matchesTag =
          _selectedTag == 'All' || item.tags.contains(_selectedTag);
      final matchesSearch = _searchQuery.isEmpty ||
          item.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.tags.any(
              (t) => t.toLowerCase().contains(_searchQuery.toLowerCase()));
      return matchesTag && matchesSearch;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            borderRadius: 16,
            child: TextField(
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                icon: Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                hintText: 'Search jacket, shoes, black...',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                border: InputBorder.none,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: allTags.map((tag) {
              final active = tag == _selectedTag;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(tag),
                  selected: active,
                  onSelected: (_) => setState(() => _selectedTag = tag),
                  backgroundColor: Colors.white.withOpacity(0.06),
                  selectedColor: AppColors.crimsonDark,
                  labelStyle: TextStyle(
                    color: active ? Colors.white : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide(
                    color: active
                        ? AppColors.crimson
                        : Colors.white.withOpacity(0.1),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: filteredItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.checkroom_outlined,
                          size: 56, color: Colors.white.withOpacity(0.2)),
                      const SizedBox(height: 12),
                      const Text(
                        'Your wardrobe is empty',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap "Add Piece" to snap or upload clothes',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 90),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.76,
                  ),
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return GlassCard(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.file(
                                    File(item.imagePath),
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.white.withOpacity(0.05),
                                      child: const Center(
                                        child: Icon(Icons.image_not_supported,
                                            color: AppColors.textSecondary),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: GestureDetector(
                                    onTap: () => _deleteItem(item.id),
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.65),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close,
                                          size: 14, color: Colors.white70),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            children: item.tags
                                .take(2)
                                .map((tag) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            AppColors.crimson.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        tag,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.crimson,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _openAddPieceSheet() {
    final nameController = TextEditingController();
    final tagsController = TextEditingController();
    String? savedImagePath;
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121216),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> pickImage(ImageSource source) async {
            final XFile? picked =
                await picker.pickImage(source: source, imageQuality: 85);
            if (picked == null) return;

            final dir = await getApplicationDocumentsDirectory();
            final fileName =
                'garment_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final savedFile =
                await File(picked.path).copy('${dir.path}/$fileName');

            setModalState(() => savedImagePath = savedFile.path);
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add New Garment',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined,
                            color: AppColors.crimson),
                        label: const Text('Camera',
                            style: TextStyle(color: AppColors.textPrimary)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                              color: Colors.white.withOpacity(0.15)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined,
                            color: AppColors.crimson),
                        label: const Text('Gallery',
                            style: TextStyle(color: AppColors.textPrimary)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                              color: Colors.white.withOpacity(0.15)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
                if (savedImagePath != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(File(savedImagePath!),
                        height: 130, width: double.infinity, fit: BoxFit.cover),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Item Name (e.g. Black Leather Jacket)',
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tagsController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Tags (comma separated: Jacket, Winter, Black)',
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (savedImagePath == null ||
                          nameController.text.trim().isEmpty) {
                        return;
                      }
                      final tags = tagsController.text
                          .split(',')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList();

                      _addItem(ClothingItem(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: nameController.text.trim(),
                        imagePath: savedImagePath!,
                        tags: tags.isEmpty ? ['General'] : tags,
                      ));
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.crimsonDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Save to Wardrobe',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGlassNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E12),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (idx) => setState(() => _tabIndex = idx),
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: AppColors.crimson,
        unselectedItemColor: AppColors.textSecondary,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.checkroom_rounded),
            label: 'Wardrobe',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_rounded),
            label: 'Calendar',
          ),
        ],
      ),
    );
  }
}

// ==================== CALENDAR TAB ====================

class CalendarTab extends StatefulWidget {
  final List<ClothingItem> items;
  final Map<String, DayPlan> plans;
  final Future<void> Function(DayPlan) onSavePlan;
  final Future<void> Function() onTestNotification;

  const CalendarTab({
    super.key,
    required this.items,
    required this.plans,
    required this.onSavePlan,
    required this.onTestNotification,
  });

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDate = DateTime.now();

  String _formatDateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final dateKey = _formatDateKey(_selectedDate);
    final currentPlan = widget.plans[dateKey];
    final plannedItems = widget.items
        .where((item) => currentPlan?.itemIds.contains(item.id) ?? false)
        .toList();

    final firstDayOfMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final startWeekday = firstDayOfMonth.weekday % 7;

    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: Colors.white),
                      onPressed: () => setState(() {
                        _focusedMonth = DateTime(
                            _focusedMonth.year, _focusedMonth.month - 1);
                      }),
                    ),
                    Text(
                      '${months[_focusedMonth.month - 1]} ${_focusedMonth.year}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.chevron_right, color: Colors.white),
                      onPressed: () => setState(() {
                        _focusedMonth = DateTime(
                            _focusedMonth.year, _focusedMonth.month + 1);
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: startWeekday + daysInMonth,
                  itemBuilder: (context, idx) {
                    if (idx < startWeekday) return const SizedBox.shrink();
                    final day = idx - startWeekday + 1;
                    final cellDate = DateTime(
                        _focusedMonth.year, _focusedMonth.month, day);
                    final cellKey = _formatDateKey(cellDate);
                    final isSelected = cellKey == dateKey;
                    final hasOutfit = widget.plans.containsKey(cellKey);

                    return GestureDetector(
                      onTap: () => setState(() => _selectedDate = cellDate),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.crimsonDark
                              : Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.crimson
                                : Colors.white.withOpacity(0.06),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            if (hasOutfit)
                              Container(
                                margin: const EdgeInsets.only(top: 3),
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.crimson,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            highlightCrimson: plannedItems.isNotEmpty,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Look for $dateKey',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          _openSelectOutfitSheet(dateKey, currentPlan),
                      icon: const Icon(Icons.add,
                          size: 18, color: AppColors.crimson),
                      label: const Text('Edit Outfit',
                          style: TextStyle(color: AppColors.crimson)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (plannedItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No clothes planned for this date yet.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  )
                else ...[
                  SizedBox(
                    height: 86,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: plannedItems.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(plannedItems[i].imagePath),
                          width: 74,
                          height: 86,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.notifications_active_outlined,
                              size: 18, color: AppColors.crimson),
                          const SizedBox(width: 8),
                          Text(
                            'Reminder: ${(currentPlan?.hour ?? 8).toString().padLeft(2, '0')}:${(currentPlan?.minute ?? 30).toString().padLeft(2, '0')}',
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () async {
                          final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(
                              hour: currentPlan?.hour ?? 8,
                              minute: currentPlan?.minute ?? 30,
                            ),
                          );
                          if (pickedTime != null && currentPlan != null) {
                            await widget.onSavePlan(DayPlan(
                              dateKey: dateKey,
                              itemIds: currentPlan.itemIds,
                              hour: pickedTime.hour,
                              minute: pickedTime.minute,
                            ));
                          }
                        },
                        child: const Text('Change Time',
                            style: TextStyle(color: AppColors.crimson)),
                      ),
                    ],
                  ),
                ],
                const Divider(color: Colors.white12, height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onTestNotification,
                    icon: const Icon(Icons.notifications_ring_volume_outlined,
                        size: 18, color: AppColors.textPrimary),
                    label: const Text('Test Reminder Notification Now',
                        style: TextStyle(color: AppColors.textPrimary)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withOpacity(0.15)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openSelectOutfitSheet(String dateKey, DayPlan? existingPlan) {
    final selectedIds = Set<String>.from(existingPlan?.itemIds ?? []);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121216),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Pieces for $dateKey',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 14),
              if (widget.items.isEmpty)
                const Text('Add items to your Wardrobe first!',
                    style: TextStyle(color: AppColors.textSecondary))
              else
                SizedBox(
                  height: 220,
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: widget.items.length,
                    itemBuilder: (_, idx) {
                      final item = widget.items[idx];
                      final isChosen = selectedIds.contains(item.id);
                      return GestureDetector(
                        onTap: () {
                          setModalState(() {
                            if (isChosen) {
                              selectedIds.remove(item.id);
                            } else {
                              selectedIds.add(item.id);
                            }
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isChosen
                                  ? AppColors.crimson
                                  : Colors.white12,
                              width: isChosen ? 2.2 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(File(item.imagePath),
                                fit: BoxFit.cover),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await widget.onSavePlan(DayPlan(
                      dateKey: dateKey,
                      itemIds: selectedIds.toList(),
                      hour: existingPlan?.hour ?? 8,
                      minute: existingPlan?.minute ?? 30,
                    ));
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.crimsonDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Save & Schedule Reminder',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
