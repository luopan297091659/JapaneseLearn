import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'api_service.dart';

/// 统一支付服务 — Apple IAP (iOS) + 二维码截图 (Android)
class PaymentService {
  PaymentService._();
  static final PaymentService instance = PaymentService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _iapAvailable = false;

  /// Apple IAP 产品信息缓存
  Map<String, ProductDetails> _products = {};

  /// 回调：购买完成
  void Function(String planId, bool success, String message)? onPurchaseResult;

  bool _initialized = false;

  // ── 初始化 ──────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (!Platform.isIOS) return;
    if (_initialized) return; // 防止重复订阅 purchaseStream
    _iapAvailable = await _iap.isAvailable();
    if (!_iapAvailable) return;

    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _sub?.cancel(),
      onError: (_) {},
    );
    _initialized = true;
  }

  void dispose() {
    _sub?.cancel();
  }

  // ── 加载 Apple IAP 产品 ──────────────────────────────────────────────────
  Future<List<ProductDetails>> loadProducts(List<String> productIds) async {
    if (!Platform.isIOS) return [];
    if (!_iapAvailable) {
      debugPrint('[IAP] ❌ StoreKit 不可用 (设备未登录 App Store / 未启用购买功能)');
      _lastLoadError = 'StoreKit 不可用';
      return [];
    }
    if (productIds.isEmpty) return [];
    final ids = productIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return [];

    debugPrint('[IAP] 查询产品: $ids');
    final response = await _iap.queryProductDetails(ids);
    _products = {for (final p in response.productDetails) p.id: p};

    if (response.error != null) {
      debugPrint('[IAP] ❌ 查询错误: ${response.error}');
      _lastLoadError = response.error?.message ?? '产品查询失败';
    }
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('[IAP] ⚠️  以下产品在 App Store Connect 未找到/未通过审核: ${response.notFoundIDs}');
      _lastLoadError =
          '以下 IAP 产品未配置或未审核: ${response.notFoundIDs.join(", ")}';
    }
    debugPrint('[IAP] ✅ 已加载产品: ${_products.keys.toList()}');
    return response.productDetails;
  }

  /// 上一次产品加载的错误信息（供 UI 诊断）
  String? _lastLoadError;
  String? get lastLoadError => _lastLoadError;

  /// 根据 apple_product_id 获取本地化价格
  String? getLocalizedPrice(String appleProductId) {
    return _products[appleProductId]?.price;
  }

  // ── 发起 Apple IAP 购买 ──────────────────────────────────────────────────
  /// 发起购买。返回 (started, errorMessage)：
  ///   started=true  → StoreKit 购买流程已发起（不代表用户最终完成）
  ///   started=false → 未能发起，errorMessage 给出原因
  Future<({bool started, String? error})> purchaseAppleDetailed(String appleProductId) async {
    if (!Platform.isIOS) {
      return (started: false, error: '仅 iOS 支持 Apple 内购');
    }
    if (!_iapAvailable) {
      return (started: false, error: 'StoreKit 不可用，请检查设备 App Store 登录状态');
    }
    final product = _products[appleProductId];
    if (product == null) {
      final hint = _lastLoadError != null ? '\n($_lastLoadError)' : '';
      return (
        started: false,
        error: '产品未加载：$appleProductId\n请检查 App Store Connect 中此 IAP 是否已配置并通过审核$hint'
      );
    }
    try {
      final purchaseParam = PurchaseParam(productDetails: product);
      final ok = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      if (!ok) {
        return (started: false, error: 'StoreKit 拒绝发起购买（可能上一笔交易未完成）');
      }
      return (started: true, error: null);
    } catch (e) {
      return (started: false, error: '发起购买异常: $e');
    }
  }

  /// 兼容旧调用：仅返回是否发起成功
  Future<bool> purchaseApple(String appleProductId) async {
    final r = await purchaseAppleDetailed(appleProductId);
    if (r.error != null) debugPrint('[IAP] ❌ ${r.error}');
    return r.started;
  }

  // ── 恢复购买 (Apple 审核 3.1.1 强制要求) ──────────────────────────────
  /// 触发 Apple IAP 恢复购买流程。结果通过 [onPurchaseResult] 回调返回。
  Future<bool> restorePurchases() async {
    if (!Platform.isIOS) return false;
    if (!_iapAvailable) {
      onPurchaseResult?.call('', false, '当前无法连接 App Store，请稍后重试');
      return false;
    }
    try {
      await _iap.restorePurchases();
      return true;
    } catch (e) {
      onPurchaseResult?.call('', false, '恢复购买失败：$e');
      return false;
    }
  }

  // ── IAP 购买回调处理 ────────────────────────────────────────────────────
  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndDeliver(purchase);
          break;
        case PurchaseStatus.error:
          onPurchaseResult?.call('', false, purchase.error?.message ?? '购买失败');
          break;
        case PurchaseStatus.canceled:
          onPurchaseResult?.call('', false, '购买已取消');
          break;
        default:
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _verifyAndDeliver(PurchaseDetails purchase) async {
    try {
      // 根据 productId 匹配 planId
      final planId = _planIdFromProductId(purchase.productID);

      final result = await apiService.verifyApplePurchase(
        receiptData: purchase.verificationData.serverVerificationData,
        planId: planId,
        transactionId: purchase.purchaseID ?? '',
      );

      final alreadyProcessed = result['already_processed'] == true;
      onPurchaseResult?.call(
        planId,
        true,
        alreadyProcessed ? '此交易已处理' : (result['message'] ?? '会员已开通'),
      );
    } catch (e) {
      onPurchaseResult?.call('', false, '验证失败：$e');
    }
  }

  String _planIdFromProductId(String productId) {
    if (productId.contains('monthly')) return 'monthly';
    if (productId.contains('yearly')) return 'yearly';
    if (productId.contains('lifetime')) return 'lifetime';
    return 'monthly';
  }

  // ── 二维码截图提交 (仅 Android) ──────────────────────────────────────────
  Future<Map<String, dynamic>> submitQrProof({
    required String planId,
    required String channel, // 'qrcode_alipay' | 'qrcode_wechat'
    required Uint8List imageBytes,
    String fileName = 'proof.jpg',
  }) async {
    if (Platform.isIOS) throw UnsupportedError('QR payment is not available on iOS');
    return apiService.submitPaymentProof(
      planId: planId,
      channel: channel,
      imageBytes: imageBytes,
      fileName: fileName,
    );
  }

  // ── 获取二维码配置 (仅 Android) ────────────────────────────────────────
  Future<Map<String, dynamic>> getQrConfig() async {
    if (Platform.isIOS) throw UnsupportedError('QR payment is not available on iOS');
    return apiService.getQrCodeConfig();
  }
}

final paymentService = PaymentService.instance;
