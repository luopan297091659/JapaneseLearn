import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
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

  // ── 初始化 ──────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (!Platform.isIOS) return;
    _iapAvailable = await _iap.isAvailable();
    if (!_iapAvailable) return;

    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _sub?.cancel(),
      onError: (_) {},
    );
  }

  void dispose() {
    _sub?.cancel();
  }

  // ── 加载 Apple IAP 产品 ──────────────────────────────────────────────────
  Future<List<ProductDetails>> loadProducts(List<String> productIds) async {
    if (!_iapAvailable || productIds.isEmpty) return [];
    final ids = productIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return [];

    final response = await _iap.queryProductDetails(ids);
    _products = {for (final p in response.productDetails) p.id: p};
    return response.productDetails;
  }

  /// 根据 apple_product_id 获取本地化价格
  String? getLocalizedPrice(String appleProductId) {
    return _products[appleProductId]?.price;
  }

  // ── 发起 Apple IAP 购买 ──────────────────────────────────────────────────
  Future<bool> purchaseApple(String appleProductId) async {
    if (!_iapAvailable) return false;
    final product = _products[appleProductId];
    if (product == null) return false;

    final purchaseParam = PurchaseParam(productDetails: product);
    return _iap.buyNonConsumable(purchaseParam: purchaseParam);
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

  // ── 二维码截图提交 (Android) ────────────────────────────────────────────
  Future<Map<String, dynamic>> submitQrProof({
    required String planId,
    required String channel, // 'qrcode_alipay' | 'qrcode_wechat'
    required Uint8List imageBytes,
    String fileName = 'proof.jpg',
  }) async {
    return apiService.submitPaymentProof(
      planId: planId,
      channel: channel,
      imageBytes: imageBytes,
      fileName: fileName,
    );
  }

  // ── 获取二维码配置 ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getQrConfig() async {
    return apiService.getQrCodeConfig();
  }
}

final paymentService = PaymentService.instance;
