import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../widgets/dialogs.dart';

/// 회원가입 (POST /auth/signup) → 바로 로그인 → 생년월일 저장(선택)
/// 서버 규칙: 이메일 형식, 비밀번호 4자 이상, 같은 이메일은 DUPLICATE
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _birthText = TextEditingController();
  DateTime? _birth;
  Subject _subject = Subject.unknown;
  Sex _sex = Sex.unknown;
  Pregnancy _preg = Pregnancy.unknown;
  bool _loading = false;
  bool _hidePw = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    _pw2.dispose();
    _birthText.dispose();
    super.dispose();
  }

  /// 화면에서 먼저 걸러낼 수 있는 입력 오류
  String? _validate() {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return '이메일 형식을 확인해 주세요.';
    if (_pw.text.length < 4) return '비밀번호는 4자 이상으로 입력해 주세요.';
    if (_pw.text != _pw2.text) return '비밀번호가 서로 달라요.';
    return null;
  }

  Future<void> _pickBirth() async {
    final d = await showDialog<DateTime>(context: context, builder: (_) => BirthDateDialog(initial: _birth));
    if (d == null || !mounted) return;
    setState(() {
      _birth = d;
      _birthText.text = Profile(birthDate: d).display ?? '';
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    // 화면이 닫혀도 쓸 수 있게 미리 잡아 둠
    final repo = ref.read(repositoryProvider);
    final auth = ref.read(authTokenProvider.notifier);
    final navigator = Navigator.of(context);
    final email = _email.text.trim();
    final birth = _birth;
    final subject = _subject, sex = _sex;
    // 여성으로 고른 경우에만 임신 여부를 보냄
    final preg = sex == Sex.female ? _preg : Pregnancy.unknown;
    try {
      await repo.signup(email, _pw.text);
      final token = await repo.login(email, _pw.text);
      ref.read(authNoticeProvider.notifier).state = null;
      auth.state = token; // 이후 요청부터 토큰이 붙음
      // 프로필 저장 실패는 가입을 막지 않음 (설정에서 다시 입력 가능)
      Future<void> quiet(Future<void> Function() f) async {
        try {
          await f();
        } catch (_) {}
      }

      if (birth != null) await quiet(() => repo.setBirthDate(birth));
      if (subject != Subject.unknown) await quiet(() => repo.setSubject(subject));
      if (sex != Sex.unknown) await quiet(() => repo.setSex(sex));
      if (preg != Pregnancy.unknown) await quiet(() => repo.setPregnancy(preg));
      ref.invalidate(profileProvider);
      navigator.popUntil((r) => r.isFirst); // 로그인 화면 위의 가입 화면 닫기 → 홈
    } on RepoException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'DUPLICATE' ? '이미 가입된 이메일이에요. 로그인해 주세요.' : e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
          Text('필플로우를 시작해요', style: t.titleLarge),
          const SizedBox(height: 6),
          Text('먹는 약을 등록하고, 함께 먹어도 되는지 확인할 수 있어요.', style: t.bodyMedium),
          const SizedBox(height: 24),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(labelText: '이메일', prefixIcon: Icon(Icons.mail_outline)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pw,
            obscureText: _hidePw,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              labelText: '비밀번호 (4자 이상)',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _hidePw ? '비밀번호 보기' : '비밀번호 숨기기',
                icon: Icon(_hidePw ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidePw = !_hidePw),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pw2,
            obscureText: _hidePw,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(labelText: '비밀번호 확인', prefixIcon: Icon(Icons.lock_outline)),
          ),
          const SizedBox(height: 20),
          _Choice<Subject>(
            title: '누구의 약을 관리하나요? (선택)',
            options: const [Subject.self, Subject.other],
            value: _subject,
            label: (s) => s.label,
            onChanged: (v) => setState(() => _subject = v),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _birthText,
            readOnly: true,
            onTap: _pickBirth,
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              labelText: _subject == Subject.other ? '복용하는 분의 생년월일 (선택)' : '생년월일 (선택)',
              hintText: '눌러서 입력',
              helperText: '나이에 따라 금기인 약을 확인할 때만 써요. 나중에 설정에서 입력해도 돼요.',
              helperMaxLines: 2,
              prefixIcon: Icon(Icons.cake_outlined),
            ),
          ),
          const SizedBox(height: 16),
          _Choice<Sex>(
            title: _subject == Subject.other ? '복용하는 분의 성별 (선택)' : '성별 (선택)',
            options: const [Sex.female, Sex.male],
            value: _sex,
            label: (s) => s.label,
            onChanged: (v) => setState(() => _sex = v),
          ),
          // 여성일 때만 임신 여부를 물음 (나중에 설정에서도 입력 가능)
          if (_sex == Sex.female) ...[
            const SizedBox(height: 16),
            _Choice<Pregnancy>(
              title: '임신 여부 (선택)',
              options: const [Pregnancy.pregnant, Pregnancy.notPregnant],
              value: _preg,
              label: (p) => p.label,
              onChanged: (v) => setState(() => _preg = v),
            ),
            const SizedBox(height: 4),
            Text('임부금기가 해당되는지 확인할 때만 써요.', style: t.bodySmall),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 16)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('가입하고 시작하기'),
          ),
        ]),
      ),
    );
  }
}

/// 고르기 칩 한 줄. 이미 고른 칩을 다시 누르면 선택 해제(응답 안 함)
class _Choice<T> extends StatelessWidget {
  const _Choice({required this.title, required this.options, required this.value, required this.label, required this.onChanged});
  final String title;
  final List<T> options;
  final T value;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final o in options)
            ChoiceChip(
              label: Text(label(o), style: const TextStyle(fontSize: 16)),
              selected: value == o,
              onSelected: (on) => onChanged(on ? o : _unset(o)),
            ),
        ]),
      ]);

  /// 선택 해제 = 각 enum의 '응답 안 함'
  static R _unset<R>(R o) => switch (o) {
        Subject() => Subject.unknown as R,
        Sex() => Sex.unknown as R,
        Pregnancy() => Pregnancy.unknown as R,
        _ => o,
      };
}
