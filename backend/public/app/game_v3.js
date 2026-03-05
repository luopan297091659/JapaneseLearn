// ══════════════════════════════════════════════════════════════════
//  GAME v3 (助词方块 · 闯关模式)  up to 30 levels, leaderboard
// ══════════════════════════════════════════════════════════════════

// ── 题库（50题，3种类型） ──
const GAME_QS = [
  // 助词 N5-N4 (t:'p')
  {t:'p',s:'東京＿行きます',a:'に',o:['に','を','で'],e:'「に」表示移动目的地。'},
  {t:'p',s:'電車＿乗ります',a:'に',o:['に','を','で'],e:'「に」乗る：乘坐交通工具。'},
  {t:'p',s:'水＿飲みます',a:'を',o:['を','に','で'],e:'「を」表示动作直接对象。'},
  {t:'p',s:'図書館＿勉強します',a:'で',o:['で','に','を'],e:'「で」表示动作场所。'},
  {t:'p',s:'友達＿会います',a:'に',o:['に','と','で'],e:'「に」会う：与某人见面。'},
  {t:'p',s:'先生＿習います',a:'に',o:['に','から','で'],e:'「に」習う：向…学习。'},
  {t:'p',s:'公園＿遊びます',a:'で',o:['で','に','を'],e:'「で」表示活动场所。'},
  {t:'p',s:'本＿読みます',a:'を',o:['を','に','で'],e:'「を」表示动作对象。'},
  {t:'p',s:'山田さん＿話します',a:'と',o:['と','に','で'],e:'「と」表示共同动作对象。'},
  {t:'p',s:'バス＿来ます',a:'で',o:['で','を','に'],e:'「で」表示交通手段。'},
  {t:'p',s:'ご飯＿食べます',a:'を',o:['を','に','で'],e:'「を」表示动作对象。'},
  {t:'p',s:'コーヒー＿好きです',a:'が',o:['が','を','の'],e:'「が」与「好き/嫌い」搭配。'},
  {t:'p',s:'日本語＿上手です',a:'が',o:['が','は','を'],e:'「が」与「上手/下手」搭配。'},
  {t:'p',s:'私＿学生です',a:'は',o:['は','が','も'],e:'「は」表示话题。'},
  {t:'p',s:'どこ＿来ましたか',a:'から',o:['から','に','で'],e:'「から」表示来源地。'},
  {t:'p',s:'3時＿始まります',a:'に',o:['に','で','から'],e:'「に」表示具体时间点。'},
  {t:'p',s:'ペン＿書きます',a:'で',o:['で','を','に'],e:'「で」表示使用的工具。'},
  {t:'p',s:'妹＿お菓子をあげます',a:'に',o:['に','へ','と'],e:'「に」あげる：给予某人。'},
  {t:'p',s:'先生＿もらいました',a:'に',o:['に','から','で'],e:'「に」もらう：从…收到。'},
  {t:'p',s:'日本＿来ました',a:'から',o:['から','に','を'],e:'「から」表示移动起点。'},
  {t:'p',s:'猫＿好きです',a:'が',o:['が','は','を'],e:'「が」与「好き」搭配。'},
  {t:'p',s:'電話＿連絡します',a:'で',o:['で','に','を'],e:'「で」表示联系手段。'},
  {t:'p',s:'弟＿本を貸します',a:'に',o:['に','へ','と'],e:'「に」貸す：借给某人。'},
  {t:'p',s:'この部屋＿広いです',a:'は',o:['は','が','の'],e:'「は」表示话题。'},
  {t:'p',s:'学校＿行きます',a:'へ',o:['へ','に','で'],e:'「へ」表示移动方向。'},
  {t:'p',s:'朝ご飯＿食べないです',a:'は',o:['は','を','が'],e:'「は」对比话题用。'},
  {t:'p',s:'一人＿行きます',a:'で',o:['で','と','に'],e:'「で」～人で：以…人数。'},
  {t:'p',s:'部屋の中＿入ります',a:'に',o:['に','を','で'],e:'「に」表示进入目的地。'},
  {t:'p',s:'9時＿働きます',a:'から',o:['から','に','まで'],e:'「から」表示开始时间。'},
  {t:'p',s:'駅＿歩いて行きます',a:'まで',o:['まで','から','で'],e:'「まで」表示移动终点。'},
  // 动词活用 (t:'v')
  {t:'v',s:'飲む → て形',a:'飲んで',o:['飲んで','飲みて','飲いて'],e:'む→んで：撥音変形。'},
  {t:'v',s:'書く → て形',a:'書いて',o:['書いて','書いで','書えて'],e:'く→いて：イ音便。'},
  {t:'v',s:'食べる → て形',a:'食べて',o:['食べて','食べりて','食べって'],e:'一段動詞：直接加て。'},
  {t:'v',s:'行く → て形',a:'行って',o:['行って','行いて','行きて'],e:'行く例外：行って。'},
  {t:'v',s:'持つ → て形',a:'持って',o:['持って','持ちて','持いて'],e:'つ→って：促音変。'},
  {t:'v',s:'遊ぶ → て形',a:'遊んで',o:['遊んで','遊びて','遊ぶて'],e:'ぶ→んで：撥音変形。'},
  {t:'v',s:'聞く → ない形',a:'聞かない',o:['聞かない','聞きない','聞くない'],e:'五段：く→か+ない。'},
  {t:'v',s:'見る → ない形',a:'見ない',o:['見ない','見りない','見えない'],e:'一段：る→ない。'},
  {t:'v',s:'来る → て形',a:'来て',o:['来て','来りて','来って'],e:'来る不规则：来て。'},
  {t:'v',s:'する → て形',a:'して',o:['して','すて','しいて'],e:'する不规则：して。'},
  {t:'v',s:'読む → ます形',a:'読みます',o:['読みます','読ます','読えます'],e:'む→み+ます。'},
  {t:'v',s:'起きる → ます形',a:'起きます',o:['起きます','起ります','起えます'],e:'一段：る→ます。'},
  // 词义选择 (t:'w')
  {t:'w',s:'嬉しい の意味は？',a:'高兴',o:['高兴','悲伤','害怕'],e:'嬉しい：高兴、喜悦。'},
  {t:'w',s:'難しい の意味は？',a:'困难',o:['困难','容易','有趣'],e:'難しい：困难的。'},
  {t:'w',s:'寂しい の意味は？',a:'寂寞',o:['寂寞','烦躁','愤怒'],e:'寂しい：寂寞的。'},
  {t:'w',s:'危ない の意味は？',a:'危险',o:['危险','安全','快速'],e:'危ない：危险的。'},
  {t:'w',s:'懐かしい の意味は？',a:'怀念',o:['怀念','陌生','无聊'],e:'懐かしい：怀念的。'},
  {t:'w',s:'諦める の意味は？',a:'放弃',o:['放弃','期待','努力'],e:'諦める：放弃。'},
  {t:'w',s:'褒める の意味は？',a:'表扬',o:['表扬','批评','忽视'],e:'褒める：表扬、夸赞。'},
  {t:'w',s:'慌てる の意味は？',a:'慌张',o:['慌张','镇定','欢呼'],e:'慌てる：慌张。'},
  {t:'w',s:'混む の意味は？',a:'拥挤',o:['拥挤','空旷','清洁'],e:'混む：拥挤。'},
  {t:'w',s:'片付ける の意味は？',a:'整理',o:['整理','破坏','装饰'],e:'片付ける：整理。'},
];

