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
dynamic_sink_lines="$(printf '%s\n' "$matches" | awk '
  function has_dynamic_content(text) {
    return index(text, interpolation) > 0 || index(text, "+") > 0
  }
  BEGIN { interpolation = sprintf("%c{", 36) }
  /innerHTML/ {
    text = substr($0, index($0, "innerHTML"))
    if (has_dynamic_content(text)) print
    next
  }
  /insertAdjacentHTML/ {
    text = substr($0, index($0, "insertAdjacentHTML"))
    if (has_dynamic_content(text)) print
    next
  }
  /outerHTML[[:space:]]*=/ {
    text = substr($0, index($0, "outerHTML"))
    if (has_dynamic_content(text)) print
  }
')"
legacy_escape_calls="$(rg -n 'escapeHTML\(' index.html estoque-facil.html || true)"
failed=0

while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  if grep -Eq 'escapeHTML\(' <<< "$line"; then
    printf '⚠️  Uso de escapeHTML (grafia antiga) detectado: %s\n' "$line" >&2
  fi
done <<< "$legacy_escape_calls"

while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  if ! grep -Eq 'escaparHtml\(|textContent|createElement|replaceChildren|safeIcon' <<< "$line"; then
    printf '❌ Conteúdo dinâmico em HTML sem proteção: %s\n' "$line" >&2
    failed=1
  fi
done <<< "$dynamic_sink_lines"

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
    END { if (!found) exit 2 }
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

check_builder_fields() {
  local name="$1"
  local start_marker="$2"
  local end_marker="$3"
  shift 3
  local block marker
  block="$(awk -v start="$start_marker" -v end="$end_marker" '
    !capturing && index($0, start) { capturing = 1 }
    capturing && end != "" && index($0, end) { found = 1; exit }
    capturing { print }
    END { if (!found) exit 2 }
  ' index.html)" || {
    printf '❌ Não foi possível inspecionar o template: %s\n' "$name" >&2
    failed=1
    return
  }
  for marker in "$@"; do
    if ! grep -Fq "$marker" <<< "$block"; then
      printf '❌ Campo sem proteção esperada em %s: %s\n' "$name" "$marker" >&2
      failed=1
    fi
  done
}

check_line_fields() {
  local name="$1"
  local marker="$2"
  shift 2
  local line field
  line="$(rg -n -m 1 -F "$marker" index.html || true)"
  if [[ -z "$line" ]]; then
    printf '❌ Não foi encontrada a linha de renderização: %s\n' "$name" >&2
    failed=1
    return
  fi
  for field in "$@"; do
    if ! grep -Fq "$field" <<< "$line"; then
      printf '❌ Campo sem proteção esperada em %s: %s\n' "$name" "$field" >&2
      failed=1
    fi
  done
}

check_required_marker() {
  local name="$1"
  local marker="$2"
  if ! rg -Fq "$marker" index.html; then
    printf '❌ Não foi encontrado o trecho esperado do fluxo %s: %s\n' "$name" "$marker" >&2
    failed=1
  fi
}

check_builder 'badges de estoque' 'const badges = Object.entries(counts)' 'const lotsHtml = lotes.map'
check_builder 'lotes do estoque' 'const lotsHtml = lotes.map((l, li) => {' 'const lotCountLabel ='
check_builder 'detalhes do estoque' 'window.stockDetailMarkup[groupIndex] =' 'const productIdArgument ='
check_builder 'cartão de estoque' 'const productRow =' 'tbody.insertAdjacentHTML'
check_builder_fields 'cartões móveis do relatório' 'if(mobileCards){' 'mobileCards.insertAdjacentHTML' \
  'const company=escaparHtml(' 'const product=escaparHtml(' 'const lot=escaparHtml(' \
  'const pile=escaparHtml(' 'const quantity=escaparHtml(' 'const validity=escaparHtml(' 'const days=escaparHtml('
check_line_fields 'HTML dos cartões móveis' 'mobileCards.insertAdjacentHTML' \
  'escaparHtml(statusColor)' 'escaparHtml(statusLabel)' '${product}' '${company}' \
  '${lot||' '${pile||' '${quantity}' '${validity}' '${days}'

# Dados do histórico são lidos do Supabase ou do cache offline; cada campo deve
# continuar escapado nos dois renderizadores de histórico.
check_line_fields 'histórico principal' 'tbody.innerHTML = dados.length ? dados.map' \
  'escaparHtml(h.data)' 'escaparHtml(h.produto)' 'escaparHtml(h.lote)' \
  'escaparHtml(h.pilha)' 'escaparHtml(h.qtd)' 'escaparHtml(h.unid)'
check_line_fields 'histórico atualizado' 'tbody.innerHTML=dados.length?dados.map' \
  'escaparHtml(d)' "escaparHtml(h.produto||'')" "escaparHtml(h.lote||'')" \
  "escaparHtml(h.qtd||0)" "escaparHtml(h.unid||'')"

# Notificações locais são reconstruídas de JSON salvo no localStorage. Verifica
# a rota fonte-destino e cada valor usado no HTML do cartão.
check_required_marker 'das notificações locais' 'JSON.parse(localStorage.getItem(localNoticeKey)'
check_required_marker 'das notificações locais' 'localNotices().forEach(row=>notices.push'
check_required_marker 'das notificações locais' 'list.replaceChildren(...notices.map(n=>createNotice('
check_line_fields 'cartão de notificação' 'item.innerHTML=' \
  'escaparHtml(iconClass)' "escaparHtml(title ?? '')" "escaparHtml(message ?? '')" \
  "escaparHtml(time ?? '')" 'safeIcon'
check_required_marker 'do cache offline' 'JSON.parse(localStorage.getItem(OFFLINE_STATE_KEY)'
check_required_marker 'do cache offline' 'inventoryData=v.inventoryData'
check_required_marker 'do cache offline' 'historicoEntradas=v.historicoEntradas'

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

printf '✅ Nenhuma interpolação crua detectada\n'
