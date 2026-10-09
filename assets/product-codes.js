/* Códigos do sistema emissor vinculados ao nome cadastrado no Estoque Fácil. */
(() => {
  let entries = null;
  let pending = null;
  let officialCatalog = null;
  const normalized = value => String(value ?? '').trim().replace(/\s+/g, ' ').toUpperCase();
  const normalizedCode = value => String(value ?? '').trim().replace(/^0+(?=\d)/, '');
  const sameCode = (left,right) => normalizedCode(left) === normalizedCode(right);
  async function load(force = false) {
    if (entries && !force) return entries;
    if (pending && !force) return pending;
    pending = (async () => {
      const headers = await window.authHeaders?.();
      if (!headers) { window.efRequireLogin?.(); entries = []; return entries; }
      const r = await fetch(SUPABASE_URL + '/rest/v1/ef_produtos_codigos?select=codigo,produto,empresa,bula_url,bula_dados', {headers});
      if (!r.ok) throw new Error('Cadastro de códigos indisponível. Execute a migração SQL dos códigos no Supabase.');
      entries = await r.json();
      return entries;
    })();
    try { return await pending; } finally { pending = null; }
  }
  async function save(product, rawCode) {
    if (!usuarioAdminAutorizado || !navigator.onLine || offlineQueue().length) throw new Error('Entre como administrador, conecte-se e sincronize as alterações pendentes.');
    const code = String(rawCode ?? '').trim();
    if (code && !/^\d{1,16}$/.test(code)) throw new Error('Digite apenas os números do código, preservando zeros à esquerda.');
    const list = await load(true);
    const current = list.find(entry => normalized(entry.produto) === normalized(product));
    if (current && sameCode(code,current.codigo)) return;
    const occupied = code && list.find(entry => sameCode(entry.codigo,code) && normalized(entry.produto) !== normalized(product));
    if (occupied && inventoryData.some(row => normalized(row.produto) === normalized(occupied.produto))) throw new Error(`Código ${code} ainda vinculado a ${occupied.produto} no estoque. Confira esse cadastro antes de reutilizar.`);
    const session = await sessaoDeEscrita();
    const path = '/rest/v1/ef_produtos_codigos';
    let method, url = SUPABASE_URL + path, body;
    if (occupied && current) throw new Error('O produto já possui outro código. Remova o vínculo antigo antes de reutilizar este código.');
    if (occupied) {
      url += '?codigo=eq.' + encodeURIComponent(occupied.codigo);
      method = 'PATCH';body = JSON.stringify({produto:product});
    } else if (current) {
      url += '?produto=eq.' + encodeURIComponent(current.produto);
      method = code ? 'PATCH' : 'DELETE';
      if (code) body = JSON.stringify({codigo:code});
    } else if (code) {
      method = 'POST';body = JSON.stringify({codigo:code,produto:product});
    } else return;
    const response = await fetch(url,{method,headers:{...supabaseHeaders,Authorization:'Bearer '+session.access_token},body});
    if (!response.ok) throw new Error(response.status === 409 ? 'Código ou produto já vinculado a outro cadastro.' : 'Não foi possível salvar o código ('+response.status+').');
    await load(true);
    officialCatalog = null;
  }
  async function catalog() {
    if (officialCatalog) return officialCatalog;
    let rows;
    try {
      rows = await load();
    } catch (error) {
      try { rows = JSON.parse(localStorage.getItem('ef_product_catalog_cache_v1') || '[]'); }
      catch { rows = []; }
      if (!rows.length) throw error;
    }
    officialCatalog = rows
      .filter(row => row.codigo != null && String(row.codigo).trim() && row.produto)
      .map(row => ({...row, codigo:String(row.codigo).trim(), produto:String(row.produto).trim()}))
      .sort((a,b) => a.produto.localeCompare(b.produto, 'pt-BR', {sensitivity:'base'}));
    try {
      localStorage.setItem('ef_product_catalog_cache_v1', JSON.stringify(officialCatalog.map(({codigo,produto,empresa}) => ({codigo,produto,empresa}))));
    } catch {}
    return officialCatalog;
  }
  async function saveBula(product, url, dados = {}) {
    const entry = (await load(true)).find(row => normalized(row.produto) === normalized(product));
    if (!entry) throw new Error('Vincule o código do produto antes de guardar a bula.');
    const session = await sessaoDeEscrita();
    const response = await fetch(SUPABASE_URL + '/rest/v1/ef_produtos_codigos?codigo=eq.' + encodeURIComponent(entry.codigo), {
      method:'PATCH', headers:{...supabaseHeaders,Authorization:'Bearer '+session.access_token},
      body:JSON.stringify({bula_url:url,bula_dados:dados})
    });
    if (!response.ok) throw new Error('A bula foi enviada, mas não foi guardada no cadastro permanente (' + response.status + ').');
    entry.bula_url=url;
    entry.bula_dados=dados;
  }
  async function saveCompany(product, company) {
    const value = normalized(company);
    if (!value) return;
    const entry = (await load()).find(row => normalized(row.produto) === normalized(product));
    if (!entry) throw new Error('Vincule o código do produto para guardar a empresa.');
    if (normalized(entry.empresa) === value) return;
    const session = await sessaoDeEscrita();
    const response = await fetch(SUPABASE_URL + '/rest/v1/ef_produtos_codigos?codigo=eq.' + encodeURIComponent(entry.codigo), {
      method:'PATCH', headers:{...supabaseHeaders,Authorization:'Bearer '+session.access_token},
      body:JSON.stringify({empresa:value})
    });
    if (!response.ok) throw new Error('Não foi possível guardar a empresa no cadastro permanente (' + response.status + ').');
    entry.empresa=value;
  }
  window.efProductCodes = {load, save, saveBula, saveCompany, sameCode, catalog, catalogEntries:()=>officialCatalog||[], byCode:code => entries?.find(entry => sameCode(entry.codigo,code)), byProduct:product => entries?.find(entry => normalized(entry.produto) === normalized(product))};
})();
