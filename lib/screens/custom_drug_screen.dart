import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../data/adherence.dart';
import '../data/custom_photos.dart';
import '../data/providers.dart';
import '../models/models.dart';
import '../widgets/custom_drug_widgets.dart';
import '../widgets/state_views.dart';

/// 직접 추가 (영양제·목록에 없는 약) — 복용 시간·기록만 관리, DUR 확인에는 넣지 않음
/// [existing]이 있으면 수정 모드. 추가하면 만든 항목을 돌려줌 (→ 바로 시간 정하기)
class CustomDrugScreen extends ConsumerStatefulWidget {
  const CustomDrugScreen({super.key, this.existing, this.initialName});
  final UserDrug? existing;

  /// 검색에서 못 찾은 이름을 그대로 채워 줄 때
  final String? initialName;

  @override
  ConsumerState<CustomDrugScreen> createState() => _CustomDrugScreenState();
}

class _CustomDrugScreenState extends ConsumerState<CustomDrugScreen> {
  bool get _isEdit => widget.existing != null;
  late final _name = TextEditingController(text: widget.existing?.itemName ?? widget.initialName ?? '');
  late final _memo = TextEditingController(text: widget.existing?.memo ?? '');
  late CustomKind _kind = widget.existing?.kind ?? CustomKind.supplement;

  /// 화면에 보이는 사진 (새로 고른 사진 또는 저장돼 있던 사진)
  String? _photo;
  bool _photoChanged = false;
  bool _saving = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final id = widget.existing?.id;
    if (id != null) {
      ref.read(customPhotosProvider.future).then((m) {
        if (mounted && !_photoChanged) setState(() => _photo = m[id]);
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _memo.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('사진 찍기', style: TextStyle(fontSize: 17)),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('앨범에서 고르기', style: TextStyle(fontSize: 17)),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (source == null) return;
    try {
      final img = await ImagePicker().pickImage(source: source, maxWidth: 1200, imageQuality: 85);
      final path = img?.path; // 닫힌 뒤 null 오류 방지: 경로를 먼저 꺼내 둠
      if (path == null || !mounted) return;
      setState(() {
        _photo = path;
        _photoChanged = true;
      });
    } catch (_) {
      if (mounted) showSnack(context, '사진을 가져오지 못했어요. 사진 없이도 추가할 수 있어요.');
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '이름을 입력해 주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _nameError = null;
    });
    // 띄어쓰기·대소문자만 다른 이름도 같은 항목으로 봄 ('오메가3' = '오메가 3')
    // 서버는 글자가 똑같을 때만 막아서 앱에서 먼저 확인
    try {
      final key = _sameNameKey(name);
      final mine = await ref.read(myDrugsProvider.future);
      final dup = mine.any((d) => d.isCustom && d.id != widget.existing?.id && _sameNameKey(d.itemName) == key);
      if (dup) {
        if (mounted) {
          setState(() {
            _saving = false;
            _nameError = '이미 같은 이름으로 추가했어요.';
          });
        }
        return;
      }
    } catch (_) {
      // 목록을 못 불러오면 서버 확인에 맡김
    }
    if (!mounted) return;
    final repo = ref.read(repositoryProvider);
    final memo = _memo.text.trim().isEmpty ? null : _memo.text.trim();
    try {
      UserDrug d;
      if (_isEdit) {
        final e = widget.existing!;
        d = await repo.updateCustomDrug(e.id, name: name, kind: _kind);
        if (memo != e.memo) d = await repo.updateMyDrug(e.id, memo: memo);
      } else {
        d = await repo.addCustomDrug(name, kind: _kind, memo: memo);
      }
      // 사진은 이 폰에만 저장. 새로 만든 항목은 혹시 남아 있던 예전 사진을 먼저 지움
      if (_photoChanged || !_isEdit) {
        final p = _photo;
        if (p == null) {
          await deleteCustomPhoto(d.id);
        } else {
          await saveCustomPhoto(d.id, p);
        }
      }
      ref.invalidate(customPhotosProvider);
      ref.invalidate(myDrugsProvider);
      ref.invalidate(schedulesProvider);
      ref.invalidate(intakesProvider(todayString()));
      ref.invalidate(daySummariesProvider); // 이번 주 줄·달력도 바로
      if (mounted) Navigator.pop(context, d);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e.toString();
      if (msg.contains('같은 이름')) {
        setState(() => _nameError = msg);
      } else {
        showSnack(context, msg);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '직접 추가 항목 수정' : '직접 추가')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        // 무엇을 하고 무엇을 안 하는지 먼저 알려 줌
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: customPurple50, borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, color: customPurple, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                keepWords('영양제나 목록에 없는 약을 등록해 복용 시간과 기록을 관리해요. '
                    '함께 먹어도 되는지 확인에는 들어가지 않아요.'),
                style: const TextStyle(fontSize: 14, height: 1.45, color: Toss.grey700),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          maxLength: 50,
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            labelText: '이름 (필수)',
            hintText: '예: 종합비타민, 오메가3',
            errorText: _nameError,
          ),
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        const SizedBox(height: 8),
        Text('종류', style: t.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in CustomKind.values)
              ChoiceChip(
                label: Text(k.label, style: const TextStyle(fontSize: 16)),
                selected: _kind == k,
                onSelected: (_) => setState(() => _kind = k),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('사진 (선택)', style: t.titleMedium),
        const SizedBox(height: 4),
        Text('사진은 이 폰에만 저장돼요.', style: t.bodySmall?.copyWith(fontSize: 13)),
        const SizedBox(height: 8),
        if (_photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(File(_photo!), height: 180, width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(height: 60, child: Center(child: Text('사진을 열 수 없어요')))),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(_photo == null ? '사진 넣기' : '사진 바꾸기'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
          ),
          if (_photo != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() {
                _photo = null;
                _photoChanged = true;
              }),
              child: const Text('사진 빼기'),
            ),
          ],
        ]),
        const SizedBox(height: 20),
        TextField(
          controller: _memo,
          maxLength: 100,
          style: const TextStyle(fontSize: 17),
          decoration: const InputDecoration(labelText: '메모 (선택)', hintText: '예: 아침 식후 1알'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          child: Text(
            _saving ? '저장 중…' : (_isEdit ? '저장' : '추가하고 시간 정하기'),
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ]),
    );
  }
}

String _sameNameKey(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();
