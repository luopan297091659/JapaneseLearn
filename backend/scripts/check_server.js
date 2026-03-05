require('dotenv').config();
const { Client: SSHClient } = require('ssh2');

const SSH_HOST = process.env.SSH_HOST || '139.196.44.6';
const SSH_PORT = parseInt(process.env.SSH_PORT || '22');
const SSH_USER = process.env.SSH_USER || 'root';
const SSH_PASS = process.env.SSH_PASSWORD || process.env.DB_PASSWORD || '';

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
      stream.stderr.on('data', d => { out += d; process.stderr.write(`stderr: ${d}`); });
      stream.on('close', code => resolve({ code, out }));
    });
  });
}

async function main() {
  const ssh = new SSHClient();
  console.log(`连接 SSH: ${SSH_USER}@${SSH_HOST}...`);
  await sshConnect(ssh);
  console.log('已连接\n');

  // 检查 MySQL 是否在 Docker 或直接运行
  await sshExec(ssh, 'ps aux | grep -E "(mysql|docker)" | grep -v grep', 'MySQL进程');
  await sshExec(ssh, 'docker ps 2>/dev/null || echo "no docker"', 'Docker容器');
  await sshExec(ssh, 'netstat -tlnp 2>/dev/null | grep 3306 || ss -tlnp | grep 3306', 'MySQL端口');
  await sshExec(ssh, 'cat /etc/mysql/mysql.conf.d/mysqld.cnf 2>/dev/null | grep -E "(bind|user|skip)" || echo "no config"', 'MySQL配置');
  // 不使用密码，直接通过 mariadb 或 mysql 系统认证
  await sshExec(ssh, 'mysql --version 2>&1; mariadb --version 2>&1', 'MySQL版本');

  ssh.end();
}

main().catch(e => console.error('失败:', e.message));
