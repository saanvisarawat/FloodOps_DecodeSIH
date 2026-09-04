import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController(text: 'volunteer.anand@keralarescue.in');
  final _passwordController = TextEditingController(text: 'password123');
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await ref.read(authProvider.notifier).login(
          _emailController.text.trim(),
          _passwordController.text,
        );
    if (ok && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.section),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cardBorder),
                    boxShadow: AppColors.glow(blur: 20),
                  ),
                  child: const Icon(Icons.shield_outlined, size: 30, color: AppColors.accent),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Volunteer & Official Sign In',
                style: AppTypography.screenTitle(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Citizens don\'t need an account — SOS, Risk, Map, Ragbot and '
                'Verification all work without signing in.',
                style: AppTypography.body(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: AppTypography.body(),
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                style: AppTypography.body(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppColors.textTertiary,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (auth.error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(auth.error!, style: AppTypography.label(color: AppColors.danger)),
              ],
              const SizedBox(height: AppSpacing.section),
              AppButton(
                label: 'Sign In',
                isLoading: auth.isLoading,
                onPressed: _submit,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton.tertiary(
                label: 'New volunteer or official? Create an account',
                expand: true,
                onPressed: () => context.push('/register'),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Tip: include "official" in the email to demo the Official view '
                '(e.g. official.priya@keralasdma.in).',
                style: AppTypography.caption(),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