const G_Q_LABELS = { p:'助词填空', v:'动词活用', w:'词义选择' };
const G_COLS = 6;

// ── 全局状态 ──
let gBoard = null, gBoardTxt = null, gBoardClr = null;
let gScore = 0, gCombo = 0, gMaxCombo = 0, gWrong = 0, gWrongLog = [];
let gCurQ = null, gSelected = 1, gDropCol = 0;
let gBaseMs = 2000, gDropMs = 2000;
let gTimerIv = null, gTimeElapsed = 0, gRunning = false;
// 闯关状态
let gPhase        = 'select';
let gCurrentLevel = 1;
let gMaxLevels    = 10;
let gUnlockedTo   = 1;
let gLevelScores  = {};
let gGRows        = 5;
let gLives        = 99, gLivesMax = 99;
let gPassTarget   = 12, gPassCount = 0;
let gFever        = false;

// ── 关卡配置生成 ──
function gLvlCfg(lv) {
  return {
    rows:     Math.min(4 + lv, 12),
    toPass:   10 + Math.floor(lv * 1.8),
    livesMax: lv <= 3 ? 99 : lv <= 8 ? 5 : lv <= 15 ? 3 : 2,
    speedMul: Math.max(0.28, 1 - (lv - 1) * 0.028),
    qTypes:   lv <= 2 ? ['p'] : lv <= 6 ? ['p','v'] : ['p','v','w'],
    rowBonus: lv <= 5 ? 5 : lv <= 12 ? 8 : 12,
  };
}

// ── localStorage 存档 ──
function gLoadLocalSaves() {
  try {
    gUnlockedTo  = parseInt(localStorage.getItem('gUnlockedTo') || '1');
    gLevelScores = JSON.parse(localStorage.getItem('gLevelScores') || '{}');
  } catch {}
}
function gSaveLocalProgress(lv, score, stars, combo) {
  const prev = gLevelScores[lv] || {};
  if (!prev.stars || score > (prev.score || 0)) {
    gLevelScores[lv] = { score, stars, combo };
    try { localStorage.setItem('gLevelScores', JSON.stringify(gLevelScores)); } catch {}
  }
}

// ── 页面初始化 ──
function gamePageInit() {
  gLoadLocalSaves();
  gameSpeedInit();
  fetch('/api/v1/game/config')
    .then(r => r.json())
    .then(d => {
      if (d.ok) {
        gMaxLevels = parseInt(d.config.max_levels) || 10;
        const mb = document.getElementById('g-max-badge');
        if (mb) mb.textContent = '共 ' + gMaxLevels + ' 关';
      }
    })
    .catch(() => {})
    .finally(() => gRenderLevelGrid());
  // 管理员按钮
  try {
    const u = JSON.parse(localStorage.getItem('user') || 'null');
    if (u && u.role === 'admin') {
      const ab = document.getElementById('g-admin-btn');
      if (ab) ab.style.display = '';
    }
  } catch {}
}

