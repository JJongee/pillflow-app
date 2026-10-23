import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 약 이미지. 이미지가 없거나(CSV 1,990건) 불러오기 실패하면 기본 아이콘.
///
/// e약은요 낱알 사진은 앞·뒷면이 나란히 있는 가로로 긴 사진이라
/// - 칸을 가로로 넓게(높이 × 1.6) 잡고
/// - 사진 전체가 보이게(contain) 넣은 뒤
/// - 남는 공간은 같은 사진을 흐리게 깔아 사진 배경색과 자연스럽게 이어지게 함
class DrugImage extends StatelessWidget {
  const DrugImage({super.key, this.url, this.size = 60});
  final String? url;

  /// 칸 높이. 너비는 높이의 1.6배
  final double size;

  @override
  Widget build(BuildContext context) {
    final w = size * 1.6;
    final placeholder = Container(
      width: w,
      height: size,
      color: Toss.grey100,
      child: Icon(Icons.medication_outlined, size: size * 0.5, color: Toss.grey400),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: url == null
          ? placeholder
          : SizedBox(
              width: w,
              height: size,
              child: Stack(fit: StackFit.expand, children: [
                // 뒤: 같은 사진을 꽉 채워 크게 흐림 → 사진 배경색으로 빈 곳을 채움
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: TileMode.mirror),
                  child: Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
                ),
                // 앞: 사진 전체 (잘리지 않게)
                Image.network(url!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => placeholder),
              ]),
            ),
    );
  }
}

/// e약은요 긴 설명문을 접었다 펼치는 카드. 값이 없으면 "정보 없음".
class InfoSection extends StatefulWidget {
  const InfoSection({super.key, required this.title, required this.body, this.initiallyExpanded = false});
  final String title;
  final String? body;
  final bool initiallyExpanded;

  @override
  State<InfoSection> createState() => _InfoSectionState();
}

class _InfoSectionState extends State<InfoSection> {
  late bool _open = widget.initiallyExpanded;
  static const _previewChars = 90;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final body = widget.body;
    final long = body != null && body.length > _previewChars;
    final shown = body == null
        ? '정보 없음'
        : (!_open && long)
            ? '${body.substring(0, _previewChars)}…'
            : body;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: long ? () => setState(() => _open = !_open) : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(widget.title, style: t.titleMedium?.copyWith(fontSize: 18))),
              if (long) Icon(_open ? Icons.expand_less : Icons.expand_more),
            ]),
            const SizedBox(height: 8),
            Text(shown, style: t.bodyLarge?.copyWith(color: body == null ? Toss.grey500 : null)),
          ]),
        ),
      ),
    );
  }
}

/// 약 이름을 '제품 이름'과 '( ) 안 성분'으로 나눔
/// 예: '타이레놀정500밀리그람(아세트아미노펜)' → ('타이레놀정500밀리그람', '아세트아미노펜')
(String, String?) splitDrugName(String name) {
  final i = name.indexOf('(');
  if (i <= 0) return (name, null);
  final main = name.substring(0, i).trim();
  var sub = name.substring(i + 1).trim();
  if (sub.endsWith(')')) sub = sub.substring(0, sub.length - 1).trim();
  return (main, sub.isEmpty ? null : sub);
}

/// 긴 약 이름: 제품 이름은 크게, 괄호 안 성분은 아랫줄에 작게 (큰 글자에서 어색하게 끊기지 않게)
class DrugNameText extends StatelessWidget {
  const DrugNameText(this.name, {super.key, this.style, this.trailing});
  final String name;
  final TextStyle? style;

  /// 이름 옆에 붙일 것 (예: '직접 추가' 배지)
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final (main, sub) = splitDrugName(name);
    final base = style ?? Theme.of(context).textTheme.bodyLarge;
    final title = trailing == null
        ? Text(main, style: base)
        : Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 2,
            children: [Text(main, style: base), trailing!],
          );
    if (sub == null) return title;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      title,
      const SizedBox(height: 2),
      Text(sub,
          style: base?.copyWith(
            fontSize: (base?.fontSize ?? 16) * 0.8,
            color: Toss.grey500,
            fontWeight: FontWeight.w400,
          )),
    ]);
  }
}
