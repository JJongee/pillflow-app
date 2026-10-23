import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// 직접 추가 항목 표시색 (보라). 빨강=금기, 파랑=복용과 겹치지 않게
const customPurple = Color(0xFF7B5CD6);
const customPurple50 = Color(0xFFF1ECFC);

/// '직접 추가' 배지
class CustomBadge extends StatelessWidget {
  const CustomBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: customPurple50, borderRadius: BorderRadius.circular(999)),
        child: const Text('직접 추가',
            softWrap: false, style: TextStyle(color: customPurple, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}

/// 종류별 기본 아이콘
IconData customKindIcon(CustomKind? k) => switch (k) {
      CustomKind.supplement => Icons.eco_outlined, // 잎사귀
      CustomKind.medicine => Icons.medication_outlined,
      _ => Icons.inventory_2_outlined,
    };

/// 직접 추가 항목 사진 (폰에 저장한 사진, 없으면 종류 아이콘). DrugImage와 같은 크기
class CustomDrugThumb extends StatelessWidget {
  const CustomDrugThumb({super.key, this.path, this.kind, this.size = 60});
  final String? path;
  final CustomKind? kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final w = size * 1.6;
    final icon = Container(
      width: w,
      height: size,
      color: customPurple50,
      child: Icon(customKindIcon(kind), size: size * 0.5, color: customPurple),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: path == null
          ? icon
          : Image.file(File(path!),
              width: w, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => icon),
    );
  }
}

/// 이름 + 배지 한 줄 (이름이 길면 줄바꿈, 배지는 끝에)
class CustomDrugTitle extends StatelessWidget {
  const CustomDrugTitle({super.key, required this.name, this.style});
  final String name;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 2,
        children: [Text(name, style: style), const CustomBadge()],
      );
}

/// 확인 결과 화면에 들어가는 회색 안내 한 줄
class ExcludedCustomNote extends StatelessWidget {
  const ExcludedCustomNote({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Toss.grey100, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, size: 20, color: Toss.grey600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '직접 추가한 항목 $count개는 확인에 들어가지 않았어요.\n'
              '영양제나 목록에 없는 약은 함께 먹어도 되는지 약사와 확인해 주세요.',
              style: const TextStyle(fontSize: 14, height: 1.45, color: Toss.grey700),
            ),
          ),
        ]),
      );
}
