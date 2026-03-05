require('dotenv').config();
const { Client: SSHClient } = require('ssh2');

const ssh = new SSHClient();
ssh.on('ready', () => {
  const DB_PASS = '6586156';
  const DB = 'japanese_learn';

  // 先查一下有多少条含 ! 的记录
  ssh.exec(
    `mariadb -u root -p'${DB_PASS}' ${DB} -e ` +
    `"SELECT COUNT(*) AS before_count FROM vocabulary WHERE word LIKE '%!%' OR reading LIKE '%!%';" 2>&1`,
    (e, s) => {
      s.on('data', d => process.stdout.write(d.toString()));
      s.on('close', () => {
        // 执行清除
        ssh.exec(
          `mariadb -u root -p'${DB_PASS}' ${DB} -e ` +
          `"UPDATE vocabulary SET word=REPLACE(word,'!',''), reading=REPLACE(reading,'!','') ` +
          `WHERE word LIKE '%!%' OR reading LIKE '%!%'; ` +
          `SELECT ROW_COUNT() AS updated_rows;" 2>&1`,
          (e2, s2) => {
            s2.on('data', d => process.stdout.write(d.toString()));
            s2.on('close', () => {
              // 同样清除 meaning_zh / example_sentence 里的 !（如果有）
              ssh.exec(
                `mariadb -u root -p'${DB_PASS}' ${DB} -e ` +
                `"SELECT COUNT(*) FROM vocabulary WHERE word LIKE '%!%' OR reading LIKE '%!%';" 2>&1`,
                (e3, s3) => {
                  s3.on('data', d => process.stdout.write(d.toString()));
                  s3.on('close', () => { console.log('\n✅ 完成'); ssh.end(); });
                }
              );
            });
          }
        );
      });
    }
  );
}).connect({ host: '139.196.44.6', port: 22, username: 'root', password: 'Xiaoyun@123' });