// ── 关卡网格渲染 ──
function gRenderLevelGrid() {
  const grid = document.getElementById('g-lvl-grid');
  if (!grid) return;
  let html = '';
  for (let lv = 1; lv <= gMaxLevels; lv++) {
    const locked  = lv > gUnlockedTo;
    const cfg     = gLvlCfg(lv);
    const saved   = gLevelScores[lv];
    const stars   = saved ? (saved.stars || 0) : 0;
    const starStr = '★'.repeat(stars) + '☆'.repeat(3 - stars);
    const cls     = locked ? 'locked' : saved ? 'done' : '';
    html += '<div class="g-lvl-cell ' + cls + '"' + (locked ? '' : ' onclick="gBeginLevel(' + lv + ')"') + '>' +
      '<div class="g-lvl-n">' + lv + '</div>' +
      '<div class="g-lvl-row">' + cfg.rows + '行</div>' +
      '<div class="g-lvl-star">' + starStr + '</div>' +
      (saved ? '<div class="g-lvl-hi">' + saved.score + '分</div>' : '') +
      (locked ? '<div class="g-lvl-lock">🔒</div>' : '') +
      '</div>';
  }
  grid.innerHTML = html;
}

// ── 开始关卡 ──
function gBeginLevel(lv) {
  const cfg    = gLvlCfg(lv);
  gCurrentLevel = lv;
  gGRows        = cfg.rows;
  gLives        = cfg.livesMax;
  gLivesMax     = cfg.livesMax;
  gPassTarget   = cfg.toPass;
  gPassCount    = 0;
  gDropMs       = Math.round(gBaseMs * cfg.speedMul);
  gScore = 0; gCombo = 0; gMaxCombo = 0; gWrong = 0; gWrongLog = [];
  gFever = false; gRunning = true;
  document.getElementById('g-sel').style.display  = 'none';
  document.getElementById('g-play').style.display = '';
  document.getElementById('g-hud-title').textContent = '关卡 ' + lv + ' · ' + gGRows + '行';
  document.getElementById('g-pass-bar').style.width  = '0%';
  document.getElementById('g-pass-txt').textContent  = '0/' + cfg.toPass;
  document.getElementById('g-fever-banner').style.display = 'none';
  ['g-score','g-combo','g-wrong'].forEach(id => document.getElementById(id).textContent = 0);
  const dp = document.getElementById('g-diff-panel');
  if (dp) { dp.style.opacity = '.45'; dp.style.pointerEvents = 'none'; }
  gRenderLives();
  gameInitBoard();
  gameNextQ();
}

// ── 返回关卡选择 ──
function gBackToSelect() {
  if (gTimerIv) { clearInterval(gTimerIv); gTimerIv = null; }
  gRunning = false;
  document.getElementById('g-play').style.display = 'none';
  document.getElementById('g-sel').style.display  = '';
  const dp = document.getElementById('g-diff-panel');
  if (dp) { dp.style.opacity = ''; dp.style.pointerEvents = ''; }
  gRenderLevelGrid();
}

// ── 生命值渲染 ──
function gRenderLives() {
  const el = document.getElementById('g-lives-row');
  if (!el) return;
  if (gLivesMax >= 99) { el.textContent = '∞'; return; }
  el.textContent = '❤️'.repeat(Math.max(0, gLives)) + '🖤'.repeat(Math.max(0, gLivesMax - gLives));
}

// ── 过关进度条 ──
function gUpdatePassBar() {
  const pct = Math.min(100, gPassCount / gPassTarget * 100);
  const bar = document.getElementById('g-pass-bar');
  const txt = document.getElementById('g-pass-txt');
  if (bar) bar.style.width = pct + '%';
  if (txt) txt.textContent = gPassCount + '/' + gPassTarget;
}

// ── 棋盘初始化 ──
function gameInitBoard() {
  const el = document.getElementById('g-board');
  if (!el) return;
  gBoard    = Array.from({length: gGRows}, () => Array(G_COLS).fill(null));
  gBoardTxt = Array.from({length: gGRows}, () => Array(G_COLS).fill(''));
  gBoardClr = Array.from({length: gGRows}, () => Array(G_COLS).fill(''));
  el.style.gridTemplateRows     = 'repeat(' + gGRows + ', 1fr)';
  el.style.gridTemplateColumns  = 'repeat(' + G_COLS + ', 1fr)';
  const ch = Math.max(22, 40 - gGRows);
  let html = '';
  for (let r = 0; r < gGRows; r++)
    for (let c = 0; c < G_COLS; c++)
      html += '<div class="g-cell" style="background:#f1f5f9;border:1px solid #e2e8f0;color:transparent;min-height:' + ch + 'px"></div>';
  el.innerHTML = html;
}

