/// 共享 UI 的稳定公开组件；实现分别归属独立 library。
export 'app/app_service/notices.dart'
    show
        AppServiceNotices,
        uiShowAnnouncement,
        uiShowReleaseNotes,
        uiShowUpdateRequired;
export 'app/app_service/privacy.dart'
    show
        PrivacyConsentDialog,
        PrivacyPolicyPage,
        uiPrivacyConsentRoute,
        uiShowPrivacyAgreement;
export 'app/app_service/settings.dart' show AppServiceControls;
export 'app/login.dart' show UbaaLoginView;
export 'app/login_verification.dart' show UbaaCaptchaDialog;
export 'app/shell.dart' show UbaaMainShell, WidgetNavigationState;
export 'app/splash.dart' show UbaaSplashView;
export 'common/error_card.dart'
    show
        FriendlyErrorCard,
        UiDiagnosticsScope,
        uiDiagnosticsGuidance,
        uiShowDiagnosticsDialog,
        uiErrorDetailsAction;
export 'features/cgyy/lock_display.dart' show UbaaCgyyLockDisplayView;
export 'write/confirmation.dart' show WriteConfirmationView;

export 'features/agenda/format.dart' show AgendaAccess;
