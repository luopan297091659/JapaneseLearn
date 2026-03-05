// 一次性迁移脚本：给 game_scores 加 base_speed_ms 列
const { sequelize } = require('../src/config/database');
sequelize.query('ALTER TABLE game_scores ADD COLUMN IF NOT EXISTS base_speed_ms INT DEFAULT 2000')
  .then(() => { console.log('[OK] base_speed_ms column added (or already exists)'); })
  .catch(e => { console.log('[Note]', e.message); })
  .finally(() => sequelize.close());
