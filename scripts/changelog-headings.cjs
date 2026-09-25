#!/usr/bin/env node
// Return source positions of top-level, plain-version ATX release headings.
// A CommonMark syntax tree keeps list/quote fences and raw HTML out of this inventory.
const fs = require('node:fs');
const { Parser } = require('commonmark');

const [file, ...extra] = process.argv.slice(2);
if (!file || extra.length) {
  console.error('usage: node scripts/changelog-headings.cjs <changelog>');
  process.exit(1);
}

const markdown = fs.readFileSync(file, 'utf8');
const lines = markdown.split(/\r\n|\n|\r/);
const document = new Parser().parse(markdown);
const headings = [];
for (let node = document.firstChild; node; node = node.next) {
  if (node.type !== 'heading' || node.level !== 2) continue;
  const line = node.sourcepos[0][0];
  // Keep the repository's literal "## X.Y.Z" convention; formatted or setext titles
  // are not release entries. Parsing first proves that the source line is a heading.
  const match = /^ {0,3}##[\t ]+([0-9]+\.[0-9]+\.[0-9]+)(?:[\t ]|$)/.exec(lines[line - 1]);
  if (match) headings.push({ line, version: match[1] });
}
process.stdout.write(JSON.stringify(headings) + '\n');
