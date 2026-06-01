const SESSION_PLATFORMS = {
  web: {
    tokenPlatform: 'web',
    loginTokenField: 'web_login_token',
  },
  app: {
    tokenPlatform: 'app',
    loginTokenField: 'app_login_token',
  },
  kotabi_app: {
    tokenPlatform: 'app',
    loginTokenField: 'app_login_token',
  },
  japanese_learn_app: {
    tokenPlatform: 'app',
    loginTokenField: 'app_login_token',
  },
  tokyo_app: {
    tokenPlatform: 'tokyo_app',
    loginTokenField: 'tokyo_app_login_token',
  },
  life_app: {
    tokenPlatform: 'tokyo_app',
    loginTokenField: 'tokyo_app_login_token',
  },
  japanese_life_simulator: {
    tokenPlatform: 'tokyo_app',
    loginTokenField: 'tokyo_app_login_token',
  },
};

function normalizeSessionPlatform(value) {
  const key = String(value || 'web').trim().toLowerCase();
  return SESSION_PLATFORMS[key] || SESSION_PLATFORMS.web;
}

module.exports = {
  normalizeSessionPlatform,
};
