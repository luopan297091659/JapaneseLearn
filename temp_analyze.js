var d = require("/tmp/nhkw.json");
var items = d.data;
console.log("Total:", items.length);
console.log("Keys:", Object.keys(items[0]).join(", "));
var vids = items.filter(function(x) { return Object.keys(x).some(function(k) { return k.toLowerCase().indexOf("vid") >= 0; }); });
console.log("With vid key:", vids.length);
items.forEach(function(item) { Object.keys(item).forEach(function(k) { if (k.toLowerCase().indexOf("vid") >= 0 || k.toLowerCase().indexOf("movie") >= 0) { console.log("  " + k + " = " + item[k]); } }); });
