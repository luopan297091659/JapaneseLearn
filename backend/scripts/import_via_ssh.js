/**
 * 通过 SSH 隧道将 import_n1n5_data.sql 导入远程 MySQL
 * SSH 隧道: 本机 localhost:13306 → 服务器 127.0.0.1:3306
 * MySQL 连接到本机隧道端口，服务器端看到的来源是 127.0.0.1（即 localhost）
 *
 * 用法: node scripts/import_via_ssh.js
 *   环境变量（可覆盖默认值）:
 *     SSH_HOST   默认 139.196.44.6
 *     SSH_USER   默认 root
 *     SSH_PASS   默认读取 .env 的 SSH_PASSWORD，否则提示输入
 *     DB_USER    默认 root
 *     DB_PASS    默认读取 .env 的 DB_PASSWORD
 *     DB_NAME    默认 japanese_learn
 */

require('dotenv').config();
const { Client: SSHClient } = require('ssh2');
const mysql = require('mysql2/promise');
const fs = require('fs');
const path = require('path');
const net = require('net');
const readline = require('readline');

const SSH_HOST = process.env.SSH_HOST || '139.196.44.6';
const SSH_PORT = parseInt(process.env.SSH_PORT || '22');
const SSH_USER = process.env.SSH_USER || 'root';
const LOCAL_TUNNEL_PORT = 13306; // 本机临时监听端口

const DB_USER = process.env.DB_USER || 'root';
const DB_PASS = process.env.DB_PASSWORD || '';
const DB_NAME = process.env.DB_NAME || 'japanese_learn';

const SQL_FILE = path.join(__dirname, '../database/seeds/import_n1n5_data.sql');

// ── 辅助: 密码输入 ────────────────────────────────────────────────────────────
function askPassword(prompt) {
  return new Promise(resolve => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    process.stdout.write(prompt);
    process.stdin.setRawMode && process.stdin.setRawMode(true);
    let pwd = '';
    process.stdin.resume();
    process.stdin.setEncoding('utf8');
    const handler = (char) => {
      if (char === '\n' || char === '\r' || char === '\u0004') {
        process.stdin.setRawMode && process.stdin.setRawMode(false);
        process.stdout.write('\n');
        process.stdin.removeListener('data', handler);
        rl.close();
        resolve(pwd);
      } else if (char === '\u0003') {
        process.exit();
      } else if (char === '\u007f') {
        pwd = pwd.slice(0, -1);
      } else {
        pwd += char;
      }
    };
    process.stdin.on('data', handler);
  });
}

// ── 辅助: 建立 SSH 隧道（本地 TCP 服务器转发到远端） ─────────────────────────
function createTunnel(sshConn, localPort, remoteHost, remotePort) {
  return new Promise((resolve, reject) => {
    const server = net.createServer(socket => {
      sshConn.forwardOut(
        '127.0.0.1', localPort,
        remoteHost, remotePort,
        (err, stream) => {
          if (err) { socket.destroy(); return; }
          socket.pipe(stream).pipe(socket);
          socket.on('close', () => stream.close && stream.close());
        }
      );
    });
    server.listen(localPort, '127.0.0.1', () => resolve(server));
    server.on('error', reject);
  });
}

// ── 辅助: 拆分 SQL 文件为语句数组 ────────────────────────────────────────────
function splitSQL(sql) {
  const statements = [];
  let current = '';
  let inString = false;
  let stringChar = '';

  for (let i = 0; i < sql.length; i++) {
    const ch = sql[i];
    if (inString) {
      current += ch;
      if (ch === stringChar && sql[i - 1] !== '\\') inString = false;
    } else if (ch === "'" || ch === '"' || ch === '`') {
      inString = true;
      stringChar = ch;
      current += ch;
    } else if (ch === ';') {
      const stmt = current.trim();
      if (stmt) statements.push(stmt);
      current = '';
    } else {
      current += ch;
    }
  }
  const last = current.trim();
  if (last) statements.push(last);
  return statements.filter(s => s.length > 0 && !s.startsWith('--'));
}

