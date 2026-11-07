import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'guest_service.dart';
import 'membership_service.dart';
import 'sync_service.dart';

class AdService extends ChangeNotifier with WidgetsBindingObserver {
  static final AdService instance = AdService._();
  AdService._();

  static const _adsDisabledKey = 'ios_ads_disabled';
  static const _productionBannerId = 'ca-app-pub-5858977826294206/8739761991';
  static const _testBannerId = 'ca-app-pub-3940256099942544/2934735716';
  static const _productionAppOpenId = 'ca-app-pub-5858977826294206/8776702272';
  static const _testAppOpenId = 'ca-app-pub-3940256099942544/9257395921';

  Future<void>? _initialization;
  Timer? _serverToggleTimer;
  StreamSubscription<AppState>? _appStateSubscription;
  Completer<void>? _serverRefreshCompleter;
  AppOpenAd? _appOpenAd;
  DateTime? _appOpenLoadedAt;
  bool _isReady = false;
  bool _adsDisabled = false;
  bool _serverEnabled = true;
  bool _consentFlowStarted = false;
  bool _appOpenLoading = false;
  bool _appOpenShowing = false;
  bool _hasEnteredBackground = false;

  bool get isReady => _isReady;
  bool get adsDisabled => _adsDisabled;
  bool get serverEnabled => _serverEnabled;
  String get bannerAdUnitId => kDebugMode ? _testBannerId : _productionBannerId;
  String get appOpenAdUnitId =>
      kDebugMode ? _testAppOpenId : _productionAppOpenId;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    WidgetsBinding.instance.addObserver(this);
    try {
      final prefs = await SharedPreferences.getInstance();
      _adsDisabled = prefs.getBool(_adsDisabledKey) ?? false;
      notifyListeners();
      _serverToggleTimer ??= Timer.periodic(
          const Duration(minutes: 2), (_) => _refreshServerSetting());
      await _refreshServerSetting();
    } catch (error) {
      debugPrint('Ad initialization failed: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshServerSetting());
    }
  }

  Future<void> _refreshServerSetting() async {
    final activeRefresh = _serverRefreshCompleter;
    if (activeRefresh != null) {
      await activeRefresh.future;
      return;
    }
    final refreshCompleter = Completer<void>();
    _serverRefreshCompleter = refreshCompleter;
    try {
      final toggles = await syncService.fetchFeatureToggles(force: true);
      final enabled = toggles['mobile-ads'] ?? true;
      if (_serverEnabled != enabled) {
        _serverEnabled = enabled;
        if (!enabled) _disposeAppOpenAd();
        notifyListeners();
      }
      if (enabled && !_consentFlowStarted) {
        _consentFlowStarted = true;
        _requestConsentAndInitialize();
      }
    } catch (error) {
      debugPrint('Ad setting sync failed: $error');
      if (!_consentFlowStarted) {
        _consentFlowStarted = true;
        _requestConsentAndInitialize();
      }
    } finally {
      _serverRefreshCompleter = null;
      refreshCompleter.complete();
    }
  }

  void _requestConsentAndInitialize() {
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => _onConsentInfoUpdated(),
      (error) {
        debugPrint('Ad consent info update failed: $error');
        _initializeIfAllowed();
      },
    );
  }

  Future<void> _onConsentInfoUpdated() async {
    try {
      await ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (error != null) debugPrint('Ad consent form failed: $error');
      });
    } catch (error) {
      debugPrint('Ad consent form failed: $error');
    }
    await _initializeIfAllowed();
  }

  Future<void> _initializeIfAllowed() async {
    try {
      if (!await ConsentInformation.instance.canRequestAds()) return;
      await MobileAds.instance.initialize();
      _isReady = true;
      notifyListeners();
      if (Platform.isAndroid) {
        await AppStateEventNotifier.startListening();
        _appStateSubscription ??=
            AppStateEventNotifier.appStateStream.listen(_onAppStateChanged);
        _loadAppOpenAd();
      }
    } catch (error) {
      debugPrint('Google Mobile Ads initialization failed: $error');
    }
  }

  Future<void> setAdsDisabled(bool disabled) async {
    if ((!Platform.isIOS && !Platform.isAndroid) ||
        !membershipService.cachedIsMember) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adsDisabledKey, disabled);
    _adsDisabled = disabled;
    if (disabled) {
      _disposeAppOpenAd();
    } else {
      _loadAppOpenAd();
    }
    notifyListeners();
  }

  void _onAppStateChanged(AppState state) {
    if (state == AppState.background) {
      _hasEnteredBackground = true;
      return;
    }
    if (state == AppState.foreground && _hasEnteredBackground) {
      _hasEnteredBackground = false;
      unawaited(_handleAppForeground());
    }
  }

  Future<void> _handleAppForeground() async {
    await _refreshServerSetting();
    if (!_canShowAds) return;
    _showAppOpenAdIfAvailable();
  }

  bool get _canShowAds {
    final isPublicSession = guestService.isGuest;
    final hasVerifiedUser = membershipService.hasCachedStatus;
    final memberOptedOut =
        hasVerifiedUser && membershipService.cachedIsMember && _adsDisabled;
    return Platform.isAndroid &&
        _serverEnabled &&
        _isReady &&
        (isPublicSession || hasVerifiedUser) &&
        !memberOptedOut;
  }

  void _loadAppOpenAd() {
    if (!Platform.isAndroid ||
        !_canShowAds ||
        _appOpenLoading ||
        _appOpenAd != null) {
      return;
    }
    _appOpenLoading = true;
    AppOpenAd.load(
      adUnitId: appOpenAdUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenLoading = false;
          if (!_canShowAds) {
            ad.dispose();
            return;
          }
          _appOpenAd = ad;
          _appOpenLoadedAt = DateTime.now();
        },
        onAdFailedToLoad: (error) {
          _appOpenLoading = false;
          debugPrint('App open ad failed to load: $error');
        },
      ),
    );
  }

  void _showAppOpenAdIfAvailable() {
    final ad = _appOpenAd;
    if (!_canShowAds || _appOpenShowing) return;
    if (ad == null) {
      _loadAppOpenAd();
      return;
    }
    if (_appOpenLoadedAt == null ||
        DateTime.now().difference(_appOpenLoadedAt!) >
            const Duration(hours: 4)) {
      _disposeAppOpenAd();
      _loadAppOpenAd();
      return;
    }

    _appOpenShowing = true;
    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdShowedFullScreenContent: (_) => _appOpenShowing = true,
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('App open ad failed to show: $error');
        _appOpenShowing = false;
        ad.dispose();
        _appOpenAd = null;
        _appOpenLoadedAt = null;
        _loadAppOpenAd();
      },
      onAdDismissedFullScreenContent: (ad) {
        _appOpenShowing = false;
        ad.dispose();
        _appOpenAd = null;
        _appOpenLoadedAt = null;
        _loadAppOpenAd();
      },
    );
    ad.show();
  }

  void _disposeAppOpenAd() {
    _appOpenAd?.dispose();
    _appOpenAd = null;
    _appOpenLoadedAt = null;
  }

  @override
  void dispose() {
    _serverToggleTimer?.cancel();
    _appOpenSubscriptionCancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _appOpenSubscriptionCancel() {
    _appStateSubscription?.cancel();
    _appStateSubscription = null;
    _disposeAppOpenAd();
  }
}

final adService = AdService.instance;
