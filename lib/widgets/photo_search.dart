import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import '../data/repository.dart';
import 'state_views.dart';

/// 사진으로 약 찾기 (OCR) — 약 상자·봉투 사진에서 글자를 읽어 약 이름 후보를 찾음
/// 사진과 글자 인식은 모두 폰 안에서 처리 (서버로 사진을 보내지 않음)
/// 사진에서 읽은 한 줄: 글자 + 사진 속 위치(픽셀)
class ScannedLine {
  final String text;
  final Rect box;
  const ScannedLine(this.text, this.box);
}

abstract class TextScanner {
  /// 사진 속 글자를 줄 단위로 (글자가 큰 줄부터)
  Future<List<ScannedLine>> scan(String imagePath);
}

class MlKitScanner implements TextScanner {
  @override
  Future<List<ScannedLine>> scan(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return sortBySize([
        for (final b in result.blocks)
          for (final l in b.lines) ScannedLine(l.text, l.boundingBox),
      ], (l) => l.box.height);
    } finally {
      await recognizer.close();
    }
  }
}

/// 글자가 큰 줄부터 (약 상자는 제품 이름이 가장 크게 인쇄돼서 맨 위 후보가 됨)
/// 크기가 비슷하면(10% 이내) 사진 속 원래 순서 유지 → 처방전 봉투는 지금처럼 위→아래
List<T> sortBySize<T>(List<T> items, double Function(T) height) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i], height(items[i]))];
  indexed.sort((a, b) {
    final bigger = a.$3 > b.$3 ? a.$3 : b.$3;
    if (bigger > 0 && (a.$3 - b.$3).abs() / bigger <= 0.1) return a.$1.compareTo(b.$1);
    return b.$3.compareTo(a.$3);
  });
  return [for (final e in indexed) e.$2];
}

/// (글자, 높이) 목록을 큰 글자부터 — 테스트·설명용
List<String> bySize(List<(String, double)> lines) => [for (final l in sortBySize(lines, (l) => l.$2)) l.$1];

final textScannerProvider = Provider<TextScanner>((ref) => MlKitScanner());

/// 약 이름이 아닌 게 분명한 줄 (봉투·처방전에 흔한 말)
const _noise = [
  '병원', '의원', '약국', '처방', '조제', '복용', '복약', '식후', '식전', '취침', '하루', '1일', '회분',
  '환자', '성명', '주소', '전화', '보험', '본인부담', '금액', '영수', '발행', '교부', '유효기간', '사용기한',
  '제조', '번호', '보관', '주의', '효능', '효과', '용법', '용량', '성분', '함량', '첨가제', '설명서',
];

/// 읽은 글자 줄 → 검색해 볼 후보
///  · '(' 뒤는 성분 설명이라 버림 ("타이레놀정500밀리그람(아세트아미노펜)" → "타이레놀정500밀리그람")
///  · 띄어쓰기·기호를 빼고, 한글이 2글자 이상 있는 줄만
///  · 봉투·처방전에 흔한 말이 들어간 줄과 날짜·전화번호, 함량·개수만 있는 줄은 뺌
List<String> candidateQueries(List<String> lines, {int limit = 10}) {
  final out = <String>[];
  for (final raw in lines) {
    final s = cleanLine(raw);
    if (s == null) continue;
    if (!out.contains(s)) out.add(s);
    if (out.length >= limit) break;
  }
  return out;
}

/// 한 줄 정리 → 검색해 볼 말 (후보가 아니면 null)
String? cleanLine(String raw) {
  var s = raw.split(RegExp(r'[(\[（]')).first;
  s = s.replaceAll(RegExp(r'[^0-9A-Za-z가-힣]'), '');
  if (RegExp(r'[가-힣]').allMatches(s).length < 2) return null;
  // 함량·개수만 있는 줄("500 밀리그람", "10정")은 약 이름이 아님 → 다른 약의 500mg이 걸리는 걸 막음
  final core = s
      .replaceAll(RegExp(r'\d+'), '')
      .replaceAll(RegExp(r'밀리그람|밀리그램|마이크로그램|그램|밀리리터|리터|mg|ml|mL|정|캡슐|포|병|매|알'), '');
  if (RegExp(r'[가-힣]').allMatches(core).length < 2) return null;
  if (_noise.any(s.contains)) return null;
  if (RegExp(r'^\d').hasMatch(s) && RegExp(r'\d{4}').hasMatch(s)) return null; // 날짜·번호로 시작
  return s.length > 30 ? s.substring(0, 30) : s;
}