// ── 棋盘刷新 ──
function gameRefreshBoard() {
  const el = document.getElementById('g-board');
  if (!el || !gBoard) return;
  const cells = el.children;
  if (cells.length !== gGRows * G_COLS) { gameInitBoard(); return; }
  const ch      = Math.max(22, 40 - gGRows);
  const selTxt  = (gCurQ && gRunning) ? (gCurQ.o[gSelected] || '') : '';
  for (let r = 0; r < gGRows; r++) {
    for (let c = 0; c < G_COLS; c++) {
      const st = gBoard[r][c];
      const d  = cells[r * G_COLS + c];
      if (!d) continue;
      const idc = c === gDropCol && gRunning && st !== 'correct' && st !== 'wrong';
      const base = 'border-radius:5px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:800;aspect-ratio:1;min-height:' + ch + 'px;';
      if (st === 'correct') {
        d.style.cssText = base + 'color:#fff;background:' + gBoardClr[r][c] + ';border:none;box-shadow:0 1px 3px rgba(0,0,0,.2)';
        d.textContent = gBoardTxt[r][c];
      } else if (st === 'wrong') {
        d.style.cssText = base + 'color:rgba(255,255,255,.75);background:#78716c;border:none';
        d.textContent = gBoardTxt[r][c];
      } else if (st === 'active') {
        d.style.cssText = base + 'color:#fff;background:#4361ee;border:none;animation:gpulse .5s infinite alternate;font-size:12px';
        d.textContent = selTxt;
      } else {
        d.style.cssText = base + 'color:transparent;background:' + (idc ? '#dce7ff' : '#f1f5f9') + ';border:1px solid ' + (idc ? '#90aaff' : '#e2e8f0') + ';animation:none';
        d.textContent = '';
      }
    }
  }
}

// ── 随机取空列 ──
function gamePickCol() {
  const idxs = [...Array(G_COLS).keys()].sort(() => Math.random() - .5);
  for (const c of idxs) if (!gBoard[0][c]) return c;
  return -1;
}

// ── 题目池（根据关卡类型） ──
function gQPool() {
  const types = new Set(gLvlCfg(gCurrentLevel).qTypes);
  return GAME_QS.filter(q => types.has(q.t));
}

// ── 下一题 ──
function gameNextQ() {
  if (!gRunning) return;
  gDropCol = gamePickCol();
  if (gDropCol === -1) { gRunning = false; setTimeout(gLevelFail, 300); return; }
  const pool  = gQPool();
  gCurQ    = pool[Math.floor(Math.random() * pool.length)];
  gSelected = Math.floor(gCurQ.o.length / 2);
  gTimeElapsed = 0;
  document.getElementById('g-sentence').textContent      = gCurQ.s;
  document.getElementById('g-qtype-badge').textContent   = G_Q_LABELS[gCurQ.t] || '填空';
  gUpdateColHint();
  gameRenderOptions();
  gBoard[0][gDropCol] = 'active';
  gameRefreshBoard();
  if (gTimerIv) clearInterval(gTimerIv);
  const totalMs = gDropMs;
  gTimerIv = setInterval(() => {
    gTimeElapsed += 80;
    const pct = Math.max(0, 100 - gTimeElapsed / totalMs * 100);
    const bar = document.getElementById('g-timebar');
    if (bar) {
      bar.style.width      = pct + '%';
      bar.style.background = pct > 55 ? 'var(--primary)' : pct > 22 ? '#f59e0b' : 'var(--danger)';
    }
    if (gTimeElapsed >= totalMs) gameConfirm();
  }, 80);
}

// ── 列指示器 ──
function gUpdateColHint() {
  const el = document.getElementById('g-col-hint');
  if (!el) return;
  let s = '';
  for (let c = 0; c < G_COLS; c++) s += c === gDropCol ? '▼' : '◦';
  el.textContent = s;
}

// ── 选项渲染 ──
function gameRenderOptions() {
  const el = document.getElementById('g-options');
  if (!el || !gCurQ) return;
  const maxLen = Math.max(...gCurQ.o.map(o => o.length));
  const fs = maxLen > 4 ? '13px' : maxLen > 2 ? '16px' : '20px';
  el.innerHTML = gCurQ.o.map((opt, i) =>
    '<div id="gopt-' + i + '" onclick="gameSelect(' + i + ')" style="' +
    'padding:13px 6px;border-radius:10px;text-align:center;cursor:pointer;' +
    'font-size:' + fs + ';font-weight:800;transition:all .15s;user-select:none;' +
    'border:2.5px solid ' + (i===gSelected ? 'var(--primary)' : 'var(--border)') + ';' +
    'background:' + (i===gSelected ? 'var(--primary-light,#e8effe)' : 'var(--surface)') + ';' +
    'color:' + (i===gSelected ? 'var(--primary)' : 'var(--text-sub)') + ';' +
    '">' + opt + '</div>'
  ).join('');
}

// ── 切换选项 ──
function gameSelect(i) {
  if (!gRunning) return;
  gSelected = i;
  gameRenderOptions();
  const el = document.getElementById('g-board');
  if (el && gBoard && gBoard[0] && gBoard[0][gDropCol] === 'active') {
    const d = el.children[gDropCol];
    if (d) d.textContent = gCurQ.o[i];
  }
}

