import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../data/providers.dart';
import '../widgets/state_views.dart';

/// 로그인 화면 틀. 서버 인증 형식(POST /auth/login)이 확정되면 api_repository.dart 의 login 만 맞추면 됩니다.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialError});

  /// 화면 상태 미리보기용: 처음부터 오류 문구를 보여줍니다.
  final String? initialError;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // 목업 모드에서는 시연이 빠르도록 미리 채워 둡니다.
  late final _email = TextEditingController(text: AppConfig.useMock ? 'demo@pillflow.app' : '');
  late final _pw = TextEditingController(text: AppConfig.useMock ? '1234' : '');
  bool _loading = false;
  bool _hidePw = true;
  late String? _error = widget.initialError;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await ref.read(repositoryProvider).login(_email.text.trim(), _pw.text);
      ref.read(authTokenProvider.notifier).state = token; // → AuthGate 가 홈으로 전환
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.medication_rounded, size: 64, color: AppColors.primary),
                const SizedBox(height: 12),
                Text('필플로우',
                    textAlign: TextAlign.center,
                    style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
                const SizedBox(height: 6),
                Text('함께 먹는 약, 안전하게 관리해요', textAlign: TextAlign.center, style: t.bodyLarge),
                const SizedBox(height: 32),
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
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _loading ? null : _login(),
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    labelText: '비밀번호',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _hidePw ? '비밀번호 보기' : '비밀번호 숨기기',
                      icon: Icon(_hidePw ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hidePw = !_hidePw),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 16)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('로그인'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => showSnack(context, '회원가입은 서버 인증이 정해지면 추가할게요.'),
                  child: const Text('처음이신가요? 회원가입'),
                ),
                if (AppConfig.useMock) ...[
                  const SizedBox(height: 16),
                  Text('목업 모드: 이메일 형식 + 비밀번호 4자 이상이면 로그인돼요.',
                      textAlign: TextAlign.center, style: t.bodySmall),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
