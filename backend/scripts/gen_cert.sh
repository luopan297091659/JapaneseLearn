#!/bin/bash
# 在 Linux 服务器 (139.196.44.6) 上运行此脚本生成自签名 SSL 证书
# 用法：bash scripts/gen_cert.sh

SERVER_IP="139.196.44.6"
CERT_DIR="./certs"

mkdir -p "$CERT_DIR"

openssl req -x509 \
  -newkey rsa:4096 \
  -keyout "$CERT_DIR/key.pem" \
  -out "$CERT_DIR/cert.pem" \
  -days 3650 \
  -nodes \
  -subj "/C=CN/ST=Shanghai/L=Shanghai/O=JapaneseLearn/CN=$SERVER_IP" \
  -addext "subjectAltName=IP:$SERVER_IP"

echo "✓ 证书已生成："
echo "  证书: $CERT_DIR/cert.pem"
echo "  私钥: $CERT_DIR/key.pem"
echo ""
echo "重启后端服务: npm start"