// ── 确认答案 ──
function gameConfirm() {
  if (!gRunning || !gCurQ) return;
  if (gTimerIv) { clearInterval(gTimerIv); gTimerIv = null; }
  gBoard[0][gDropCol] = null;
  const ans = gCurQ.o[gSelected];
  const ok  = ans === gCurQ.a;
  // 落点
  let landRow = -1;
  for (let r = gGRows - 1; r >= 0; r--) { if (!gBoard[r][gDropCol]) { landRow = r; break; } }
  if (landRow < 0) { gRunning = false; setTimeout(gLevelFail, 300); return; }
  gBoard[landRow][gDropCol]    = ok ? 'correct' : 'wrong';
  gBoardTxt[landRow][gDropCol] = ans;
  gBoardClr[landRow][gDropCol] = ok ? gComboColor() : '#78716c';

  if (ok) {
    gPassCount++;
    gCombo++;
    if (gCombo > gMaxCombo) gMaxCombo = gCombo;
    gDropMs = Math.max(Math.round(gBaseMs * 0.28), gDropMs - Math.round(gCombo * 22));
    const wasFever = gFever;
    gFever = gCombo >= 8;
    const fevBanner = document.getElementById('g-fever-banner');
    if (fevBanner) fevBanner.style.display = gFever ? '' : 'none';
    if (gFever && !wasFever) toast('🔥 FEVER 激活！得分 ×2');
    const mul = gFever ? 2 : 1;
    const pts = mul * (1 + Math.floor(gCombo / 5));
    gScore += pts;
    gameClearRows();
    gameShowFeedback(gSelected, true, pts);
  } else {
    gWrong++;
    gCombo = 0; gFever = false;
    const fevBanner = document.getElementById('g-fever-banner');
    if (fevBanner) fevBanner.style.display = 'none';
    gDropMs = Math.min(Math.round(gBaseMs * 1.1), gDropMs + 100);
    gWrongLog.push({s: gCurQ.s, wrong: ans, correct: gCurQ.a, e: gCurQ.e});
    if (gLivesMax < 99) {
      gLives--;
      gRenderLives();
      if (gLives <= 0) {
        gameShowFeedback(gSelected, false, 0);
        gameRefreshBoard();
        setTimeout(gLevelFail, 700);
        return;
      }
    }
    gameShowFeedback(gSelected, false, 0);
  }

  document.getElementById('g-score').textContent = gScore;
  document.getElementById('g-combo').textContent = gCombo;
  document.getElementById('g-wrong').textContent = gWrong;
  gUpdatePassBar();
  gameRefreshBoard();

  if (gPassCount >= gPassTarget) {
    gRunning = false;
    setTimeout(gLevelClear, 600);
    return;
  }
  if (gBoard[0].some(c => c && c !== 'active')) {
    gRunning = false;
    setTimeout(gLevelFail, 800);
  } else {
    setTimeout(gameNextQ, 480);
  }
}

// ── 选项反馈 ──
function gameShowFeedback(idx, ok, pts) {
  const el = document.getElementById('g-options');
  if (!el || !gCurQ) return;
  el.querySelectorAll('div').forEach((d, i) => {
    if (i === idx) {
      d.style.background  = ok ? '#e8f5e9' : '#ffebee';
      d.style.borderColor = ok ? 'var(--success)' : 'var(--danger)';
      d.style.color       = ok ? 'var(--success)' : 'var(--danger)';
      if (ok && pts > 1) d.textContent += ' +' + pts;
    }
    if (!ok && gCurQ.o[i] === gCurQ.a) {
      d.style.background  = '#e8f5e9';
      d.style.borderColor = 'var(--success)';
      d.style.color       = 'var(--success)';
    }
  });
}

// ── 消行 ──
function gameClearRows() {
  const bonus = gLvlCfg(gCurrentLevel).rowBonus;
  for (let r = gGRows - 1; r >= 0; r--) {
    if (gBoard[r].every(c => c === 'correct' || c === 'wrong')) {
      gScore += bonus;
      for (let rr = r; rr > 0; rr--) {
        gBoard[rr]    = [...gBoard[rr-1]];
        gBoardTxt[rr] = [...gBoardTxt[rr-1]];
        gBoardClr[rr] = [...gBoardClr[rr-1]];
      }
      gBoard[0]    = Array(G_COLS).fill(null);
      gBoardTxt[0] = Array(G_COLS).fill('');
      gBoardClr[0] = Array(G_COLS).fill('');
      document.getElementById('g-score').textContent = gScore;
      toast('🎉 消行！+' + bonus + '分');
      r++;
    }
  }
}

// ── 连击颜色 ──
function gComboColor() {
  if (gCombo >= 10) return 'linear-gradient(135deg,#ef4444,#f59e0b)';
  if (gCombo >= 5)  return 'linear-gradient(135deg,#7c3aed,#4361ee)';
  return 'linear-gradient(135deg,#1976d2,#1565c0)';
}

// ── 星级计算 ──
function gCalcStars(acc, maxCombo) {
  if (acc >= 85 && maxCombo >= 5) return 3;
  if (acc >= 65) return 2;
  return 1;
}

