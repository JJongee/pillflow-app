import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 약 이미지. 이미지가 없거나(CSV 1,990건) 불러오기 실패하면 기본 아이콘.
class DrugImage extends StatelessWidget {
  const DrugImage({super.key, this.url, this.size = 56});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Toss.grey100,
      child: Icon(Icons.medication_outlined, size: size * 0.5, color: Toss.grey400),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
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
