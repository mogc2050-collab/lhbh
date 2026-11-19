import 'package:flutter/material.dart';

import 'device_media.dart';

Future<void> showPermissionPanel(BuildContext context, PhoneLibrary phone) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .76,
        child: _PermissionPanel(phone: phone),
      ),
    );

class _PermissionPanel extends StatelessWidget {
  const _PermissionPanel({required this.phone});
  final PhoneLibrary phone;

  Future<void> run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح إعدادات الأذونات على هذا الجهاز.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: AnimatedBuilder(
      animation: phone,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        children: [
          Text(
            'الأذونات والإشعارات',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'اختار اللي تحتاجه. تقدر تستورد ملفات يدويًا من غير إتاحة مكتبة الهاتف كلها.',
          ),
          const SizedBox(height: 12),
          for (final item in [
            ('audio', 'الموسيقى والصوت', Icons.music_note_rounded),
            ('video', 'الفيديو', Icons.movie_outlined),
            ('image', 'الصور', Icons.photo_library_outlined),
            ('notifications', 'إشعارات التشغيل', Icons.notifications_outlined),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(item.$3),
              title: Text(item.$2),
              subtitle: Text(
                item.$1 == 'notifications'
                    ? (phone.notificationsGranted ? 'مفعّلة' : 'غير مفعّلة')
                    : phone.permissions[item.$1] == true
                    ? phone.permissions['${item.$1}Limited'] == true
                          ? 'الوصول للعناصر اللي اخترتها فقط'
                          : 'الوصول مفعّل'
                    : 'غير مسموح حاليًا',
              ),
              trailing: TextButton(
                onPressed: phone.loading
                    ? null
                    : () => run(context, () async {
                        if (item.$1 == 'notifications') {
                          if (phone.notificationsGranted) {
                            await phone.openNotificationSettings();
                          } else {
                            await phone.requestNotifications();
                            if (!phone.notificationsGranted &&
                                context.mounted) {
                              await phone.openNotificationSettings();
                            }
                          }
                        } else {
                          if (phone.permissions[item.$1] == true &&
                              phone.permissions['${item.$1}Limited'] != true) {
                            await phone.openAppSettings();
                            return;
                          }
                          await phone.refresh(
                            askPermissions: true,
                            permissionKinds: [item.$1],
                          );
                        }
                      }),
                child: Text(
                  item.$1 == 'notifications' && phone.notificationsGranted
                      ? 'الإعدادات'
                      : phone.permissions[item.$1] == true
                      ? 'إدارة'
                      : 'السماح',
                ),
              ),
            ),
          if (phone.loading) const LinearProgressIndicator(),
          if (phone.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(phone.error!),
            ),
          const Divider(height: 28),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('إعدادات التطبيق في أندرويد'),
            subtitle: const Text('تعديل الوصول أو إعادة تفعيل إذن مرفوض'),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: () => run(context, phone.openAppSettings),
          ),
        ],
      ),
    ),
  );
}
