import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../db/app_db.dart';

/// מזהה ה-OAuth client מסוג Web בפרויקט Google Cloud של האפליקציה.
/// לא סוד (מופיע בכל APK). נדרש באנדרואיד כ-serverClientId.
const googleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue:
      '494572279154-3pkmvau9hqa3gorvq0jg2kotvojj498o.apps.googleusercontent.com',
);

/// הרשאה מצומצמת: האפליקציה רואה רק קבצים שהיא עצמה יצרה בדרייב.
const driveScope = 'https://www.googleapis.com/auth/drive.file';
const folderName = 'יומן אירועים - נתונים';

class StorageMode {
  static const local = 'local';
  static const drive = 'drive';
}

/// סנכרון דרך הדרייב של חשבון הגוגל (D-11).
///
/// המסד המקומי הוא תמיד מקור העבודה. בדרייב יש תיקייה אחת, ובה קובץ אחד
/// לכל מכשיר (`device-<id>.json`) עם עותק מלא של הנתונים. כל מכשיר כותב רק
/// לקובץ שלו - אין דריסות - וקורא את הקבצים של כולם וממזג לפי updated_at.
/// אחרי התקנה מחדש: מתחברים, והנתונים חוזרים מהקבצים שבדרייב.
class DriveSync {
  DriveSync._();
  static final DriveSync instance = DriveSync._();

  final _db = AppDb.instance;
  final _signIn = GoogleSignIn.instance;
  bool _initialized = false;
  GoogleSignInAccount? _user;

  /// מצב לתצוגה במסכים.
  final status = ValueNotifier<SyncStatus>(const SyncStatus());

  /// נקרא אחרי מיזוג ששינה נתונים מקומיים (טעינה מחדש + תזכורות).
  Future<void> Function()? onRemoteChanges;

  bool _running = false;
  bool _again = false;
  Timer? _debounce;
  Timer? _periodic;

  Future<String> get mode async =>
      await _db.getSetting('storage_mode') ?? StorageMode.local;

  Future<void> _init() async {
    if (_initialized) return;
    await _signIn.initialize(
      serverClientId: googleWebClientId.isEmpty ? null : googleWebClientId,
    );
    _signIn.authenticationEvents.listen((e) {
      if (e is GoogleSignInAuthenticationEventSignIn) {
        _user = e.user;
      } else if (e is GoogleSignInAuthenticationEventSignOut) {
        _user = null;
      }
    }, onError: (_) {});
    _initialized = true;
  }

  /// בפתיחת האפליקציה: אם במצב דרייב - התחברות שקטה וסנכרון.
  Future<void> start() async {
    final account = await _db.getSetting('drive_account');
    final last = int.tryParse(await _db.getSetting('last_sync_at') ?? '');
    status.value = status.value.copyWith(
      account: account,
      lastSync: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
    );
    if (await mode != StorageMode.drive) return;
    try {
      await _init();
      _user ??= await _signIn.attemptLightweightAuthentication();
    } catch (_) {}
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 3), (_) => sync());
    unawaited(sync());
  }

  void stopTimers() {
    _periodic?.cancel();
    _periodic = null;
    _debounce?.cancel();
  }

  /// אחרי כל שינוי מקומי: סנכרון אחרי שקט קצר (כמה שינויים = סנכרון אחד).
  void requestSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () => sync());
  }

  /// התחברות אינטראקטיבית (מכפתור בלבד) + אישור הרשאת דרייב.
  /// מחזיר את כתובת המייל של החשבון.
  Future<String> connect() async {
    if (googleWebClientId.isEmpty) {
      throw const SyncError('החיבור לגוגל עוד לא הוגדר בגרסה הזו');
    }
    await _init();
    final user = await _signIn.authenticate(scopeHint: const [driveScope]);
    _user = user;
    await user.authorizationClient.authorizeScopes(const [driveScope]);
    await _db.setSetting('storage_mode', StorageMode.drive);
    await _db.setSetting('drive_account', user.email);
    status.value = status.value.copyWith(account: user.email, error: null);
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 3), (_) => sync());
    return user.email;
  }

  /// מעבר ל"רק בטלפון": מפסיקים לסנכרן. הקבצים בדרייב נשארים.
  Future<void> disconnect() async {
    stopTimers();
    try {
      await _init();
      await _signIn.signOut();
    } catch (_) {}
    _user = null;
    await _db.setSetting('storage_mode', StorageMode.local);
    await _db.setSetting('drive_account', null);
    await _db.setSetting('drive_folder_id', null);
    await _db.setSetting('drive_file_id', null);
    status.value = const SyncStatus();
  }

  Future<String?> _token() async {
    await _init();
    _user ??= await _signIn.attemptLightweightAuthentication();
    final user = _user;
    if (user == null) return null;
    final auth = await user.authorizationClient.authorizationForScopes(const [
      driveScope,
    ]);
    return auth?.accessToken;
  }

  /// סנכרון מלא: הורדה ומיזוג של קבצי כל המכשירים, והעלאת הקובץ שלנו.
  /// מחזיר כמה שורות השתנו מקומית (או -1 אם לא רץ).
  Future<int> sync() async {
    if (await mode != StorageMode.drive) return -1;
    if (_running) {
      _again = true;
      return -1;
    }
    _running = true;
    status.value = status.value.copyWith(syncing: true, error: null);
    var changed = 0;
    try {
      final token = await _token();
      if (token == null) {
        throw const SyncError('צריך להתחבר מחדש לגוגל (הגדרות > סנכרון)');
      }
      final api = _DriveApi(token);
      final folderId = await _folder(api);
      final deviceId = await _db.deviceId;
      final myName = 'device-$deviceId.json';
      String? myFileId;
      for (final f in await api.listJson(folderId)) {
        if (f.name == myName) {
          myFileId = f.id;
          continue;
        }
        final snap = await api.download(f.id);
        if (snap != null) changed += await _db.merge(snap);
      }
      final body = jsonEncode(await _db.snapshot());
      if (myFileId == null) {
        await api.create(folderId, myName, body);
      } else {
        await api.update(myFileId, body);
      }
      final now = DateTime.now();
      await _db.setSetting('last_sync_at', '${now.millisecondsSinceEpoch}');
      status.value = status.value.copyWith(
        syncing: false,
        lastSync: now,
        error: null,
      );
      if (changed > 0) await onRemoteChanges?.call();
    } on SyncError catch (e) {
      status.value = status.value.copyWith(syncing: false, error: e.message);
    } catch (e) {
      status.value = status.value.copyWith(
        syncing: false,
        error: 'הסנכרון נכשל: ${_short(e)}',
      );
    } finally {
      _running = false;
    }
    if (_again) {
      _again = false;
      unawaited(sync());
    }
    return changed;
  }

  /// תיקיית הנתונים: חיפוש בכל סנכרון (אם שני מכשירים יצרו תיקייה באותו
  /// רגע, כולם מתכנסים לוותיקה), ואם אין - יצירה.
  Future<String> _folder(_DriveApi api) async {
    final found = await api.findFolder(folderName);
    final id = found ?? await api.createFolder(folderName);
    await _db.setSetting('drive_folder_id', id);
    return id;
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}

