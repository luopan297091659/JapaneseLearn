const { DataTypes } = require('sequelize');
const { sequelize } = require('../config/database');

const PasswordResetCode = sequelize.define('PasswordResetCode', {
  id: { type: DataTypes.INTEGER, autoIncrement: true, primaryKey: true },
  email: { type: DataTypes.STRING(255), allowNull: false },
  code: { type: DataTypes.STRING(6), allowNull: false },
  expires_at: { type: DataTypes.DATE, allowNull: false },
  used: { type: DataTypes.BOOLEAN, defaultValue: false },
}, {
  tableName: 'password_reset_codes',
  indexes: [{ fields: ['email', 'code'] }],
});

module.exports = PasswordResetCode;
