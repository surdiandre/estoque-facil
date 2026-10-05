#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const ROOT = path.resolve(__dirname, '..');
const FILES = ['index.html', 'estoque-facil.html'];
const [indexHtml, stockHtml] = FILES.map(file => fs.readFileSync(path.join(ROOT, file)));
const digest = content => crypto.createHash('sha256').update(content).digest('hex');
const indexHash = digest(indexHtml);
const stockHash = digest(stockHtml);

if (!indexHtml.equals(stockHtml)) {
  console.error('❌ Os HTMLs diferem.');
  console.error('  index.html: ' + indexHash);
  console.error('  estoque-facil.html: ' + stockHash);
  process.exit(1);
}

console.log('✅ HTMLs idênticos. SHA-256: ' + indexHash);
