part of 'login.dart';

extension LoginVerificationControls on _UbaaLoginViewState {
  List<Widget> _buildVerificationControls() => <Widget>[
    for (final route in widget.verification!.routes) ...<Widget>[
      if (route.status ==
          LoginRouteVerificationStatus.captchaRequired) ...<Widget>[
        const SizedBox(height: 16),
        Text('${route.route.label} 验证码'),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: '${route.route.label} 验证码，点击刷新',
          child: InkWell(
            key: ValueKey<String>('captcha-image-${route.route.name}'),
            onTap: widget.isLoading || widget.onRefreshCaptcha == null
                ? null
                : () => widget.onRefreshCaptcha!(route.route),
            child: Container(
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: route.isRefreshing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : route.hasUsableFrame
                  ? CaptchaPixels(frame: route.frame!)
                  : const Text('图片暂不可用，点击刷新'),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('点击图片刷新', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        TextField(
          key: ValueKey<String>('captcha-answer-${route.route.name}'),
          controller: _answerControllers[route.route],
          enabled: !widget.isLoading && route.hasUsableFrame,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          enableInteractiveSelection: false,
          contextMenuBuilder: (_, _) => const SizedBox.shrink(),
          decoration: InputDecoration(labelText: '${route.route.label} 验证码答案'),
          onChanged: (value) =>
              widget.onCaptchaAnswerChanged?.call(route.route, value),
          onSubmitted: (_) {
            if (_canSubmit) widget.onSubmit();
          },
        ),
        if (route.error case final error?) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            error.message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
      if (route.status == LoginRouteVerificationStatus.ready) ...<Widget>[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: widget.isLoading || widget.onContinueReady == null
              ? null
              : () => widget.onContinueReady!(route.route),
          icon: const Icon(Icons.check_circle_outline),
          label: Text(
            widget.routePolicy == RoutePolicy.auto
                ? '保持自动连接并继续'
                : '使用已就绪的${route.route.label}',
          ),
        ),
        if (widget.routePolicy == RoutePolicy.auto)
          OutlinedButton(
            onPressed: widget.isLoading || widget.onContinueFixedReady == null
                ? null
                : () => widget.onContinueFixedReady!(route.route),
            child: Text('改用${route.route.label}并继续'),
          ),
      ],
      if (route.status == LoginRouteVerificationStatus.failed) ...<Widget>[
        const SizedBox(height: 8),
        Text('${route.route.label} 暂未就绪'),
      ],
    ],
  ];
}
