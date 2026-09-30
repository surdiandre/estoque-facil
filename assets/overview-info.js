(() => {
  const CACHE_KEY = 'estoque-facil-overview-movements-v1';
  const ZONE = 'America/Sao_Paulo';
  const FIFTEEN_MINUTES = 15 * 60 * 1000;
  let pending = false;
  let lastAttempt = 0;

  function today() {
    const parts = new Intl.DateTimeFormat('pt-BR', {timeZone:ZONE, year:'numeric', month:'2-digit', day:'2-digit'}).formatToParts(new Date());
    const pick = type => parts.find(part => part.type === type).value;
    return `${pick('year')}-${pick('month')}-${pick('day')}`;
  }
  function clock(date) { return new Intl.DateTimeFormat('pt-BR', {timeZone:ZONE,hour:'2-digit',minute:'2-digit'}).format(date); }
  function readCache() {
    try {
      const saved = JSON.parse(localStorage.getItem(CACHE_KEY) || 'null');
      return saved?.day === today() && Number.isFinite(saved.entries) && Number.isFinite(saved.exits) ? saved : null;
    } catch { return null; }
  }
  function saveCache(value) { try { localStorage.setItem(CACHE_KEY,JSON.stringify(value)); } catch { /* Armazenamento indisponível. */ } }
  function render(data, saved = false) {
    document.getElementById('overview-entries-count').textContent = data?.entries ?? '—';
    document.getElementById('overview-exits-count').textContent = data?.exits ?? '—';
    document.getElementById('overview-movements-status').textContent = data
      ? `${saved ? 'Dados salvos' : 'Atualizado'} às ${clock(new Date(data.updated))}`
      : 'Movimentações indisponíveis no momento.';
  }
  async function countFor(table, day) {
    const url = `${SUPABASE_URL}/rest/v1/${table}?select=id&data=eq.${day}`;
    const response = await fetch(url,{headers:{...supabaseHeaders,Prefer:'count=exact'},signal:AbortSignal.timeout(9000)});
    if (!response.ok) throw new Error(`Histórico ${response.status}`);
    const match = /\/(\d+)$/.exec(response.headers.get('content-range') || '');
    if (match) return Number(match[1]);
    const rows = await response.json();
    if (!Array.isArray(rows) || rows.length >= 1000) throw new Error('Contagem incompleta');
    return rows.length;
  }
  async function refresh(force = false) {
    if (!document.getElementById('overview-movements-title') || pending || document.hidden) return;
    const cached = readCache();
    if (cached) render(cached, true);
    if (!navigator.onLine) { if (!cached) render(null); return; }
    if (!force && Date.now() - lastAttempt < FIFTEEN_MINUTES) return;
    pending = true;
    lastAttempt = Date.now();
    try {
      const day = today();
      const [entries,exits] = await Promise.all([countFor('historico_entradas',day),countFor('historico_saidas',day)]);
      if (day !== today()) { lastAttempt = 0; return; }
      const result = {day,entries,exits,updated:Date.now()};
      saveCache(result);
      render(result);
    } catch {
      if (!cached) render(null);
    } finally { pending = false; }
  }
  window.refreshOverviewMovements = () => refresh(true);
  function init() {
    if (!document.getElementById('overview-movements-title')) return;
    refresh();
    window.addEventListener('online',()=>refresh(true),{passive:true});
    document.addEventListener('visibilitychange',()=>{if (!document.hidden) refresh();});
    window.setInterval(()=>{if (!document.hidden && document.getElementById('page-overview')?.classList.contains('is-active')) refresh();},FIFTEEN_MINUTES);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded',init,{once:true});
  else init();
})();
