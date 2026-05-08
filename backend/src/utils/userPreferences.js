const DEFAULT_USER_PREFERENCES = Object.freeze({
  locale: 'zh',
  appearance_mode: 'classic',
  slow_speed: 0.5,
  notification_enabled: true,
  daily_goal_minutes: 15,
});

function clampNumber(value, min, max, fallback) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return fallback;
  return Math.min(max, Math.max(min, numeric));
}

function parsePreferenceJson(raw) {
  if (!raw) return {};
  try {
    const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch (_err) {
    return {};
  }
}

function normalizeUserPreferences(input = {}, user = null) {
  const locale = ['zh', 'en', 'ja'].includes(input.locale) ? input.locale : DEFAULT_USER_PREFERENCES.locale;
  const appearanceMode = ['classic', 'anime', 'sakura'].includes(input.appearance_mode)
    ? input.appearance_mode
    : DEFAULT_USER_PREFERENCES.appearance_mode;

  const notificationEnabled = input.notification_enabled !== undefined
    ? input.notification_enabled === true
    : user?.notification_enabled ?? DEFAULT_USER_PREFERENCES.notification_enabled;

  const dailyGoalMinutes = Math.round(clampNumber(
    input.daily_goal_minutes ?? user?.daily_goal_minutes,
    5,
    240,
    DEFAULT_USER_PREFERENCES.daily_goal_minutes,
  ));

  const slowSpeed = Math.round(clampNumber(
    input.slow_speed,
    0.2,
    0.8,
    DEFAULT_USER_PREFERENCES.slow_speed,
  ) * 100) / 100;

  return {
    locale,
    appearance_mode: appearanceMode,
    slow_speed: slowSpeed,
    notification_enabled: notificationEnabled,
    daily_goal_minutes: dailyGoalMinutes,
  };
}

function getUserPreferences(user) {
  const parsed = parsePreferenceJson(user?.preferences_json);
  return normalizeUserPreferences(parsed, user);
}

function mergeUserPreferences(user, overrides = {}) {
  return normalizeUserPreferences({
    ...getUserPreferences(user),
    ...(overrides && typeof overrides === 'object' ? overrides : {}),
  }, user);
}

function serializeUserPreferences(preferences) {
  return JSON.stringify(normalizeUserPreferences(preferences));
}

function summarizeUserPreferences(preferences) {
  const pref = normalizeUserPreferences(preferences);
  const localeLabel = { zh: '中文', en: 'English', ja: '日本語' }[pref.locale] || pref.locale;
  const appearanceLabel = { anime: '蓝调', sakura: '樱花', classic: '经典' }[pref.appearance_mode] || '经典';
  const notificationLabel = pref.notification_enabled ? '通知开' : '通知关';
  return `${localeLabel} / ${appearanceLabel} / ${pref.slow_speed}x / ${pref.daily_goal_minutes}分 / ${notificationLabel}`;
}

module.exports = {
  DEFAULT_USER_PREFERENCES,
  parsePreferenceJson,
  normalizeUserPreferences,
  getUserPreferences,
  mergeUserPreferences,
  serializeUserPreferences,
  summarizeUserPreferences,
};
