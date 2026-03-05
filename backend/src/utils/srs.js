/**
 * SM-2 Spaced Repetition Algorithm
 * quality: 0-5 (0=blackout, 3=hard, 4=good, 5=easy)
 */
function sm2(card, quality) {
  let { repetitions, ease_factor, interval_days } = card;

  if (quality >= 3) {
    if (repetitions === 0) interval_days = 1;
    else if (repetitions === 1) interval_days = 6;
    else interval_days = Math.round(interval_days * ease_factor);

    repetitions += 1;
  } else {
    repetitions = 0;
    interval_days = 1;
  }

  ease_factor = Math.max(1.3, ease_factor + 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));

  const due_date = new Date();
  due_date.setDate(due_date.getDate() + interval_days);

  return {
    repetitions,
    ease_factor,
    interval_days,
    due_date: due_date.toISOString().split('T')[0],
    last_reviewed_at: new Date(),
    is_graduated: repetitions >= 3 && interval_days >= 21,
  };
}

module.exports = { sm2 };
