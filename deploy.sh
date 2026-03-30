#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
#  deploy.sh — 自动部署 Japanese Learn 后端（Rocky Linux）
#  macOS / Linux 兼容，使用 ssh/scp
#  关键特性：部署时保留服务器上的管理员配置文件
# ══════════════════════════════════════════════════════════════════
set -euo pipefail

# ── 配置 ──
SERVER_HOST="139.196.44.6"
SERVER_USER="root"
SERVER_PASS="Xiaoyun@123"
SERVER_PORT=22
REMOTE_PATH="/home/japanese-learn/backend"
LOCAL_BACKEND="$(cd "$(dirname "$0")/backend" && pwd)"

# 需要在部署时保留的配置文件（服务器上已有的不覆盖）
PRESERVE_CONFIGS=(
  "config/feature_tiers.json"
  "config/feature_toggles.json"
  "config/ai_settings.json"
  "config/membership.json"
)

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -p ${SERVER_PORT}"
SCP_OPTS="-o StrictHostKeyChecking=no -P ${SERVER_PORT}"

# ── 辅助函数（使用 sshpass 自动输入密码）──
info()  { echo -e "\033[36m[INFO]\033[0m $*"; }
ok()    { echo -e "\033[32m[ OK ]\033[0m $*"; }
warn()  { echo -e "\033[33m[WARN]\033[0m $*"; }
err()   { echo -e "\033[31m[ERR ]\033[0m $*"; }
remote(){ sshpass -p "${SERVER_PASS}" ssh ${SSH_OPTS} "${SERVER_USER}@${SERVER_HOST}" "$@"; }
upload_file(){ sshpass -p "${SERVER_PASS}" scp ${SCP_OPTS} "$1" "${SERVER_USER}@${SERVER_HOST}:$2"; }
upload_dir() { sshpass -p "${SERVER_PASS}" scp ${SCP_OPTS} -r "$1" "${SERVER_USER}@${SERVER_HOST}:$2"; }

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  部署 Japanese Learn 后端 → ${SERVER_USER}@${SERVER_HOST}"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── [1/7] 测试连接 ──
info "[1/7] 测试 SSH 连接..."
if remote "echo ok" >/dev/null 2>&1; then
  ok "SSH 连接成功"
else
  err "SSH 连接失败，请检查服务器地址、端口和密码"
  exit 1
fi

# ── [2/7] 创建远程目录 ──
info "[2/7] 创建远程目录..."
remote "mkdir -p ${REMOTE_PATH}/config ${REMOTE_PATH}/config/_backup"
ok "目录已就绪"

