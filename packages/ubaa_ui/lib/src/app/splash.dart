part of '../widgets.dart';

/// 启动页：保留旧版 UBAA 标题和标语。
class UbaaSplashView extends StatelessWidget {
  const UbaaSplashView({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'UBAA',
              style: textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 72,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Make BUAA Great Again',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: textTheme.bodyLarge?.color?.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
