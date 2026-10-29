import 'package:flutter/material.dart';

/// Khung chung cho các màn đăng nhập / đăng ký / OTP: đầu trang màu + thẻ nội dung.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 210,
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            flexibleSpace: FlexibleSpaceBar(
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary, scheme.tertiary],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(icon, size: 44, color: scheme.onPrimary),
                        const SizedBox(height: 12),
                        Text(title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.85))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverToBoxAdapter(child: child),
          ),
        ],
      ),
    );
  }
}

void showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$error')));

/// Nút có trạng thái đang tải; [onPressed] null khi [loading].
class LoadingButton extends StatelessWidget {
  const LoadingButton({super.key, required this.label, required this.loading, required this.onPressed});

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Text(label),
      );
}

final usernameRe = RegExp(r'^[a-z0-9_.]{3,30}$');
final emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
const minPassword = 6;
