ALTER TABLE membership_orders
  ADD COLUMN alipay_out_trade_no VARCHAR(100) NULL COMMENT '支付宝商户订单号' AFTER stripe_session_id,
  ADD COLUMN alipay_trade_no VARCHAR(100) NULL COMMENT '支付宝交易号' AFTER alipay_out_trade_no;

CREATE INDEX idx_membership_orders_alipay_out_trade_no ON membership_orders (alipay_out_trade_no);
CREATE INDEX idx_membership_orders_alipay_trade_no ON membership_orders (alipay_trade_no);
