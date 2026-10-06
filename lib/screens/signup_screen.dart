import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import '../data/repository.dart';

/// 회원가입 (POST /auth/signup) → 바로 로그인 → 태어난 해 저장(선택)
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
  final _year = TextEditingController();
  bool _loading = false;
  bool _hidePw = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    _pw2.dispose();
    _year.dispose();
    super.dispose();
  }

  /// 화면에서 먼저 걸러낼 수 있는 입력 오류
  String? _validate() {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return '이메일 형식을 확인해 주세요.';
    if (_pw.text.length < 4) return '비밀번호는 4자 이상으로 입력해 주세요.';
    if (_pw.text != _pw2.text) return '비밀번호가 서로 달라요.';
    final y = _year.text.trim();
    if (y.isNotEmpty) {
      final n = int.tryParse(y);
      if (n == null || n < 1900 || n > DateTime.now().year) return '태어난 해를 다시 확인해 주세요.';
    }
    return null;
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
    final year = int.tryParse(_year.text.trim());
    try {
      await repo.signup(email, _pw.text);
      final token = await repo.login(email, _pw.text);
      auth.state = token; // 이후 요청부터 토큰이 붙음
      if (year != null) {
        try {
          await repo.setBirthYear(year);
        } catch (_) {
          // 태어난 해 저장 실패는 가입을 막지 않음 (설정에서 다시 입력 가능)
        }
      }
      ref.invalidate(birthYearProvider);
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
          const SizedBox(height: 14),
          TextField(
            controller: _year,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _loading ? null : _submit(),
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
              labelText: '태어난 해 (선택)',
              hintText: '예: 1958',
              helperText: '나이에 따라 금기인 약을 확인할 때만 써요. 나중에 설정에서 입력해도 돼요.',
              helperMaxLines: 2,
              prefixIcon: Icon(Icons.cake_outlined),
            ),
          ),
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
