const { DataTypes } = require('sequelize');
const { sequelize } = require('../config/database');
const bcrypt = require('bcryptjs');
const {
  getUserPreferences,
  summarizeUserPreferences,
  serializeUserPreferences,
} = require('../utils/userPreferences');

const User = sequelize.define('User', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  username: { type: DataTypes.STRING(50), allowNull: false },
  email: { type: DataTypes.STRING(255), allowNull: false, unique: true, validate: { isEmail: true } },
  password_hash: { type: DataTypes.STRING(255), allowNull: false },
  avatar_url: { type: DataTypes.STRING(500), allowNull: true },
  level: {
    type: DataTypes.ENUM('N5', 'N4', 'N3', 'N2', 'N1'),
    defaultValue: 'N5',
  },
  streak_days: { type: DataTypes.INTEGER, defaultValue: 0 },
  total_study_minutes: { type: DataTypes.INTEGER, defaultValue: 0 },
  last_study_date: { type: DataTypes.DATEONLY, allowNull: true },
  is_active: { type: DataTypes.BOOLEAN, defaultValue: true },
  role: { type: DataTypes.ENUM('user', 'admin'), defaultValue: 'user' },
  admin_level: { type: DataTypes.ENUM('super_admin', 'admin'), allowNull: true, defaultValue: null },
  permissions: { type: DataTypes.TEXT, allowNull: true, defaultValue: null },
  membership_plan: { type: DataTypes.STRING(50), allowNull: true, defaultValue: null },
  membership_expire: { type: DataTypes.DATE, allowNull: true, defaultValue: null },
  trial_activated: { type: DataTypes.BOOLEAN, defaultValue: false },
  notification_enabled: { type: DataTypes.BOOLEAN, defaultValue: true },
  daily_goal_minutes: { type: DataTypes.INTEGER, defaultValue: 15 },
  preferences_json: {
    type: DataTypes.TEXT,
    allowNull: false,
    defaultValue: serializeUserPreferences(),
  },
  web_login_token: { type: DataTypes.STRING(36), allowNull: true },
  app_login_token: { type: DataTypes.STRING(36), allowNull: true },
  tokyo_app_login_token: { type: DataTypes.STRING(36), allowNull: true },
  invite_code: { type: DataTypes.STRING(8), allowNull: true, unique: true },
  invited_by: { type: DataTypes.UUID, allowNull: true },
}, {
  tableName: 'users',
  hooks: {
    beforeCreate: async (user) => {
      user.password_hash = await bcrypt.hash(user.password_hash, 12);
      // 自动生成唯一邀请码
      if (!user.invite_code) {
        user.invite_code = require('crypto').randomBytes(4).toString('hex').toUpperCase();
      }
    },
    beforeUpdate: async (user) => {
      if (user.changed('password_hash')) {
        user.password_hash = await bcrypt.hash(user.password_hash, 12);
      }
    },
  },
});

User.prototype.validatePassword = async function (password) {
  return bcrypt.compare(password, this.password_hash);
};

User.prototype.toJSON = function () {
  const values = { ...this.get() };
  values.preferences = getUserPreferences(values);
  values.preference_summary = summarizeUserPreferences(values.preferences);
  delete values.preferences_json;
  delete values.password_hash;
  delete values.web_login_token;
  delete values.app_login_token;
  delete values.tokyo_app_login_token;
  return values;
};

module.exports = User;
