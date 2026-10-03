#!/usr/bin/env node
'use strict';

// Atualiza as versões em memória primeiro. Só grava depois que todas as
// referências e a igualdade dos HTMLs forem validadas.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const ROOT = path.resolve(__dirname, '..');
const FILES = [
  'sw.js',
  'app-version.json',
  'assets/app-updates.js',
  'index.html',
  'estoque-facil.html'
];

function fail(message) {
  throw new Error(message);
}

function sha256(text) {
  return crypto.createHash('sha256').update(text, 'utf8').digest('hex');
}

function countMatches(text, regex) {
  return [...text.matchAll(new RegExp(regex.source, regex.flags.includes('g') ? regex.flags : regex.flags + 'g'))].length;
}

// Exige exatamente uma ocorrência para evitar alterações silenciosas incompletas.
function replaceExactlyOnce(text, regex, replacement, description) {
  const count = countMatches(text, regex);
  if (count !== 1) fail(description + ': esperada 1 ocorrência, encontradas ' + count + '.');
  return text.replace(regex, replacement);
}

function versionFrom(text, regex, description) {
  const match = text.match(regex);
  if (!match) fail('Não encontrei a versão em ' + description + '.');
  return match[1];
}

function main() {
  const args = process.argv.slice(2);
  if (args.length !== 1 || !/^[1-9]\d*$/.test(args[0]) || !Number.isSafeInteger(Number(args[0]))) {
    fail('Informe uma versão como inteiro positivo, por exemplo: npm run bump 225');
  }
  const nextVersion = args[0];

  // Guarda cópias originais para validar tudo antes da gravação e reverter
  // arquivos já gravados se uma operação de escrita falhar.
  const original = Object.fromEntries(FILES.map(file => {
    const fullPath = path.join(ROOT, file);
    if (!fs.existsSync(fullPath)) fail('Arquivo obrigatório não encontrado: ' + file);
    return [file, fs.readFileSync(fullPath, 'utf8')];
  }));
  const beforeIndexHash = sha256(original['index.html']);
  const beforeStockHash = sha256(original['estoque-facil.html']);
  if (beforeIndexHash !== beforeStockHash) {
    console.error('⚠️ Os HTMLs já estão diferentes. Nenhum arquivo foi alterado; restaure a igualdade e tente novamente.');
    process.exitCode = 1;
    return;
  }

  // Confirma que os componentes compartilham uma versão atual antes do bump.
  const currentSwVersion = versionFrom(original['sw.js'], /const VERSION\s*=\s*['"](\d+)['"]\s*;/, 'sw.js');
  const currentCacheVersion = versionFrom(original['sw.js'], /const CACHE\s*=\s*['"]estoque-facil-v(\d+)-[^'"]+['"]\s*;/, 'CACHE do sw.js');
  const currentCoreVersion = versionFrom(original['sw.js'], /['"]\.\/assets\/app-updates\.js\?v=(\d+)['"]/, 'CORE do sw.js');
  const appVersion = JSON.parse(original['app-version.json']);
  const currentJsonVersion = String(appVersion.version || '');
  const currentUpdateVersion = versionFrom(original['assets/app-updates.js'], /const VERSION\s*=\s*['"](\d+)['"]\s*;/, 'assets/app-updates.js');
  const currentVersions = [currentSwVersion, currentCacheVersion, currentCoreVersion, currentJsonVersion, currentUpdateVersion];
  if (currentVersions.some(version => version !== currentSwVersion)) {
    fail('As versões atuais já divergem entre sw.js, app-version.json e app-updates.js. Sincronize-as antes de executar o bump.');
  }

  const updated = { ...original };
  const counts = {};

  // Atualiza versão do service worker, nome do cache e referência CORE.
  updated['sw.js'] = replaceExactlyOnce(
    updated['sw.js'],
    /(const VERSION\s*=\s*['"])\d+(['"]\s*;)/,
    (match, prefix, suffix) => prefix + nextVersion + suffix,
    'VERSION no sw.js'
  );
  updated['sw.js'] = replaceExactlyOnce(
    updated['sw.js'],
    /(const CACHE\s*=\s*['"]estoque-facil-v)\d+(-[^'"]+['"]\s*;)/,
    (match, prefix, suffix) => prefix + nextVersion + suffix,
    'CACHE no sw.js'
  );
  updated['sw.js'] = replaceExactlyOnce(
    updated['sw.js'],
    /(['"]\.\/assets\/app-updates\.js\?v=)\d+(['"])/,
    (match, prefix, suffix) => prefix + nextVersion + suffix,
    'CORE app-updates.js no sw.js'
  );

  // Atualiza JSON e mantém o sufixo descritivo do rótulo (ex.: “Validade por data”).
  if (!/^v\d+\s*·\s*/.test(String(appVersion.label || ''))) {
    fail('O rótulo de app-version.json não segue o formato “vN · descrição”.');
  }
  appVersion.version = nextVersion;
  appVersion.label = String(appVersion.label).replace(/^v\d+(\s*·\s*)/, 'v' + nextVersion + '$1');
  updated['app-version.json'] = JSON.stringify(appVersion) + '\n';

  // Sincroniza a versão interna usada pelo detector de atualizações.
  updated['assets/app-updates.js'] = replaceExactlyOnce(
    updated['assets/app-updates.js'],
    /(const VERSION\s*=\s*['"])\d+(['"]\s*;)/,
    (match, prefix, suffix) => prefix + nextVersion + suffix,
    'VERSION em assets/app-updates.js'
  );

  // Atualiza todos os parâmetros ?v= nos dois HTMLs, como cache-busters.
  for (const file of ['index.html', 'estoque-facil.html']) {
    counts[file] = countMatches(updated[file], /\?v=\d+/g);
    if (counts[file] === 0) fail('Não encontrei parâmetros ?v= em ' + file + '.');
    updated[file] = updated[file].replace(/(\?v=)\d+/g, '$1' + nextVersion);
  }

  // Valida as referências e a igualdade dos HTMLs antes de tocar no disco.
  const finalJson = JSON.parse(updated['app-version.json']);
  const finalSw = updated['sw.js'];
  const finalInternal = versionFrom(updated['assets/app-updates.js'], /const VERSION\s*=\s*['"](\d+)['"]\s*;/, 'assets/app-updates.js');
  const finalReferences = [
    versionFrom(finalSw, /const VERSION\s*=\s*['"](\d+)['"]\s*;/, 'VERSION no sw.js'),
    versionFrom(finalSw, /const CACHE\s*=\s*['"]estoque-facil-v(\d+)-[^'"]+['"]\s*;/, 'CACHE no sw.js'),
    versionFrom(finalSw, /['"]\.\/assets\/app-updates\.js\?v=(\d+)['"]/, 'CORE do sw.js'),
    String(finalJson.version),
    finalInternal
  ];
  if (finalReferences.some(version => version !== nextVersion)) fail('Validação final encontrou versões divergentes.');
  const afterIndexHash = sha256(updated['index.html']);
  const afterStockHash = sha256(updated['estoque-facil.html']);
  if (afterIndexHash !== afterStockHash) fail('Os HTMLs divergiram durante a atualização. Nenhum arquivo foi gravado.');

  // Grava usando arquivos temporários; se qualquer gravação falhar, restaura
  // integralmente todos os arquivos já substituídos.
  const written = [];
  try {
    for (const file of FILES) {
      const target = path.join(ROOT, file);
      const temporary = target + '.bump-' + process.pid + '.tmp';
      try {
        fs.writeFileSync(temporary, updated[file], { encoding: 'utf8', mode: fs.statSync(target).mode });
        fs.renameSync(temporary, target);
        written.push(file);
      } catch (error) {
        if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
        throw error;
      }
    }
  } catch (error) {
    for (const file of written.reverse()) fs.writeFileSync(path.join(ROOT, file), original[file], 'utf8');
    fail('Falha ao gravar; arquivos anteriores restaurados. Detalhe: ' + error.message);
  }

  console.log('✅ Versão atualizada: ' + currentSwVersion + ' → ' + nextVersion);
  console.log('  sw.js: VERSION, CACHE e CORE app-updates.js');
  console.log('  app-version.json: version e label');
  console.log('  assets/app-updates.js: VERSION interna');
  console.log('  index.html: ' + counts['index.html'] + ' parâmetros ?v= atualizados');
  console.log('  estoque-facil.html: ' + counts['estoque-facil.html'] + ' parâmetros ?v= atualizados');
  console.log('  SHA-256 dos HTMLs: idênticos (' + afterIndexHash + ')');
}

try {
  main();
} catch (error) {
  console.error('❌ ' + error.message);
  process.exitCode = 1;
}
