require('dotenv').config();
const { Client: SSHClient } = require('ssh2');
const fs = require('fs');
const path = require('path');

const SSH_HOST  = '139.196.44.6';
const SSH_PORT  = 22;
const SSH_USER  = 'root';
const SSH_PASS  = 'Xiaoyun@123';
const DB_PASS   = '6586156';
const DB_NAME   = 'japanese_learn';
const SQL_FILE  = path.join(__dirname, '../database/seeds/import_n4_vocab.sql');
const REMOTE_SQL = '/tmp/import_n4_vocab.sql';
const REMOTE_PKG = '/home/japanese-learn/backend/package.json';
const LOCAL_PKG  = path.join(__dirname, '../package.json');

function sshConnect(ssh) {
  return new Promise((resolve, reject) => {
    ssh.on('ready', resolve).on('error', reject).connect({
      host: SSH_HOST, port: SSH_PORT,
      username: SSH_USER, password: SSH_PASS,
      readyTimeout: 20000,
    });
  });
}

function sshExec(ssh, cmd, label) {
  return new Promise((resolve, reject) => {
    if (label) console.log(`\n[${label}]`);
    ssh.exec(cmd, (err, stream) => {
      if (err) return reject(err);
      let out = '';
      stream.on('data', d => { out += d; process.stdout.write(d.toString()); });
      stream.stderr.on('data', d => { out += d; process.stderr.write(d.toString()); });
      stream.on('close', code => resolve({ code, out }));
    });
  });
}

function sftpUpload(ssh, localPath, remotePath, label) {
  return new Promise((resolve, reject) => {
    ssh.sftp((err, sftp) => {
      if (err) return reject(err);
      const readStream  = fs.createReadStream(localPath);
      const writeStream = sftp.createWriteStream(remotePath);
      const total = fs.statSync(localPath).size;
      let uploaded = 0;
      if (label) process.stdout.write(`📤 上传 ${label}...`);
      readStream.on('data', chunk => {
        uploaded += chunk.length;
        process.stdout.write(`\r📤 ${label}: ${(uploaded/1024).toFixed(0)}/${(total/1024).toFixed(0)} KB  `);
      });
      writeStream.on('close', () => { console.log(' ✅'); sftp.end(); resolve(); });
      writeStream.on('error', reject);
      readStream.pipe(writeStream);
    });
  });
}

async function main() {
  const ssh = new SSHClient();
  console.log(`🔌 连接 SSH...`);
  await sshConnect(ssh);
  console.log('✅ 已连接\n');

  // 1. 上传 N4 SQL
  await sftpUpload(ssh, SQL_FILE, REMOTE_SQL, 'N4词汇SQL');

  // 2. 执行 N4 SQL 导入
  console.log('\n🚀 导入 N4 词汇...');
  const r1 = await sshExec(ssh,
    `bash -c "mariadb -u root -p'${DB_PASS}' ${DB_NAME} < '${REMOTE_SQL}' 2>&1 && echo __OK__"`
  );
  if (!r1.out.includes('__OK__')) {
    console.error('\n❌ N4 导入失败'); ssh.end(); process.exit(1);
  }

  // 3. 上传新 package.json（含 adm-zip）
  await sftpUpload(ssh, LOCAL_PKG, REMOTE_PKG, 'package.json');

  // 4. 在服务器安装 adm-zip
  console.log('\n📦 安装 adm-zip...');
  await sshExec(ssh,
    `cd /home/japanese-learn/backend && npm install --production 2>&1 | grep -E "(added|found|error|adm)" || true`
  );

  // 5. 重启 PM2
  console.log('\n🔄 重启 japanese-learn...');
  await sshExec(ssh, 'pm2 restart japanese-learn && pm2 list');

  // 6. 验证
  console.log('\n📊 验证数据...');
  await sshExec(ssh,
    `mariadb -u root -p'${DB_PASS}' ${DB_NAME} -e ` +
    `"SELECT jlpt_level, COUNT(*) cnt FROM vocabulary GROUP BY jlpt_level ORDER BY jlpt_level;" 2>&1`
  );

  // 7. 清理
  await sshExec(ssh, `rm -f '${REMOTE_SQL}'`);

  console.log('\n✅ 全部完成!');
  ssh.end();
  process.exit(0);
}

main().catch(e => {
  console.error('\n❌ 失败:', e.message);
  process.exit(1);
});