// ── 通关 ──
function gLevelClear() {
  const acc   = Math.round(gPassCount / Math.max(1, gPassCount + gWrong) * 100);
  const stars = gCalcStars(acc, gMaxCombo);
  const dp    = document.getElementById('g-diff-panel');
  if (dp) { dp.style.opacity = ''; dp.style.pointerEvents = ''; }
  gSaveLocalProgress(gCurrentLevel, gScore, stars, gMaxCombo);
  if (gCurrentLevel >= gUnlockedTo && gCurrentLevel < gMaxLevels) {
    gUnlockedTo = gCurrentLevel + 1;
    try { localStorage.setItem('gUnlockedTo', gUnlockedTo); } catch {}
  }
  gameSaveScore(gCurrentLevel, gScore, acc, gMaxCombo, gPassCount + gWrong, true);
  const starStr = '⭐'.repeat(stars) + '☆'.repeat(3 - stars);
  const nextLv  = gCurrentLevel + 1;
  const hasNext = nextLv <= gMaxLevels;
  const wHtml   = gWrongLog.length
    ? '<div style="font-weight:700;margin-bottom:8px;text-align:left">📋 本关错题</div>' +
      gWrongLog.slice(0,5).map(w =>
        '<div style="padding:8px;background:var(--surface2,#f5f5f5);border-radius:6px;margin-bottom:6px;font-size:12px;text-align:left">' +
        '<div style="font-weight:700">' + escHtml(w.s) + '</div>' +
        '<div style="color:var(--danger)">❌ ' + escHtml(w.wrong) + '</div>' +
        '<div style="color:var(--success)">✅ ' + escHtml(w.correct) + '</div>' +
        '<div style="color:var(--text-sub);font-size:11px">' + escHtml(w.e) + '</div></div>'
      ).join('') : '';
  openModal('🎉 关卡 ' + gCurrentLevel + ' 通关！',
    '<div style="text-align:center;margin-bottom:14px">' +
    '<div style="font-size:44px;margin-bottom:8px">' + starStr + '</div>' +
    '<div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px;margin-bottom:10px">' +
    '<div style="background:var(--primary-light,#e8effe);padding:12px;border-radius:8px"><div style="font-size:20px;font-weight:800;color:var(--primary)">' + gScore + '</div><div style="font-size:10px;color:var(--text-sub)">得分</div></div>' +
    '<div style="background:#e8f5e9;padding:12px;border-radius:8px"><div style="font-size:20px;font-weight:800;color:var(--success)">' + acc + '%</div><div style="font-size:10px;color:var(--text-sub)">正确率</div></div>' +
    '<div style="background:#fffbeb;padding:12px;border-radius:8px"><div style="font-size:20px;font-weight:800;color:#f59e0b">' + gMaxCombo + '</div><div style="font-size:10px;color:var(--text-sub)">最高连击</div></div>' +
    '</div></div>' + wHtml +
    '<div style="display:flex;gap:8px;justify-content:center;margin-top:12px;flex-wrap:wrap">' +
    '<button class="btn btn-outline btn-sm" onclick="closeModal();gBackToSelect()">关卡列表</button>' +
    '<button class="btn btn-outline btn-sm" onclick="closeModal();gBeginLevel(' + gCurrentLevel + ')">重玩本关</button>' +
    (hasNext
      ? '<button class="btn btn-primary btn-sm" onclick="closeModal();gBeginLevel(' + nextLv + ')">下一关 →</button>'
      : '<button class="btn btn-primary btn-sm" onclick="closeModal();gBackToSelect()">🏆 全部通关！</button>') +
    '</div>');
}

// ── 失败 ──
function gLevelFail() {
  const dp = document.getElementById('g-diff-panel');
  if (dp) { dp.style.opacity = ''; dp.style.pointerEvents = ''; }
  const total = gPassCount + gWrong;
  const acc   = total > 0 ? Math.round(gPassCount / total * 100) : 0;
  gameSaveScore(gCurrentLevel, gScore, acc, gMaxCombo, total, false);
  const reason  = gLives <= 0 ? '💔 生命用尽' : '📦 棋盘溢出';
  const wHtml   = gWrongLog.slice(0,6).map(w =>
    '<div style="padding:8px;background:var(--surface2,#f5f5f5);border-radius:6px;margin-bottom:6px;font-size:12px;text-align:left">' +
    '<div style="font-weight:700">' + escHtml(w.s) + '</div>' +
    '<div style="color:var(--danger)">❌ ' + escHtml(w.wrong) + '</div>' +
    '<div style="color:var(--success)">✅ ' + escHtml(w.correct) + '</div>' +
    '<div style="color:var(--text-sub);font-size:11px">' + escHtml(w.e) + '</div></div>'
  ).join('');
  openModal(reason + ' · 关卡 ' + gCurrentLevel,
    '<div style="text-align:center;margin-bottom:12px">' +
    '<div style="font-size:40px;margin-bottom:8px">😤</div>' +
    '<div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px;margin-bottom:10px">' +
    '<div style="background:var(--primary-light,#e8effe);padding:10px;border-radius:8px"><div style="font-size:20px;font-weight:800;color:var(--primary)">' + gScore + '</div><div style="font-size:10px;color:var(--text-sub)">得分</div></div>' +
    '<div style="background:#ffebee;padding:10px;border-radius:8px"><div style="font-size:20px;font-weight:800;color:var(--danger)">' + gWrong + '</div><div style="font-size:10px;color:var(--text-sub)">错误</div></div>' +
    '<div style="background:#e8f5e9;padding:10px;border-radius:8px"><div style="font-size:20px;font-weight:800;color:var(--success)">' + acc + '%</div><div style="font-size:10px;color:var(--text-sub)">正确率</div></div>' +
    '</div>' +
    '<div style="font-size:13px;color:var(--text-sub)">已答对 ' + gPassCount + '/' + gPassTarget + '，未达过关条件</div>' +
    '</div>' +
    (gWrongLog.length ? '<div style="font-weight:700;margin-bottom:8px">📋 错题回顾</div>' + wHtml : '') +
    '<div style="display:flex;gap:8px;justify-content:center;margin-top:12px;flex-wrap:wrap">' +
    '<button class="btn btn-outline btn-sm" onclick="closeModal();gBackToSelect()">关卡列表</button>' +
    '<button class="btn btn-primary btn-sm" onclick="closeModal();gBeginLevel(' + gCurrentLevel + ')">再试一次</button>' +
    '</div>');
}

