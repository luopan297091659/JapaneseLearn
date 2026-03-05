const { Client: SSHClient } = require('ssh2');

const ssh = new SSHClient();
ssh.on('ready', () => {
  ssh.exec('pm2 logs japanese-learn --lines 50 --nostream 2>&1', (err, stream) => {
    stream.on('data', d => process.stdout.write(d.toString()));
    stream.stderr.on('data', d => process.stdout.write(d.toString()));
    stream.on('close', () => {
      // Also check app.js startup
      ssh.exec('cat /home/japanese-learn/backend/src/app.js', (e, s) => {
        s.on('data', d => process.stdout.write(d.toString()));
        s.on('close', () => ssh.end());
      });
    });
  });
}).connect({ host: '139.196.44.6', port: 22, username: 'root', password: 'Xiaoyun@123' });
