const fs = require('fs');
const h = fs.readFileSync('d:/PROJECT/JapaneseLearn/nhk_article.html', 'utf8');

// Extract all script tags with __next_f content
const scripts = [];
const re = /<script>(self\.__next_f\.push.*?)<\/script>/g;
let m;
while ((m = re.exec(h)) !== null) {
  scripts.push(m[1]);
}
console.log('Total __next_f scripts:', scripts.length);

// Find ones that contain article keywords
scripts.forEach((s, i) => {
  if (s.includes('茂木') || s.includes('イラン') || s.includes('拘束') || s.includes('外務')) {
    console.log(`\n=== Script ${i} (len=${s.length}) ===`);
    // Decode the escaped string
    try {
      // The format is: self.__next_f.push([1,"...escaped content..."])
      const content = s.replace('self.__next_f.push([1,"', '').replace('"])', '');
      const decoded = content.replace(/\\n/g, '\n').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
      console.log(decoded.substring(0, 2000));
    } catch(e) {
      console.log(s.substring(0, 2000));
    }
  }
});
