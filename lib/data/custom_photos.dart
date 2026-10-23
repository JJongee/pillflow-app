import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 직접 추가 항목 사진은 서버에 올리지 않고 이 폰에만 저장 (팀 합의 10/22)
/// - 사진 파일: 앱 전용 폴더/custom_photos/
/// - 어떤 항목의 사진인지: shared_preferences 'custom_photo_<내 약 id>' = 파일 경로
const _prefix = 'custom_photo_';

/// 고른 사진을 앱 폴더로 복사해 두고 경로를 돌려줌 (사진 앱 캐시는 지워질 수 있어서)
Future<String?> saveCustomPhoto(int userDrugId, String sourcePath) async {
  try {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/custom_photos');
    await dir.create(recursive: true);
    final ext = sourcePath.contains('.') ? sourcePath.substring(sourcePath.lastIndexOf('.')) : '.jpg';
    final target = '${dir.path}/drug_${userDrugId}_${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(sourcePath).copy(target);
    final p = await SharedPreferences.getInstance();
    final old = p.getString('$_prefix$userDrugId');
    await p.setString('$_prefix$userDrugId', target);
    if (old != null && old != target) await _deleteFile(old);
    return target;
  } catch (_) {
    return null; // 사진 저장에 실패해도 항목 추가는 그대로
  }
}

/// 사진 지우기 (항목을 삭제하거나 사진을 뺄 때)
Future<void> deleteCustomPhoto(int userDrugId) async {
  try {
    final p = await SharedPreferences.getInstance();
    final old = p.getString('$_prefix$userDrugId');
    await p.remove('$_prefix$userDrugId');
    if (old != null) await _deleteFile(old);
  } catch (_) {}
}

Future<void> _deleteFile(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// 내 약 id → 사진 경로 (파일이 남아 있는 것만)
final customPhotosProvider = FutureProvider<Map<int, String>>((ref) async {
  try {
    final p = await SharedPreferences.getInstance();
    final out = <int, String>{};
    for (final k in p.getKeys().where((k) => k.startsWith(_prefix))) {
      final id = int.tryParse(k.substring(_prefix.length));
      final path = p.getString(k);
      if (id != null && path != null && File(path).existsSync()) out[id] = path;
    }
    return out;
  } catch (_) {
    return const {};
  }
});