// ── 分数上报后端 ──
function gameSaveScore(lv, score, acc, maxCombo, total, passed) {
  const token = (typeof getToken === 'function') ? getToken() : localStorage.getItem('token');
  if (!token) return;
  fetch('/api/v1/game/score', {
    method: 'POST',
    headers: {'Content-Type':'application/json','Authorization':'Bearer ' + token},
    body: JSON.stringify({level_num:lv, score, accuracy:acc, max_combo:maxCombo, questions_answered:total, passed}),
  }).catch(() => {});
}

// ── 排行榜（全局） ──
function gOpenLeaderboard() {
  openModal('🏆 总排行榜', '<div class="loading"><div class="spinner"></div></div>');
  fetch('/api/v1/game/leaderboard/global')
    .then(r => r.json())
    .then(d => {
      if (!d.ok || !d.data.length) {
        document.getElementById('modal-body').innerHTML = '<div style="text-align:center;color:var(--text-hint);padding:24px">暂无排行数据，快来成为第一名！</div>';
        return;
      }
      const rows = d.data.map((row, i) => {
        const md = i===0?'🥇':i===1?'🥈':i===2?'🥉':'#'+(i+1);
        return '<tr><td style="padding:8px 4px;text-align:center;font-size:15px">' + md + '</td>' +
          '<td style="padding:8px 4px;font-weight:700">' + escHtml(row.username||'匿名') + '</td>' +
          '<td style="padding:8px 4px;text-align:center;font-weight:800;color:var(--primary)">' + (row.max_level||0) + '</td>' +
          '<td style="padding:8px 4px;text-align:center">' + (row.total_score||0) + '</td>' +
          '<td style="padding:8px 4px;text-align:center;color:#f59e0b">' + (row.best_combo||0) + '</td></tr>';
      }).join('');
      document.getElementById('modal-body').innerHTML =
        '<div style="overflow-x:auto">' +
        '<table style="width:100%;border-collapse:collapse;font-size:13px">' +
        '<thead><tr style="border-bottom:2px solid var(--border);color:var(--text-sub)">' +
        '<th style="padding:6px;text-align:center">名次</th><th style="padding:6px">玩家</th>' +
        '<th style="padding:6px;text-align:center">最高关</th><th style="padding:6px;text-align:center">总分</th>' +
        '<th style="padding:6px;text-align:center">最高连击</th></tr></thead>' +
        '<tbody>' + rows + '</tbody></table></div>' +
        '<div style="text-align:center;margin-top:12px">' +
        '<button class="btn btn-sm btn-outline" onclick="gOpenLevelLeaderboard(1)">单关排行 →</button></div>';
    })
    .catch(() => { document.getElementById('modal-body').innerHTML = '<div style="color:var(--danger);text-align:center;padding:16px">加载失败，请检查网络</div>'; });
}

