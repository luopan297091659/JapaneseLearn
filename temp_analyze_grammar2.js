const Database = require('better-sqlite3');
const db = new Database('./temp_grammar_extract/collection.anki21');

// Get model field names from col table
const colData = db.prepare("SELECT models FROM col").get();
if (colData) {
  const models = JSON.parse(colData.models);
  Object.values(models).forEach(m => {
    console.log(`Model: ${m.name} (id: ${m.id})`);
    console.log('Field names:');
    m.flds.forEach((f, i) => {
      console.log(`  [${i}] ${f.name}`);
    });
  });
}

// Extract all grammar items: title, structure, meaning, level, examples
console.log('\n\n=== ALL GRAMMAR ITEMS ===\n');
const allNotes = db.prepare('SELECT flds, tags FROM notes ORDER BY id').all();
const grammarItems = [];

allNotes.forEach(r => {
  const fields = r.flds.split('\x1f');
  const tags = r.tags.trim();
  
  // Determine level from tags
  let level = '';
  if (tags.includes('::N1')) level = 'N1';
  else if (tags.includes('::N2')) level = 'N2';
  else if (tags.includes('::N3')) level = 'N3';
  else if (tags.includes('::N4')) level = 'N4';
  else if (tags.includes('::N5')) level = 'N5';
  else if (tags.includes('敬语')) level = '敬語';
  
  // Clean HTML
  const clean = (s) => (s || '').replace(/<[^>]*>/g, '').trim();
  
  const title = clean(fields[3]); // grammar point title
  const structure = clean(fields[4]); // grammar structure/pattern
  const meaning = clean(fields[14]); // Chinese meaning/explanation
  
  // Example sentences (fields 29-31 Japanese, 54-56 Chinese)
  const examples = [];
  for (let i = 29; i <= 53; i++) {
    const jp = clean(fields[i]);
    if (jp) {
      const zhIdx = i + 25; // corresponding Chinese translation
      const zh = clean(fields[zhIdx]);
      examples.push({ jp, zh });
    }
  }
  
  // Notes/explanations (fields 104-106)
  const notes = [clean(fields[104]), clean(fields[105]), clean(fields[106])].filter(Boolean);
  
  grammarItems.push({ level, title, structure, meaning, examples: examples.length, notes: notes.length });
});

// Summary by level
const byLevel = {};
grammarItems.forEach(g => {
  if (!byLevel[g.level]) byLevel[g.level] = [];
  byLevel[g.level].push(g);
});

console.log('Grammar count by level:');
Object.entries(byLevel).sort().forEach(([level, items]) => {
  console.log(`  ${level || '(no level)'}: ${items.length} items`);
});

// Print first 5 of each level
Object.entries(byLevel).sort().forEach(([level, items]) => {
  console.log(`\n--- ${level} (first 10) ---`);
  items.slice(0, 10).forEach(g => {
    console.log(`  ${g.title} | ${g.structure} | ${g.meaning.substring(0, 50)} | examples: ${g.examples}`);
  });
});

db.close();