/// 후보 하나
class PhotoCandidate {
  final String query; // 실제로 검색한 말
  final String read; // 사진에서 읽은 줄
  final String firstName; // 읽은 글자와 가장 비슷한 약 이름
  final int total;
  const PhotoCandidate(this.query, this.firstName, this.total, {String? read}) : read = read ?? query;

  /// 사진 글자 그대로 검색됐는지 (아니면 글자 일부로 찾은 '비슷한 이름')
  bool get exact => query == read;

  /// 눌렀을 때 검색할 말: 대표 이름에서 괄호 앞부분
  String get searchName {
    final n = firstName.split(RegExp(r'[(\[（]')).first.trim();
    return n.isEmpty ? query : n;
  }
}

/// 글자 인식이 한두 글자 틀린 경우("타o레놀", "아세트아마노펜")를 위해 조금씩 줄여 가며 검색
///  1) 읽은 그대로  2) 가장 긴 한글 덩어리를 뒤에서부터 한 글자씩 줄임(3글자까지)  3) 나머지 한글 덩어리(2글자 이상)
List<String> searchAttempts(String q, {int max = 6}) {
  final runs = RegExp(r'[가-힣]+').allMatches(q).map((m) => m.group(0)!).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final out = <String>[q];
  if (runs.isNotEmpty) {
    final longest = runs.first;
    for (var n = longest.length - 1; n >= 3; n--) {
      out.add(longest.substring(0, n));
    }
    for (final r in runs) {
      if (r.length >= 2) out.add(r);
    }
  }
  final seen = <String>{};
  return [for (final a in out) if (seen.add(a)) a].take(max).toList();
}

/// 읽은 글자와 가장 비슷한 이름 (같은 순서로 겹치는 글자 수 = 최장 공통 부분열)
/// hints: 같은 사진에서 읽은 다른 줄들 ("500 밀리그람", "10정" 등) — 함량이 맞는 제품을 대표로 고르는 데 씀
String bestMatch(String read, List<String> names, {List<String> hints = const []}) {
  String key(String s) => s.split(RegExp(r'[(\[（]')).first.replaceAll(RegExp(r'[^0-9가-힣]'), '');
  int lcs(String a, String b) {
    final dp = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        dp[i][j] = a[i - 1] == b[j - 1] ? dp[i - 1][j - 1] + 1 : (dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1]);
      }
    }
    return dp[a.length][b.length];
  }

  final r = key(read);
  // 같은 사진의 다른 줄에서 나온 함량·숫자 (예: "500밀리그람", "500")
  final hintKeys = {
    for (final h in hints)
      if (key(h).length >= 3 && key(h) != r) key(h),
  };
  final hintNums = {for (final h in hints) ...RegExp(r'\d{2,}').allMatches(h).map((m) => m.group(0)!)};
  var best = names.first;
  var bestScore = double.negativeInfinity;
  for (final n in names) {
    final k = key(n);
    if (k.isEmpty) continue;
    // 1) 읽은 글자를 얼마나 담고 있는지  2) 첫 글자가 같은지(앞에 다른 말이 붙은 '우먼스타이레놀'보다 '타이레놀' 우선)
    // 3) 그래도 같으면 길이가 읽은 글자와 비슷한 이름
    final cover = r.isEmpty ? 0.0 : lcs(r, k) / r.length;
    final sameStart = r.isNotEmpty && k[0] == r[0] ? 1.0 : 0.0;
    // 4) 사진의 다른 줄과 맞는 함량·숫자가 이름에 있으면 가산 ('타이레놀콜드'보다 '타이레놀정500밀리그람')
    final hintHit = hintKeys.where(k.contains).length * 2 + hintNums.where(k.contains).length;
    final score = cover * 10 + sameStart * 3 + hintHit - (k.length - r.length).abs() * 0.01;
    if (score > bestScore) {
      bestScore = score;
      best = n;
    }
  }
  return best;
}

