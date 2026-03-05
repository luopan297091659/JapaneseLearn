/**
 * 通过 SSH 将 SQL 文件上传到服务器，直接用服务器的 mysql CLI 执行
 * 服务器上 mysql -u root -p 连接的是 localhost (unix socket)，权限无问题
 *
 * 用法: node scripts/import_via_ssh_exec.js
 */

require('dotenv').config();
const { Client: SSHClient } = require('ssh2');
const fs = require('fs');
const path = require('path');

const SSH_HOST = process.env.SSH_HOST || '139.196.44.6';
const SSH_PORT = parseInt(process.env.SSH_PORT || '22');
const SSH_USER = process.env.SSH_USER || 'root';
const SSH_PASS = process.env.SSH_PASSWORD || process.env.DB_PASSWORD || '';
const DB_PASS  = process.env.DB_PASSWORD || '';
const DB_NAME  = process.env.DB_NAME || 'japanese_learn';

const SQL_FILE    = path.join(__dirname, '../database/seeds/import_n1n5_data.sql');
const REMOTE_PATH = '/tmp/japanese_learn_import.sql';

// ── 工具函数 ─────────────────────────────────────────────────────────────────

function sshConnect(ssh) {
  return new Promise((resolve, reject) => {
    ssh.on('ready', resolve).on('error', reject).connect({
      host: SSH_HOST, port: SSH_PORT,
      username: SSH_USER, password: SSH_PASS,
      readyTimeout: 20000,
    });
  });
}

function sshExec(ssh, cmd) {
  return new Promise((resolve, reject) => {
    ssh.exec(cmd, (err, stream) => {
      if (err) return reject(err);
      let stdout = '', stderr = '';
      stream.on('data', d => { stdout += d; process.stdout.write(d.toString()); });
      stream.stderr.on('data', d => { stderr += d; process.stderr.write(d.toString()); });
      stream.on('close', (code) => resolve({ code, stdout, stderr }));
    });
  });
}

function sftpUpload(ssh, localPath, remotePath) {
  return new Promise((resolve, reject) => {
    ssh.sftp((err, sftp) => {
      if (err) return reject(err);
      const readStream  = fs.createReadStream(localPath);
      const writeStream = sftp.createWriteStream(remotePath);
      const total = fs.statSync(localPath).size;
      let uploaded = 0;
      readStream.on('data', chunk => {
        uploaded += chunk.length;
        const pct = ((uploaded / total) * 100).toFixed(1);
        process.stdout.write(`\r   上传进度: ${(uploaded/1024/1024).toFixed(2)}MB / ${(total/1024/1024).toFixed(2)}MB (${pct}%)  `);
      });
      writeStream.on('close', () => { console.log('\n'); sftp.end(); resolve(); });
      writeStream.on('error', reject);
      readStream.pipe(writeStream);
    });
  });
}

// ── 主流程 ────────────────────────────────────────────────────────────────────
async function main() {
  if (!fs.existsSync(SQL_FILE)) {
    console.error(`❌ SQL 文件不存在: ${SQL_FILE}`);
    process.exit(1);
  }

  const fileSizeMB = (fs.statSync(SQL_FILE).size / 1024 / 1024).toFixed(2);
  console.log(`📄 SQL 文件: ${SQL_FILE} (${fileSizeMB} MB)`);

  const ssh = new SSHClient();

  // 1. SSH 连接
  console.log(`🔌 连接 SSH: ${SSH_USER}@${SSH_HOST}:${SSH_PORT} ...`);
  await sshConnect(ssh);
  console.log(`✅ SSH 已连接\n`);

  // 2. 检查服务器上是否有 mysql CLI
  console.log(`🔍 检查服务器 mysql CLI...`);
  const check = await sshExec(ssh, 'which mysql || echo NOT_FOUND');
  if (check.stdout.includes('NOT_FOUND')) {
    console.error('❌ 服务器未安装 mysql CLI');
    ssh.end(); process.exit(1);
  }
  console.log('');

  // 3. SFTP 上传 SQL 文件
  console.log(`📤 上传 SQL 文件到服务器 ${REMOTE_PATH} ...`);
  await sftpUpload(ssh, SQL_FILE, REMOTE_PATH);
  console.log(`✅ 上传完成\n`);

  // 4. 在服务器执行 mysql 导入
  // 先尝试 auth_socket（无密码），Ubuntu 默认 root 使用此方式
  // 若失败再尝试密码认证
  console.log(`🚀 在服务器执行 MySQL 导入...`);
  let importResult = await sshExec(ssh,
    `mysql -u root ${DB_NAME} < ${REMOTE_PATH} 2>&1 && echo __IMPORT_OK__`
  );
  if (!importResult.stdout.includes('__IMPORT_OK__')) {
    console.log('\n   auth_socket 失败，尝试密码认证...');
    importResult = await sshExec(ssh,
      `mysql -u root -p'${DB_PASS}' ${DB_NAME} < ${REMOTE_PATH} 2>&1 && echo __IMPORT_OK__`
    );
  }
  console.log('');

  if (!importResult.stdout.includes('__IMPORT_OK__')) {
    console.error(`❌ mysql 执行失败`);
    ssh.end(); process.exit(1);
  }

  // 5. 验证数量
  console.log(`📊 验证导入结果...`);
  const verifyCmd = `mysql -u root ${DB_NAME} -e "SELECT 'vocabulary' as tbl, COUNT(*) as cnt FROM vocabulary UNION ALL SELECT 'grammar_lessons', COUNT(*) FROM grammar_lessons;" 2>/dev/null || ` +
    `mysql -u root -p'${DB_PASS}' ${DB_NAME} -e "SELECT 'vocabulary' as tbl, COUNT(*) as cnt FROM vocabulary UNION ALL SELECT 'grammar_lessons', COUNT(*) FROM grammar_lessons;" 2>&1`;
  await sshExec(ssh, verifyCmd);

  // 6. 清理临时文件
  await sshExec(ssh, `rm -f ${REMOTE_PATH}`);

  console.log('\n✅ 数据导入完成!');
  ssh.end();
  process.exit(0);
}

main().catch(e => {
  console.error('\n❌ 失败:', e.message);
  process.exit(1);
});
