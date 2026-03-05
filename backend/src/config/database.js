const { Sequelize } = require('sequelize');
const logger = require('../utils/logger');

const sequelize = new Sequelize(
  process.env.DB_NAME || 'japanese_learn',
  process.env.DB_USER || 'root',
  process.env.DB_PASSWORD || '',
  {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT) || 3306,
    dialect: 'mysql',
    // 告知 MySQL 连接器以东京时间（JST, UTC+9）读写 DATETIME / TIMESTAMP 字段
    timezone: '+09:00',
    dialectOptions: {
      timezone: '+09:00',
    },
    logging: (msg) => logger.debug(msg),
    pool: {
      max: 10,
      min: 0,
      acquire: 30000,
      idle: 10000,
    },
    define: {
      timestamps: true,
      underscored: true,
    },
  }
);

module.exports = { sequelize, Sequelize };
