require('dotenv').config();
const { Client: SSHClient } = require('ssh2');
const fs = require('fs');
const path = require('path');

const SSH_HOST = '139.196.44.6';
const SSH_PORT = 22;
const SSH_USER = 'root';
const SSH_PASS = 'Xiaoyun@123';        // SSH 登录密码
const DB_PASS  = '6586156';            // MariaDB root 密码（从服务器 .env 获取）
const DB_NAME  = 'japanese_learn';
const REMOTE_PATH = '/tmp/japanese_learn_import.sql';
const SQL_FILE = path.join(__dirname, '../database/seeds/import_n1n5_data.sql');

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
        process.stdout.write(`\r   上传: ${(uploaded/1024/1024).toFixed(2)}/${(total/1024/1024).toFixed(2)} MB (${((uploaded/total)*100).toFixed(1)}%)  `);
      });
      writeStream.on('close', () => { console.log(''); sftp.end(); resolve(); });
      writeStream.on('error', reject);
      readStream.pipe(writeStream);
    });
  });
}

async function main() {
  const ssh = new SSHClient();
  console.log(`🔌 连接 SSH ${SSH_USER}@${SSH_HOST}...`);
  await sshConnect(ssh);
  console.log('✅ SSH 已连接\n');

  // 1. 上传 SQL 文件
  console.log(`📤 上传 SQL 文件...`);
  await sftpUpload(ssh, SQL_FILE, REMOTE_PATH);
  console.log('✅ 上传完成\n');

  // 2. 在服务器执行 mysql 导入（使用正确密码）
  // 注意：exec 的命令中 < 是服务器端 shell 解析的，不受 PowerShell 影响
  console.log(`🚀 执行 MariaDB 导入 (密码: ${DB_PASS})...`);
  const importCmd = `bash -c "mariadb -u root -p'${DB_PASS}' ${DB_NAME} < '${REMOTE_PATH}' 2>&1 && echo __IMPORT_OK__"`;
  const result = await sshExec(ssh, importCmd);
  console.log('');

  if (!result.out.includes('__IMPORT_OK__')) {
    console.error('❌ 导入失败');
    // 尝试无密码
    console.log('尝试无密码...');
    const result2 = await sshExec(ssh, `bash -c "mariadb -u root ${DB_NAME} < '${REMOTE_PATH}' 2>&1 && echo __IMPORT_OK__"`);
    if (!result2.out.includes('__IMPORT_OK__')) {
      ssh.end(); process.exit(1);
    }
  }

  // 3. 验证
  console.log('\n📊 验证导入结果...');
  await sshExec(ssh, `bash -c "mariadb -u root -p'${DB_PASS}' ${DB_NAME} -e \\"SELECT 'vocabulary' tbl, COUNT(*) cnt FROM vocabulary UNION ALL SELECT 'grammar_lessons', COUNT(*) FROM grammar_lessons;\\" 2>&1"`, '数量统计');

  // 4. 清理
  await sshExec(ssh, `rm -f '${REMOTE_PATH}'`);

  console.log('\n✅ 数据导入完成!');
  ssh.end();
  process.exit(0);
}

main().catch(e => {
  console.error('\n❌ 失败:', e.message);
  process.exit(1);
});