// ── 主流程 ────────────────────────────────────────────────────────────────────
async function main() {
  // 1. 读取 SQL 文件
  if (!fs.existsSync(SQL_FILE)) {
    console.error(`❌ SQL 文件不存在: ${SQL_FILE}`);
    console.error('   请先运行: node scripts/generate_import_sql.js');
    process.exit(1);
  }
  console.log(`📄 读取 SQL 文件: ${SQL_FILE}`);
  const sqlContent = fs.readFileSync(SQL_FILE, 'utf8');
  const statements = splitSQL(sqlContent);
  console.log(`   共解析 ${statements.length} 条语句`);

  // 2. 获取 SSH 密码
  let sshPass = process.env.SSH_PASSWORD || DB_PASS; // 通常和 DB 密码相同
  if (!sshPass) {
    sshPass = await askPassword(`🔑 SSH 密码 (${SSH_USER}@${SSH_HOST}): `);
  } else {
    console.log(`🔑 使用 .env 中的密码连接 SSH...`);
  }

  // 3. 建立 SSH 连接
  const ssh = new SSHClient();
  await new Promise((resolve, reject) => {
    ssh.on('ready', resolve).on('error', reject).connect({
      host: SSH_HOST,
      port: SSH_PORT,
      username: SSH_USER,
      password: sshPass,
      readyTimeout: 15000,
    });
  });
  console.log(`✅ SSH 已连接: ${SSH_USER}@${SSH_HOST}`);

  // 4. 建立本地 TCP 隧道 → 远端 MySQL
  const tunnelServer = await createTunnel(ssh, LOCAL_TUNNEL_PORT, '127.0.0.1', 3306);
  console.log(`✅ SSH 隧道已建立: localhost:${LOCAL_TUNNEL_PORT} → ${SSH_HOST}:3306`);

  // 5. 连接 MySQL（通过隧道）
  const db = await mysql.createConnection({
    host: '127.0.0.1',
    port: LOCAL_TUNNEL_PORT,
    user: DB_USER,
    password: DB_PASS,
    database: DB_NAME,
    multipleStatements: false,
    connectTimeout: 15000,
  });
  console.log(`✅ MySQL 已连接: ${DB_USER}@${DB_NAME}\n`);

  // 6. 逐条执行 SQL 语句
  let ok = 0, skip = 0, err = 0;
  const total = statements.length;
  const startTime = Date.now();

  for (let i = 0; i < statements.length; i++) {
    const stmt = statements[i];
    // 跳过纯注释和 USE / SET 语句（可选：USE 仍执行）
    if (stmt.startsWith('/*') || stmt.startsWith('--')) { skip++; continue; }

    try {
      await db.query(stmt);
      ok++;
    } catch (e) {
      // ER_DUP_ENTRY (1062) 和 INSERT IGNORE 不会到这，其他错误记录
      if (e.errno !== 1062) {
        console.error(`\n⚠️  语句 #${i + 1} 错误 (${e.errno}): ${e.sqlMessage}`);
        console.error(`   SQL: ${stmt.substring(0, 80)}...`);
        err++;
      } else {
        skip++;
      }
    }

    // 进度显示
    if ((i + 1) % 500 === 0 || i + 1 === total) {
      const pct = (((i + 1) / total) * 100).toFixed(1);
      const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
      process.stdout.write(`\r   进度: ${i + 1}/${total} (${pct}%) ✓${ok} ⊘${skip} ✗${err}  ${elapsed}s  `);
    }
  }

  console.log('\n');
  console.log(`✅ 导入完成!`);
  console.log(`   成功: ${ok} 条`);
  console.log(`   跳过: ${skip} 条`);
  console.log(`   错误: ${err} 条`);
  console.log(`   耗时: ${((Date.now() - startTime) / 1000).toFixed(1)}s`);

  // 7. 验证数量
  const [[vocabCount]] = await db.query('SELECT COUNT(*) as cnt FROM vocabulary');
  const [[grammarCount]] = await db.query('SELECT COUNT(*) as cnt FROM grammar_lessons');
  console.log(`\n📊 数据库状态:`);
  console.log(`   vocabulary 表: ${vocabCount.cnt} 条`);
  console.log(`   grammar_lessons 表: ${grammarCount.cnt} 条`);

  await db.end();
  tunnelServer.close();
  ssh.end();
  process.exit(0);
}

main().catch(async e => {
  console.error('\n❌ 导入失败:', e.message);
  process.exit(1);
});
