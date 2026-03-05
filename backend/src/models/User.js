const { DataTypes } = require('sequelize');
const { sequelize } = require('../config/database');
const bcrypt = require('bcryptjs');

const User = sequelize.define('User', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  username: { type: DataTypes.STRING(50), allowNull: false, unique: true },
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
  notification_enabled: { type: DataTypes.BOOLEAN, defaultValue: true },
  daily_goal_minutes: { type: DataTypes.INTEGER, defaultValue: 15 },
}, {
  tableName: 'users',
  hooks: {
    beforeCreate: async (user) => {
      user.password_hash = await bcrypt.hash(user.password_hash, 12);
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
  delete values.password_hash;
  return values;
};

module.exports = User;