# ── [3/7] 备份服务器上现有的配置文件 ──
info "[3/7] 备份服务器端配置文件..."
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
remote "
  cd ${REMOTE_PATH}
  for f in ${PRESERVE_CONFIGS[*]}; do
    if [ -f \"\$f\" ]; then
      cp \"\$f\" \"config/_backup/\$(basename \$f).bak_${TIMESTAMP}\"
      echo \"  备份: \$f\"
    fi
  done
  # 只保留最近 10 份备份
  ls -t config/_backup/*.bak_* 2>/dev/null | tail -n +40 | xargs rm -f 2>/dev/null || true
  echo '  备份完成'
"
ok "配置备份完成"

# ── [4/7] 上传代码（跳过配置文件目录，后续单独处理） ──
info "[4/7] 上传代码..."
upload_dir  "${LOCAL_BACKEND}/src"          "${REMOTE_PATH}/"
upload_dir  "${LOCAL_BACKEND}/public"       "${REMOTE_PATH}/"
upload_dir  "${LOCAL_BACKEND}/scripts"      "${REMOTE_PATH}/"
upload_file "${LOCAL_BACKEND}/package.json" "${REMOTE_PATH}/package.json"

# 上传 .env（如果本地存在）
if [ -f "${LOCAL_BACKEND}/.env" ]; then
  upload_file "${LOCAL_BACKEND}/.env" "${REMOTE_PATH}/.env"
  ok ".env 已上传"
fi

# eslint 等开发文件不上传
ok "代码上传完成"

# ── [5/7] 合并配置文件（服务器已有则保留，不存在则用本地默认值） ──
info "[5/7] 合并配置文件（保留服务器端已有配置）..."
for cfg in "${PRESERVE_CONFIGS[@]}"; do
  local_file="${LOCAL_BACKEND}/${cfg}"
  remote_file="${REMOTE_PATH}/${cfg}"

  # 检查服务器上是否已存在该配置
  if remote "test -f ${remote_file}" 2>/dev/null; then
    info "  ✓ 保留服务器端: ${cfg}"
  else
    # 服务器上不存在，上传本地默认配置
    if [ -f "${local_file}" ]; then
      upload_file "${local_file}" "${remote_file}"
      ok "  ↑ 上传默认配置: ${cfg}"
    else
      warn "  ✗ 本地与服务器均不存在: ${cfg}（服务启动时将使用内置默认值）"
    fi
  fi
done
ok "配置合并完成"

# ── [5.5/7] 修复 SVG 文件名编码（pscp/scp 日文文件名可能乱码） ──
info "[5.5/7] 修复 SVG 文件名编码..."
remote "
  which convmv >/dev/null 2>&1 || dnf install -y convmv >/dev/null 2>&1 || true
  cd ${REMOTE_PATH}/public/app/svg/kana/hiragana 2>/dev/null && convmv -f euc-jp -t utf-8 --notest *.svg 2>/dev/null || true
  cd ${REMOTE_PATH}/public/app/svg/kana/katakana 2>/dev/null && convmv -f euc-jp -t utf-8 --notest *.svg 2>/dev/null || true
  echo done
"
ok "SVG 编码修复完成"

# ── [6/7] 安装依赖 & 重启服务 ──
info "[6/7] 安装依赖..."
remote "cd ${REMOTE_PATH} && npm install --production 2>&1 | tail -5"
ok "依赖安装完成"

info "[6.5/7] 重启 PM2 服务..."
remote "
  cd ${REMOTE_PATH}
  pm2 restart japanese-learn 2>/dev/null || pm2 start src/app.js --name japanese-learn
  pm2 save --force
  echo '--- PM2 进程列表 ---'
  pm2 list
"
ok "服务已重启"

# ── [7/7] 验证 ──
info "[7/7] 验证服务..."
sleep 2
HTTP_CODE=$(remote "curl -s -o /dev/null -w '%{http_code}' http://localhost:8002/api/v1/sync/features" 2>/dev/null || echo "000")
if [ "${HTTP_CODE}" = "200" ]; then
  ok "API 响应正常 (HTTP ${HTTP_CODE})"
else
  warn "API 响应码: ${HTTP_CODE}（可能需要等待几秒启动）"
fi

# ── 显示当前服务器上配置文件状态 ──
echo ""
info "服务器端配置文件状态："
remote "
  cd ${REMOTE_PATH}
  for f in ${PRESERVE_CONFIGS[*]}; do
    if [ -f \"\$f\" ]; then
      sz=\$(wc -c < \"\$f\" | tr -d ' ')
      ts=\$(stat -c '%y' \"\$f\" 2>/dev/null || stat -f '%Sm' \"\$f\" 2>/dev/null)
      echo \"  ✓ \$f  (\${sz} bytes, \${ts})\"
    else
      echo \"  ✗ \$f  (不存在)\"
    fi
  done
"

echo ""
echo "═══════════════════════════════════════════════════════════"
ok "部署完成！"
echo "  API:   http://${SERVER_HOST}:8002/api/v1"
echo "  后台:  http://${SERVER_HOST}:8002/admin/"
echo "  Web:   http://${SERVER_HOST}:8002/app/"
echo "═══════════════════════════════════════════════════════════"
echo ""
