import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_service.dart';
import '../services/guest_service.dart';
import '../services/membership_service.dart';

class AppBannerAd extends StatelessWidget {
  final bool showOnAuthPage;

  const AppBannerAd({super.key, this.showOnAuthPage = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([adService, membershipService]),
      builder: (context, _) {
        final publicSession = showOnAuthPage || guestService.isGuest;
        final isMember = membershipService.cachedIsMember;
        final canShowForSession =
          publicSession || membershipService.hasCachedStatus;
        final memberDisabledAds =
            !publicSession && isMember && adService.adsDisabled;
        if (!Platform.isIOS ||
          !adService.serverEnabled ||
            !adService.isReady ||
            !canShowForSession ||
            memberDisabledAds) {
          return const SizedBox.shrink();
        }
        return const _AdaptiveBannerAd();
      },
    );
  }
}

class _AdaptiveBannerAd extends StatefulWidget {
  const _AdaptiveBannerAd();

  @override
  State<_AdaptiveBannerAd> createState() => _AdaptiveBannerAdState();
}

class _AdaptiveBannerAdState extends State<_AdaptiveBannerAd> {
  BannerAd? _bannerAd;
  AnchoredAdaptiveBannerAdSize? _bannerSize;
  int? _requestedWidth;
  int _loadGeneration = 0;

  void _loadForWidth(int width) {
    if (width <= 0 || width == _requestedWidth) return;
    _requestedWidth = width;
    final generation = ++_loadGeneration;
    _bannerAd?.dispose();
    _bannerAd = null;
    _bannerSize = null;
    _createBanner(width, generation);
  }

  Future<void> _createBanner(int width, int generation) async {
    try {
      final size =
          await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
      if (!mounted || generation != _loadGeneration || size == null) return;

      final banner = BannerAd(
        adUnitId: adService.bannerAdUnitId,
        request: const AdRequest(),
        size: size,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted || generation != _loadGeneration) {
              ad.dispose();
              return;
            }
            setState(() {
              _bannerAd = ad as BannerAd;
              _bannerSize = size;
            });
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            if (mounted && generation == _loadGeneration) {
              debugPrint('Banner ad failed to load: $error');
            }
          },
        ),
      );
      await banner.load();
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        debugPrint('Banner ad request failed: $error');
      }
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth.truncate()
            : MediaQuery.sizeOf(context).width.truncate();
        _loadForWidth(width);
        final banner = _bannerAd;
        final size = _bannerSize;
        if (banner == null || size == null) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: SizedBox(
            width: size.width.toDouble(),
            height: size.height.toDouble(),
            child: AdWidget(ad: banner),
          ),
        );
      },
    );
  }
}
