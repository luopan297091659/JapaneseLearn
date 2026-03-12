const Database = require('better-sqlite3');
const db = new Database('./temp_grammar_extract/collection.anki21');

// Tables
const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all();
console.log('Tables:', tables.map(t => t.name));

// Notes structure
const cols = db.prepare("PRAGMA table_info(notes)").all();
console.log('Notes columns:', cols.map(c => c.name));

// Count
const cnt = db.prepare('SELECT COUNT(*) as c FROM notes').get();
console.log('Total notes:', cnt.c);

// Tags distribution
const allNotes = db.prepare('SELECT tags FROM notes').all();
const tagCounts = {};
allNotes.forEach(r => {
  const tags = r.tags.trim().split(/\s+/).filter(Boolean);
  tags.forEach(t => { tagCounts[t] = (tagCounts[t] || 0) + 1; });
});
console.log('\nTag distribution:');
Object.entries(tagCounts).sort((a, b) => b[1] - a[1]).forEach(([tag, count]) => {
  console.log(`  ${tag}: ${count}`);
});

// Sample notes (first 5)
const samples = db.prepare('SELECT id, mid, flds, tags FROM notes LIMIT 5').all();
samples.forEach((r, i) => {
  console.log(`\n--- Note ${i + 1} ---`);
  console.log('tags:', r.tags.trim());
  const fields = r.flds.split('\x1f');
  console.log('fields count:', fields.length);
  fields.forEach((f, j) => {
    // Strip HTML for display
    const clean = f.replace(/<[^>]*>/g, '').substring(0, 200);
    console.log(`  field[${j}]: ${clean}`);
  });
});

// Model info
const colDecks = db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='col'").all();
if (colDecks.length > 0) {
  const colData = db.prepare("SELECT models FROM col").get();
  if (colData) {
    const models = JSON.parse(colData.models);
    Object.values(models).forEach(m => {
      console.log(`\nModel: ${m.name}`);
      console.log('Fields:', m.flds.map(f => f.name));
    });
  }
}

// Check notetypes table (anki21 format)
try {
  const notetypes = db.prepare("SELECT * FROM notetypes").all();
  notetypes.forEach(nt => {
    console.log(`\nNotetype: ${nt.name} (id: ${nt.id})`);
    try {
      const config = JSON.parse(nt.config || '{}');
      console.log('Config keys:', Object.keys(config));
    } catch (_) {}
  });
  
  const fields = db.prepare("SELECT * FROM fields ORDER BY ntid, ord").all();
  console.log('\nFields by notetype:');
  const byNt = {};
  fields.forEach(f => {
    if (!byNt[f.ntid]) byNt[f.ntid] = [];
    byNt[f.ntid].push(f.name);
  });
  Object.entries(byNt).forEach(([ntid, names]) => {
    console.log(`  ntid ${ntid}: [${names.join(', ')}]`);
  });
} catch (e) {
  console.log('No notetypes table:', e.message);
}

db.close();