class SyncError implements Exception {
  final String message;
  const SyncError(this.message);
  @override
  String toString() => message;
}

class SyncStatus {
  final bool syncing;
  final DateTime? lastSync;
  final String? error;
  final String? account;
  const SyncStatus({
    this.syncing = false,
    this.lastSync,
    this.error,
    this.account,
  });

  SyncStatus copyWith({
    bool? syncing,
    DateTime? lastSync,
    Object? error = _keep,
    Object? account = _keep,
  }) => SyncStatus(
    syncing: syncing ?? this.syncing,
    lastSync: lastSync ?? this.lastSync,
    error: identical(error, _keep) ? this.error : error as String?,
    account: identical(account, _keep) ? this.account : account as String?,
  );

  static const _keep = Object();
}

class _DriveFile {
  final String id;
  final String name;
  _DriveFile(this.id, this.name);
}

/// Drive REST v3 מינימלי (בלי חבילת googleapis).
class _DriveApi {
  final String token;
  _DriveApi(this.token);

  static const _base = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';
  static const _folderMime = 'application/vnd.google-apps.folder';

  Map<String, String> get _h => {'Authorization': 'Bearer $token'};

  void _check(http.Response r, String what) {
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw const SyncError('אין הרשאה לדרייב - צריך להתחבר מחדש');
    }
    if (r.statusCode >= 300) {
      throw SyncError('$what: HTTP ${r.statusCode}');
    }
  }

  String _q(String s) => s.replaceAll("\\", "\\\\").replaceAll("'", "\\'");

  Future<String?> findFolder(String name) async {
    final q =
        "name = '${_q(name)}' and mimeType = '$_folderMime' and trashed = false";
    final r = await http.get(
      Uri.parse(_base).replace(
        queryParameters: {
          'q': q,
          'spaces': 'drive',
          'orderBy': 'createdTime',
          'fields': 'files(id,name)',
        },
      ),
      headers: _h,
    );
    _check(r, 'חיפוש תיקייה');
    final files = (jsonDecode(r.body)['files'] as List?) ?? [];
    return files.isEmpty ? null : files.first['id'] as String;
  }

  Future<String> createFolder(String name) async {
    final r = await http.post(
      Uri.parse('$_base?fields=id'),
      headers: {..._h, 'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'mimeType': _folderMime}),
    );
    _check(r, 'יצירת תיקייה');
    return jsonDecode(r.body)['id'] as String;
  }

  Future<List<_DriveFile>> listJson(String folderId) async {
    final out = <_DriveFile>[];
    String? page;
    do {
      final r = await http.get(
        Uri.parse(_base).replace(
          queryParameters: {
            'q': "'$folderId' in parents and trashed = false",
            'fields': 'nextPageToken,files(id,name)',
            'pageSize': '100',
            if (page != null) 'pageToken': page,
          },
        ),
        headers: _h,
      );
      _check(r, 'רשימת קבצים');
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      for (final f in (j['files'] as List? ?? [])) {
        final name = f['name'] as String;
        if (name.startsWith('device-') && name.endsWith('.json')) {
          out.add(_DriveFile(f['id'] as String, name));
        }
      }
      page = j['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  Future<Map<String, dynamic>?> download(String id) async {
    final r = await http.get(Uri.parse('$_base/$id?alt=media'), headers: _h);
    _check(r, 'הורדה');
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null; // קובץ פגום של מכשיר אחר לא עוצר את הסנכרון
    }
  }

  Future<void> create(String folderId, String name, String json) async {
    const boundary = 'eventlog-boundary-7f3a';
    final meta = jsonEncode({
      'name': name,
      'parents': [folderId],
      'mimeType': 'application/json',
    });
    final body =
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$meta\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$json\r\n'
        '--$boundary--';
    final r = await http.post(
      Uri.parse('$_upload?uploadType=multipart&fields=id'),
      headers: {..._h, 'Content-Type': 'multipart/related; boundary=$boundary'},
      body: utf8.encode(body),
    );
    _check(r, 'העלאה');
  }

  Future<void> update(String id, String json) async {
    final r = await http.patch(
      Uri.parse('$_upload/$id?uploadType=media&fields=id'),
      headers: {..._h, 'Content-Type': 'application/json; charset=UTF-8'},
      body: utf8.encode(json),
    );
    _check(r, 'עדכון');
  }
}
