require('dotenv').config();
const { Client: SSHClient } = require('ssh2');

const SSH_HOST = '139.196.44.6';
const SSH_PORT = 22;
const SSH_USER = 'root';
const SSH_PASS = 'Xiaoyun@123';

function sshConnect(ssh) {
  return new Promise((resolve, reject) => {
    ssh.on('ready', resolve).on('error', reject).connect({
      host: SSH_HOST, port: SSH_PORT,
      username: SSH_USER, password: SSH_PASS,
      readyTimeout: 15000,
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

async function main() {
  const ssh = new SSHClient();
  await sshConnect(ssh);
  console.log('SSH connected\n');

  await sshExec(ssh, 'pm2 list 2>&1', 'PM2进程列表');
  await sshExec(ssh, 'ls -la /home/japanese-learn/backend/src/ 2>/dev/null || echo "no src"', '后端src目录');
  await sshExec(ssh, 'ls -la /home/japanese-learn/backend/ 2>/dev/null', '后端根目录');
  await sshExec(ssh, 'node --version 2>&1; npm --version 2>&1', 'Node/npm版本');

  ssh.end();
}

main().catch(e => console.error('失败:', e.message));
