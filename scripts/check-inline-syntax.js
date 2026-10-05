#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const { JSDOM } = require('jsdom');

const ROOT = path.resolve(__dirname, '..');
const HTML_FILES = ['index.html', 'estoque-facil.html'];
const MODULE_TYPES = new Set(['module']);
const CLASSIC_TYPES = new Set([
  '',
  'text/javascript',
  'application/javascript',
  'text/ecmascript',
  'application/ecmascript'
]);

function checkInlineScripts(filename) {
  const source = fs.readFileSync(path.join(ROOT, filename), 'utf8');
  const dom = new JSDOM(source);
  let checked = 0;
  const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'estoque-inline-'));

  try {
    const scripts = [...dom.window.document.querySelectorAll('script:not([src])')];
    for (let index = 0; index < scripts.length; index++) {
      const script = scripts[index];
      const type = (script.getAttribute('type') || '').split(';', 1)[0].trim().toLowerCase();
      if (MODULE_TYPES.has(type)) {
        const temporaryModule = path.join(temporaryDirectory, 'inline-' + (index + 1) + '.mjs');
        fs.writeFileSync(temporaryModule, script.textContent, 'utf8');
        execFileSync(process.execPath, ['--check', temporaryModule], { stdio: 'pipe' });
      } else if (CLASSIC_TYPES.has(type)) {
        new vm.Script(script.textContent, {
          filename: filename + '#inline-script-' + (index + 1)
        });
      } else {
        continue;
      }
      checked++;
    }
  } finally {
    dom.window.close();
    fs.rmSync(temporaryDirectory, { recursive: true, force: true });
  }

  console.log(filename + ': ' + checked + ' scripts inline válidos.');
  return checked;
}

const count = HTML_FILES.reduce((total, filename) => total + checkInlineScripts(filename), 0);
console.log('Sintaxe inline OK: ' + count + ' scripts verificados.');