/// 한 줄로 후보 찾기 (못 찾으면 null)
Future<PhotoCandidate?> findForLine(PillRepository repo, String q, {List<String> hints = const []}) async {
  for (final attempt in searchAttempts(q)) {
    try {
      final r = await repo.searchDrugs(attempt, page: 1, size: 20); // 대표 이름을 고를 수 있게 넉넉히
      if (r.total > 0) {
        return PhotoCandidate(attempt, bestMatch(q, [for (final d in r.items) d.itemName], hints: hints), r.total, read: q);
      }
    } catch (_) {}
  }
  return null;
}

/// 📷 → (카메라 / 앨범) → 글자 읽기 → 실제로 검색되는 후보만 보여 주기 → 고른 검색어 돌려줌
Future<String?> showPhotoSearch(BuildContext context, WidgetRef ref) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('사진으로 약 찾기', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('약 상자나 봉투의 약 이름이 잘 보이게 찍어 주세요. 사진은 휴대폰 안에서만 쓰고 저장하거나 보내지 않아요.',
              style: TextStyle(fontSize: 14, color: Toss.grey600)),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, size: 28),
            title: const Text('사진 찍기', style: TextStyle(fontSize: 17)),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, size: 28),
            title: const Text('앨범에서 고르기', style: TextStyle(fontSize: 17)),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    ),
  );
  if (source == null || !context.mounted) return null;

  final XFile? image;
  try {
    image = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 90);
  } catch (_) {
    if (context.mounted) showSnack(context, '카메라나 앨범을 열 수 없어요. 권한을 확인하거나 직접 입력해 주세요.');
    return null;
  }
  if (image == null || !context.mounted) return null;
  final imagePath = image.path; // 아래 창(클로저)에서도 쓰게 미리 꺼내 둠

  // 읽는 동안 기다림 표시
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        CircularProgressIndicator(),
        SizedBox(width: 20),
        Expanded(child: Text('사진에서 약 이름을 찾는 중이에요', style: TextStyle(fontSize: 16))),
      ]),
    ),
  );

  List<PhotoCandidate> found = [];
  List<ScannedLine> scanned = []; // 사진에서 읽은 글자 (확인용)
  Size? imageSize;
  String? error;
  try {
    // 사진 크기 (읽은 글자 위치를 사진 위에 표시할 때 씀)
    try {
      final img = await decodeImageFromList(await image.readAsBytes());
      imageSize = Size(img.width.toDouble(), img.height.toDouble());
    } catch (_) {}
    scanned = await ref.read(textScannerProvider).scan(imagePath);
    final lines = [for (final l in scanned) l.text];
    final queries = candidateQueries(lines);
    final repo = ref.read(repositoryProvider);
    final results = await Future.wait(queries.map((q) => findForLine(repo, q, hints: lines)));
    // 여러 줄이 같은 약으로 이어지면 한 번만
    final names = <String>{};
    found = [
      for (final c in results.whereType<PhotoCandidate>())
        if (names.add(c.firstName)) c,
    ];
  } catch (_) {
    error = '사진에서 글자를 읽지 못했어요.';
  }
  navigator.pop(); // 기다림 표시 닫기
  if (!context.mounted) return null;

  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _CandidateSheet(
      found: found,
      scanned: scanned,
      imagePath: imagePath,
      imageSize: imageSize,
      error: error,
    ),
  );
}

/// 후보마다 다른 색 (빨강은 금기 경고 전용이라 쓰지 않음)
const _markColors = [Toss.blue, Color(0xFF0E9F6E), Color(0xFFB45309), Color(0xFF7C3AED), Color(0xFF0891B2)];
Color markColor(int i) => _markColors[i % _markColors.length];

