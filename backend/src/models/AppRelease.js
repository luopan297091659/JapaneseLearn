const { DataTypes } = require('sequelize');
const { sequelize } = require('../config/database');

const AppRelease = sequelize.define('AppRelease', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true,
  },
  version: {
    type: DataTypes.STRING,
    allowNull: false,
  },
  platform: {
    type: DataTypes.STRING,
    allowNull: false, // 'android' | 'ios'
  },
  file_url: {
    type: DataTypes.STRING,
    allowNull: false,
  },
  upload_time: {
    type: DataTypes.DATE,
    defaultValue: DataTypes.NOW,
  },
  download_count: {
    type: DataTypes.INTEGER,
    defaultValue: 0,
  },
  changelog: {
    type: DataTypes.TEXT,
    allowNull: true,
  },
});

module.exports = AppRelease;
