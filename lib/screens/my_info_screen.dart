import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/models.dart';
import '../widgets/dialogs.dart';

/// 내 정보: 약 먹는 분 기준의 개인정보를 한곳에서 보고 고침
/// (누구의 약 · 생년월일 · 성별 · 임신 여부). 모두 선택 입력
class MyInfoScreen extends ConsumerWidget {
  const MyInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider).valueOrNull ?? const Profile();
    final t = Theme.of(context).textTheme;
    final other = p.subject == Subject.other;

    Widget item(IconData icon, String title, String value, String why, VoidCallback onTap) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text('$value\n$why', style: const TextStyle(height: 1.45)),
          isThreeLine: true,
          trailing: const Icon(Icons.edit_outlined),
          onTap: onTap,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('내 정보')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            '모두 선택 입력이에요. 약을 먹는 분 기준으로 입력하면 금기·주의 판정이 더 정확해져요.',
            style: t.bodyMedium,
          ),
        ),
        item(Icons.person_outline, '누구의 약인가요', p.subject.label, '가족의 약이면 아래 정보도 그분 기준으로 입력해요.',
            () => editSubject(context, ref, p.subject)),
        const Divider(),
        item(Icons.cake_outlined, other ? '복용하는 분의 생년월일' : '생년월일', p.display ?? '입력 안 함',
            '연령금기와 나이별 용법을 확인할 때 써요.', () => editBirthDate(context, ref, p)),
        const Divider(),
        item(Icons.wc_outlined, other ? '복용하는 분의 성별' : '성별', p.sex.label, '남성이면 임신 여부를 묻지 않아요.',
            () => editSex(context, ref, p.sex)),
        // 남성이면 임신 여부를 묻지 않음 (성별을 건너뛴 여성은 입력 가능)
        if (p.asksPregnancy) ...[
          const Divider(),
          item(Icons.pregnant_woman_outlined, '임신 여부', p.pregnancy.label, '임부금기가 해당되는지 확인할 때 써요.',
              () => editPregnancy(context, ref, p.pregnancy)),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }
}