class _CandidateSheet extends StatelessWidget {
  const _CandidateSheet({
    required this.found,
    required this.scanned,
    required this.imagePath,
    this.imageSize,
    this.error,
  });
  final List<PhotoCandidate> found;
  final List<ScannedLine> scanned;
  final String imagePath;
  final Size? imageSize;
  final String? error;

  /// 후보가 나온 줄의 위치 (같은 정리 규칙으로 찾음)
  Rect? _boxOf(PhotoCandidate c) {
    for (final l in scanned) {
      if (cleanLine(l.text) == c.read) return l.box;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final size = imageSize;
    final marks = [for (var i = 0; i < found.length; i++) (_boxOf(found[i]), i)];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
          Text(found.isEmpty ? '약 이름을 찾지 못했어요' : '사진에서 찾은 약 이름',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            found.isEmpty
                ? '${error ?? ''} 약 이름이 크게 잘 보이게 다시 찍거나, 말로 찾기·직접 입력을 써 주세요.'.trim()
                : '사진의 번호 칸이 약 이름으로 읽은 곳이에요. 찾으려는 약을 눌러 주세요.',
            style: t.bodyMedium?.copyWith(color: Toss.grey600),
          ),
          // 고른 사진 + 읽은 곳 표시 (번호 = 아래 후보 번호, 회색 = 그 밖에 읽은 글자)
          if (size != null && size.width > 0 && size.height > 0) ...[
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: AspectRatio(
                  aspectRatio: size.width / size.height,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(fit: StackFit.expand, children: [
                      Image.file(File(imagePath), fit: BoxFit.fill),
                      CustomPaint(
                        painter: _MarkPainter(
                          imageSize: size,
                          others: [for (final l in scanned) l.box],
                          marks: [
                            for (final m in marks)
                              if (m.$1 != null) (m.$1!, m.$2),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          for (var i = 0; i < found.length; i++)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 15,
                  backgroundColor: markColor(i),
                  child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                title: Text(found[i].firstName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                subtitle: Text(found[i].exact
                    ? '"${found[i].query}" 검색 결과 ${found[i].total}건'
                    : '사진 글자 "${found[i].read}"와 비슷한 이름 · "${found[i].query}" 검색 ${found[i].total}건'),
                trailing: const Icon(Icons.chevron_right),
                // 누르면 대표 이름으로 바로 검색 (괄호 속 성분은 빼고: "타이레놀정500밀리그람")
                onTap: () => Navigator.pop(context, found[i].searchName),
              ),
            ),
          // 사진에서 어떤 글자를 읽었는지 (왜 이 후보가 나왔는지 확인용)
          if (scanned.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('사진에서 읽은 글자 ${scanned.length}줄', style: t.bodyMedium?.copyWith(color: Toss.grey600)),
              children: [
                for (final l in scanned)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(l.text, style: t.bodySmall?.copyWith(fontSize: 13)),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('닫기', style: TextStyle(fontSize: 16)),
          ),
        ]),
      ),
    );
  }
}

/// 사진 위에 읽은 곳 그리기: 후보 줄은 번호 + 색 테두리, 나머지 읽은 줄은 얇은 흰 테두리
class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.imageSize, required this.others, required this.marks});
  final Size imageSize;
  final List<Rect> others;
  final List<(Rect, int)> marks;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / imageSize.width;
    final sy = size.height / imageSize.height;
    Rect scale(Rect r) => Rect.fromLTRB(r.left * sx, r.top * sy, r.right * sx, r.bottom * sy).inflate(2);

    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withAlpha(200);
    for (final r in others) {
      canvas.drawRect(scale(r), thin);
    }
    for (final (r, i) in marks) {
      final rect = scale(r);
      final color = markColor(i);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color,
      );
      // 번호 동그라미 (왼쪽 위)
      const rad = 11.0;
      final c = Offset(rect.left.clamp(rad, size.width - rad), rect.top.clamp(rad, size.height - rad));
      canvas.drawCircle(c, rad, Paint()..color = color);
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.marks != marks || old.others != others;
}
