#!/usr/bin/env bash
set -uo pipefail

html_files=(index.html estoque-facil.html)
for file in "${html_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    printf '❌ Arquivo não encontrado: %s\n' "$file" >&2
    exit 1
  fi
done

matches="$(rg -n 'innerHTML|insertAdjacentHTML|outerHTML' index.html estoque-facil.html || true)"
interpolated_lines="$(printf '%s\n' "$matches" | awk 'index($0, sprintf("%c{", 36)) > 0')"
failed=0

while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  if ! grep -Eq 'escaparHtml\(|textContent|createElement|replaceChildren|safeIcon' <<< "$line"; then
    printf '❌ Interpolação sem proteção: %s\n' "$line" >&2
    failed=1
  fi
done <<< "$interpolated_lines"

row_check="$(awk '
  /const row = `/ { capturing = 1; row_start = NR; block = $0; next }
  capturing {
    block = block "\n" $0
    if ($0 ~ /`;[[:space:]]*$/) {
      references = block
      escapes = block
      interpolation_count = gsub(/\$\{/, "", references)
      escape_count = gsub(/escaparHtml\(/, "", escapes)
      if (interpolation_count > escape_count) {
        printf "index.html:%d: linha de relatório: %d interpolações, %d chamadas a escaparHtml().\n", row_start, interpolation_count, escape_count
        failed = 1
      }
      capturing = 0
      completed = 1
      exit
    }
  }
  END {
    if (!completed) {
      print "index.html: não foi possível verificar o template de linha do relatório."
      failed = 1
    }
    if (failed) exit 1
  }
' index.html 2>&1)" || {
  printf '❌ %s\n' "$row_check" >&2
  failed=1
}

check_builder() {
  local name="$1"
  local start_marker="$2"
  local end_marker="$3"
  local block
  block="$(awk -v start="$start_marker" -v end="$end_marker" '
    !capturing && index($0, start) { capturing = 1 }
    capturing && end != "" && index($0, end) { found = 1; exit }
    capturing { print }
    END { if (!capturing) exit 2 }
  ' index.html)" || {
    printf '❌ Não foi possível inspecionar o template intermediário: %s\n' "$name" >&2
    failed=1
    return
  }
  if ! grep -Fq 'escaparHtml(' <<< "$block"; then
    printf '❌ Template intermediário sem escaparHtml(): %s\n' "$name" >&2
    failed=1
  fi
}

check_builder 'badges de estoque' 'const badges = Object.entries(counts)' 'const lotsHtml = lotes.map'
check_builder 'lotes do estoque' 'const lotsHtml = lotes.map((l, li) => {' 'const lotCountLabel ='
check_builder 'detalhes do estoque' 'window.stockDetailMarkup[groupIndex] =' 'const productId ='
check_builder 'cartão de estoque' 'const productRow =' 'tbody.insertAdjacentHTML'

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

printf '✅ Nenhuma interpolação crua detectada\n'
