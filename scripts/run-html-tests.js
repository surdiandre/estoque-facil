#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { JSDOM, VirtualConsole } = require('jsdom');

const ROOT = path.resolve(__dirname, '..');
const ORIGIN = 'http://ci.local';
const TEST_PAGES = [
  'tests/security.test.html',
  'tests/validade.test.html',
  'tests/queue.test.html'
];

function waitForSummary(window, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  return new Promise((resolve, reject) => {
    const check = () => {
      const summary = window.document.getElementById('summary');
      const text = summary?.textContent?.trim();
      if (text && text !== 'Executando…') {
        resolve(text);
        return;
      }
      if (Date.now() >= deadline) {
        reject(new Error('O teste não concluiu antes do timeout.'));
        return;
      }
      setTimeout(check, 10);
    };
    check();
  });
}

async function runPage(relativePath) {
  const absolutePath = path.join(ROOT, relativePath);
  const html = fs.readFileSync(absolutePath, 'utf8');
  const url = ORIGIN + '/' + relativePath.replaceAll(path.sep, '/');
  const jsdomErrors = [];
  const virtualConsole = new VirtualConsole();
  virtualConsole.on('jsdomError', error => jsdomErrors.push(error));

  const dom = new JSDOM(html, {
    url,
    runScripts: 'dangerously',
    virtualConsole,
    beforeParse(window) {
      window.fetch = async input => {
        const requested = new URL(typeof input === 'string' ? input : input.url, window.location.href);
        if (requested.origin !== ORIGIN) {
          return { ok: false, status: 403, text: async () => 'Unexpected origin' };
        }
        const target = path.resolve(ROOT, '.' + decodeURIComponent(requested.pathname));
        const relative = path.relative(ROOT, target);
        if (relative.startsWith('..') || path.isAbsolute(relative)) {
          return { ok: false, status: 403, text: async () => 'Path outside project' };
        }
        try {
          const body = fs.readFileSync(target, 'utf8');
          return { ok: true, status: 200, text: async () => body };
        } catch {
          return { ok: false, status: 404, text: async () => 'File not found' };
        }
      };
    }
  });

  try {
    const summary = await waitForSummary(dom.window, 10000);
    const failures = [...dom.window.document.querySelectorAll('#results .fail')]
      .map(item => item.textContent.trim());
    const resultCount = dom.window.document.querySelectorAll('#results li').length;
    if (!summary.startsWith('✅') || failures.length > 0 || resultCount === 0 || jsdomErrors.length > 0) {
      const details = failures.length ? '\n' + failures.map(item => '  - ' + item).join('\n') : '';
      const runtime = jsdomErrors.length ? '\n' + jsdomErrors.map(error => error.message).join('\n') : '';
      throw new Error(relativePath + ': ' + summary + details + runtime);
    }
    console.log(relativePath + ': ' + summary + ' (' + resultCount + ' testes)');
    return resultCount;
  } finally {
    dom.window.close();
  }
}

(async () => {
  let total = 0;
  for (const page of TEST_PAGES) total += await runPage(page);
  console.log('Sucesso: ' + total + ' testes HTML passaram.');
})().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
