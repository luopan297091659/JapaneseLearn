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
    if (label) console.log(`\n[${label}] $ ${cmd}`);
    ssh.exec(cmd, (err, stream) => {
      if (err) return reject(err);
      let out = '';
      stream.on('data', d => { out += d; process.stdout.write(d.toString()); });
      stream.stderr.on('data', d => { out += d; process.stderr.write(d.toString()); });
      stream.on('close', code => resolve({ code, out }));
    });
  });
}

async function main() {
  const ssh = new SSHClient();
  await sshConnect(ssh);
  console.log('SSH connected\n');

  // 检查 MariaDB 用户认证插件
  await sshExec(ssh,
    `mariadb -u root -e "SELECT user, host, plugin, authentication_string FROM mysql.user;" 2>&1`,
    'MariaDB用户列表(无密码)');

  // 检查 /etc/mysql 配置目录
  await sshExec(ssh, 'ls /etc/mysql/ 2>/dev/null && cat /etc/mysql/debian.cnf 2>/dev/null || echo "no debian.cnf"', 'debian.cnf');

  // 查看 MariaDB 日志最后几行（有无 root 密码设置记录）
  await sshExec(ssh, 'find /var/log -name "*.err" 2>/dev/null | head -2 | xargs ls -la 2>/dev/null', '错误日志');

  // 检查 app .env 或 backend 部署路径上的配置
  await sshExec(ssh, 'find /home /root /opt /var/www -name ".env" 2>/dev/null | head -10', '已部署.env');
  await sshExec(ssh, 'cat /home/japanese-learn/backend/.env 2>/dev/null || echo "no .env"', '后端.env');

  ssh.end();
}

main().catch(e => console.error('失败:', e.message));