// ── 单关排行榜 ──
function gOpenLevelLeaderboard(lv) {
  document.getElementById('modal-title').textContent = '🏆 关卡 ' + lv + ' 排行榜';
  document.getElementById('modal-body').innerHTML = '<div class="loading"><div class="spinner"></div></div>';
  const total = Math.min(gMaxLevels, 10);
  const nav   = Array.from({length: total}, (_, i) =>
    '<button class="btn btn-sm ' + (i+1===lv?'btn-primary':'btn-outline') + '" onclick="gOpenLevelLeaderboard(' + (i+1) + ')" style="padding:4px 10px">Lv.' + (i+1) + '</button>'
  ).join('');
  fetch('/api/v1/game/leaderboard?level=' + lv)
    .then(r => r.json())
    .then(d => {
      const navHtml = '<div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:12px">' + nav + '</div>';
      if (!d.ok || !d.data.length) {
        document.getElementById('modal-body').innerHTML = navHtml + '<div style="text-align:center;color:var(--text-hint);padding:16px">该关暂无过关记录</div>';
        return;
      }
      const rows = d.data.map((row, i) => {
        const md = i===0?'🥇':i===1?'🥈':i===2?'🥉':'#'+(i+1);
        return '<tr><td style="padding:7px 4px;text-align:center">' + md + '</td>' +
          '<td style="padding:7px 4px;font-weight:700">' + escHtml(row.username||'匿名') + '</td>' +
          '<td style="padding:7px 4px;text-align:center;font-weight:800;color:var(--primary)">' + (row.best_score||0) + '</td>' +
          '<td style="padding:7px 4px;text-align:center;color:#f59e0b">' + (row.best_combo||0) + '</td>' +
          '<td style="padding:7px 4px;text-align:center">' + (row.avg_acc||0) + '%</td></tr>';
      }).join('');
      document.getElementById('modal-body').innerHTML = navHtml +
        '<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse;font-size:13px">' +
        '<thead><tr style="border-bottom:2px solid var(--border);color:var(--text-sub)">' +
        '<th style="padding:6px;text-align:center">名次</th><th style="padding:6px">玩家</th>' +
        '<th style="padding:6px;text-align:center">最高分</th><th style="padding:6px;text-align:center">最高连击</th>' +
        '<th style="padding:6px;text-align:center">准确率</th></tr></thead><tbody>' + rows + '</tbody></table></div>';
    })
    .catch(() => { document.getElementById('modal-body').innerHTML = '<div style="color:var(--danger);text-align:center;padding:16px">加载失败</div>'; });
}

// ── 管理员关卡设置 ──
function gOpenAdminConfig() {
  openModal('⚙️ 关卡设置（管理员）',
    '<div class="input-group"><label>最大关卡数（1-30）</label>' +
    '<input class="input" id="g-admin-maxlv" type="number" min="1" max="30" value="' + gMaxLevels + '"></div>' +
    '<div style="font-size:12px;color:var(--text-hint);margin-bottom:14px">设置后玩家可见的关卡总数将更新（当前：' + gMaxLevels + ' 关）</div>' +
    '<button class="btn btn-primary" style="width:100%;justify-content:center" onclick="gSaveAdminConfig()">保存</button>');
}
function gSaveAdminConfig() {
  const val   = parseInt(document.getElementById('g-admin-maxlv').value);
  const token = (typeof getToken === 'function') ? getToken() : localStorage.getItem('token');
  if (!token) { toast('请先登录'); return; }
  fetch('/api/v1/game/config', {
    method: 'PUT',
    headers: {'Content-Type':'application/json','Authorization':'Bearer '+token},
    body: JSON.stringify({max_levels: val}),
  }).then(r => r.json()).then(d => {
    if (d.ok) {
      gMaxLevels = d.max_levels;
      const mb = document.getElementById('g-max-badge');
      if (mb) mb.textContent = '共 ' + gMaxLevels + ' 关';
      closeModal();
      toast('✅ 已更新为 ' + gMaxLevels + ' 关');
      gRenderLevelGrid();
    }
  }).catch(() => toast('保存失败'));
}

// ── 速度滑块 ──
function gameSpeedInput(input) {
  const ms = parseInt(input.value);
  gBaseMs = ms;
  if (!gRunning) gDropMs = ms;
  const pct = (ms - 300) / (10000 - 300) * 100;
  input.style.background = 'linear-gradient(to right, var(--primary) ' + pct + '%, var(--border) ' + pct + '%)';
  const secs = (ms / 1000).toFixed(1);
  document.getElementById('g-speed-val').textContent = secs + 's';
  let emoji = '⚡', label = '极速';
  if      (ms >= 8000) { emoji = '🐌'; label = '超慢'; }
  else if (ms >= 4000) { emoji = '🐢'; label = '很慢'; }
  else if (ms >= 2000) { emoji = '🐢'; label = '慢速'; }
  else if (ms >= 1200) { emoji = '🚶'; label = '正常'; }
  else if (ms >= 700)  { emoji = '🏃'; label = '快速'; }
  else if (ms >= 400)  { emoji = '💨'; label = '冲刺'; }
  document.getElementById('g-speed-emoji').textContent = emoji;
  document.getElementById('g-speed-label').textContent = label;
}
function gameSpeedInit() {
  const sl = document.getElementById('g-speed-slider');
  if (sl) gameSpeedInput(sl);
}

// ── 键盘控制 ──
document.addEventListener('keydown', function(e) {
  const ap = document.querySelector('.page.active');
  if (!ap || ap.id !== 'page-game' || !gRunning) return;
  const len = gCurQ ? gCurQ.o.length : 3;
  if      (e.key === 'ArrowLeft')              { gameSelect(Math.max(0, gSelected - 1)); e.preventDefault(); }
  else if (e.key === 'ArrowRight')             { gameSelect(Math.min(len - 1, gSelected + 1)); e.preventDefault(); }
  else if (e.key === 'Enter' || e.key === ' ') { gameConfirm(); e.preventDefault(); }
});
