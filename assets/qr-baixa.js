/* Estoque Fácil — leitura e conferência de ordens com QR. O QR não executa baixa sem confirmação. */
(() => {
  let cameraStream = null, video = null, scanner = null, scanToken = 0, order = null;
  const el = id => document.getElementById(id);
  const normalize = value => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim().toUpperCase().replace(/\s+/g, ' ');
  const status = (message, error = false) => { const box = el('qr-status'); if (box) { box.textContent = message; box.classList.toggle('is-error', error); } };
  const currentRows = () => inventoryData;
  const library = () => new Promise((resolve, reject) => {
    if (window.Html5Qrcode) return resolve(window.Html5Qrcode);
    const existing = document.getElementById('qr-reader-library');
    if (existing) { existing.addEventListener('load', () => resolve(window.Html5Qrcode), {once:true}); existing.addEventListener('error', reject, {once:true}); return; }
    const script = document.createElement('script'); script.id = 'qr-reader-library';
    script.src = 'https://unpkg.com/html5-qrcode@2.3.8/html5-qrcode.min.js';
    script.onload = () => window.Html5Qrcode ? resolve(window.Html5Qrcode) : reject(new Error('Leitor de QR indisponível.'));
    script.onerror = () => reject(new Error('Não foi possível carregar o leitor de QR.'));
    document.head.appendChild(script);
  });
  const nativeDetector = async () => {
    if (!window.BarcodeDetector) return null;
    const formats = await BarcodeDetector.getSupportedFormats().catch(() => []);
    return formats.includes('qr_code') ? new BarcodeDetector({formats:['qr_code']}) : null;
  };
  window.stopQrScanner = async () => {
    scanToken++;
    cameraStream?.getTracks().forEach(track => track.stop()); cameraStream = null;
    if (video) { video.pause(); video.srcObject = null; video.remove(); video = null; }
    if (scanner) { const previous = scanner; scanner = null; await previous.stop().catch(() => {}); try { await previous.clear(); } catch (_) {} }
    el('qr-reader')?.classList.add('hidden');
  };
  window.resetQrBaixa = () => { window.stopQrScanner(); order = null; el('qr-preview')?.classList.add('hidden'); if (el('qr-order-items')) el('qr-order-items').replaceChildren(); status('Leia o QR impresso na ordem de saída. Confira todos os itens antes de confirmar.'); };
  const decoded = async value => { await window.stopQrScanner(); try { await window.efProductCodes.load(true); parseOrder(value); renderOrder(); status('QR lido. Confira os itens, as pilhas e a NF.'); } catch (error) { order = null; el('qr-preview')?.classList.add('hidden'); status(error.message, true); } };
  window.startQrScanner = async () => {
    await window.stopQrScanner(); const token = ++scanToken; const reader = el('qr-reader'); reader.classList.remove('hidden'); reader.replaceChildren();
    status('Abrindo a câmera…');
    try {
      const detector = await nativeDetector();
      if (detector) {
        cameraStream = await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'}},audio:false});
        video = document.createElement('video'); video.setAttribute('playsinline',''); video.muted = true; video.autoplay = true; video.srcObject = cameraStream; reader.appendChild(video); await video.play();
        const scan = async () => { if (token !== scanToken) return; try { const results = await detector.detect(video); if (results.length) return decoded(results[0].rawValue); } catch (_) {} setTimeout(scan, 150); };
        scan();
      } else {
        const Html5Qrcode = await library(); if (token !== scanToken) return;
        scanner = new Html5Qrcode('qr-reader');
        await scanner.start({facingMode:'environment'}, {fps:10,qrbox:{width:240,height:240}}, value => decoded(value), () => {});
      }
      status('Aponte a câmera para o QR da ordem.');
    } catch (error) { await window.stopQrScanner(); status('Não foi possível abrir a câmera. Você pode selecionar uma imagem com QR. '+(error.message||''), true); }
  };
  window.readQrImage = async file => {
    if (!file) return;
    await window.stopQrScanner(); status('Lendo QR da imagem…');
    try {
      const detector = await nativeDetector(); let value;
      if (detector) { const bitmap = await createImageBitmap(file); try { value = (await detector.detect(bitmap))[0]?.rawValue; } finally { bitmap.close(); } }
      else { const Html5Qrcode = await library(); const reader = el('qr-reader'); reader.classList.remove('hidden'); scanner = new Html5Qrcode('qr-reader'); value = await scanner.scanFile(file, false); try { await scanner.clear(); } catch (_) {} scanner = null; reader.classList.add('hidden'); }
      if (!value) throw new Error('Nenhum QR encontrado na imagem.');
      await decoded(value);
    } catch (error) { status(error.message||'Não foi possível ler o QR.', true); }
  };
  function parseOrder(raw) {
    if (String(raw).length > 12000) throw new Error('QR maior que o formato permitido.');
    let data; try { data = JSON.parse(raw); } catch (_) { throw new Error('Formato de QR inválido. Esta ordem precisa usar o padrão Estoque Fácil.'); }
    if (data?.tipo !== 'EF-BAIXA' || data.v !== 1) throw new Error('Este QR não é uma ordem de baixa do Estoque Fácil.');
    const nf = String(data.nf||'').trim(), serie = String(data.serie||'').trim();
    const seqSaida = String(data.seq_saida||'').trim();
    const filial = String(data.filial||'1').trim();
    const ordem = String(data.ordem||`SAIDA-${filial}-${seqSaida}`).trim();
    if (!nf || (!seqSaida && !data.ordem) || !filial || !Array.isArray(data.itens) || !data.itens.length || data.itens.length > 50) throw new Error('QR sem NF, sequência de saída ou itens válidos.');
    const items = data.itens.map((item, index) => {
      const produto=String(item.produto||'').trim(), codigo=String(item.codigo||'').trim(), lote=String(item.lote||'').trim(), unid=String(item.unid||'').trim(), qtd=Number(item.qtd);
      if (!produto || !lote || !unid || !Number.isSafeInteger(qtd) || qtd < 1) throw new Error(`Item ${index+1} do QR está incompleto.`);
      const codeMatch=codigo?window.efProductCodes.byCode(codigo):null;
      const codeRows=codeMatch?currentRows().filter(row=>normalize(row.produto)===normalize(codeMatch.produto)&&normalize(row.lote)===normalize(lote)):[];
      const candidates=currentRows().filter(row=>normalize(row.lote)===normalize(lote)&&normalize(row.unid)===normalize(unid)&&(!codeMatch||normalize(row.produto)===normalize(codeMatch.produto)));
      const exact=candidates.filter(row=>normalize(row.produto)===normalize(produto));
      const products=[...new Map(candidates.map(row=>[normalize(row.produto),row.produto])).values()];
      const selectedProduct=codeMatch?codeMatch.produto:(!codigo&&exact.length?exact[0].produto:(!codigo&&products.length===1?products[0]:''));
      return {produto,codigo,lote,unid,qtd,candidates,codeProduct:codeMatch?.produto||'',codeUnits:[...new Set(codeRows.map(row=>row.unid))],selectedProduct,matchedByCode:!!codeMatch,matchedByLot:!codigo&&!exact.length&&products.length===1};
    });
    order={ordem,nf,seqSaida,filial,serie,items};
  }
  function renderOrder() {
    el('qr-order-nf').textContent=`NF ${order.nf}`; el('qr-order-id').textContent=order.seqSaida?`Seq. saída ${order.seqSaida}`:`Ordem ${order.ordem}`;
    const container=el('qr-order-items'); container.replaceChildren();
    order.items.forEach((item,index)=>{
      const block=document.createElement('div');block.className='qr-item';
      const title=document.createElement('strong');title.textContent=item.produto;
      const info=document.createElement('small');info.textContent=`${item.codigo?'Código '+item.codigo+' · ':''}Lote ${item.lote} · Retirar ${item.qtd} ${item.unid}`;
      const productLabel=document.createElement('label');productLabel.textContent='Produto no Estoque Fácil';productLabel.htmlFor=`qr-item-produto-${index}`;
      const productSelect=document.createElement('select');productSelect.id=`qr-item-produto-${index}`;
      const products=[...new Map(item.candidates.map(row=>[normalize(row.produto),row.produto])).values()].sort((a,b)=>a.localeCompare(b,'pt-BR'));
      productSelect.append(new Option('Selecione o produto cadastrado',''));
      products.forEach(product=>productSelect.append(new Option(product,product)));
      productSelect.value=item.selectedProduct;
      if(item.selectedProduct) productSelect.hidden=true,productLabel.hidden=true;
      if((item.matchedByCode&&item.candidates.length)||item.matchedByLot){const hint=document.createElement('small');hint.className='qr-match-note';hint.textContent=`Cadastro identificado pelo ${item.matchedByCode?'código':'lote'}: ${item.selectedProduct}`;block.append(title,info,hint,productLabel,productSelect);}
      else if(!item.selectedProduct && products.length){const hint=document.createElement('small');hint.className='qr-item-error';hint.textContent=item.codigo?'Código ainda não cadastrado. Confira o produto correspondente ao lote.':'Há mais de um produto com este lote. Confira e selecione o cadastro correto.';block.append(title,info,hint,productLabel,productSelect);}
      else block.append(title,info,productLabel,productSelect);
      const label=document.createElement('label');label.textContent='Pilha de saída';label.htmlFor=`qr-item-pilha-${index}`;
      const select=document.createElement('select');select.id=`qr-item-pilha-${index}`;select.dataset.qrIndex=String(index);
      const fillPiles=()=>{
        const rows=item.candidates.filter(row=>normalize(row.produto)===normalize(productSelect.value));
        select.replaceChildren(new Option('Escolha a pilha',''));
        rows.forEach(row=>select.append(new Option(`Armazém 0${row.armazem} · Pilha ${row.pilha} · disponível ${row.qtd} ${row.unid}`,String(row.id))));
        if(rows.length===1 && Number(rows[0].qtd)>=item.qtd) select.value=String(rows[0].id);
        validatePreview();
      };
      productSelect.addEventListener('change',fillPiles);
      select.addEventListener('change',validatePreview);
      if(!item.candidates.length){label.hidden=true;select.hidden=true;}
      block.append(label,select);
      if(!item.candidates.length){const warning=document.createElement('small');warning.className='qr-item-error';warning.textContent=item.matchedByCode?`Divergência: código ${item.codigo} está vinculado a ${item.codeProduct}${item.codeUnits.length?' ('+item.codeUnits.join(', ')+')':''}; a ordem pede ${item.produto} em ${item.unid}. Não há pilha compatível com este lote e unidade. Confira o cadastro e a ordem.`:'Lote e unidade não encontrados no estoque. Confira o cadastro.';block.append(warning);}
      container.append(block);
      fillPiles();
    });
    el('qr-preview').classList.remove('hidden');validatePreview();
    el('content-baixa-foto').scrollTop=0;
  }
  function allocations() {
    if (!order) throw new Error('Leia o QR antes de confirmar.');
    const claimed=new Map();
    const items=order.items.map((item,index)=>{
      if(!item.candidates.length) throw new Error(`Divergência no item ${index+1}: confira código, lote e unidade.`);
      const id=Number(el(`qr-item-pilha-${index}`).value);
      const product=el(`qr-item-produto-${index}`).value;
      const row=item.candidates.find(candidate=>Number(candidate.id)===id && normalize(candidate.produto)===normalize(product));
      if(!row) throw new Error(`Escolha a pilha do item ${index+1}.`);
      claimed.set(id,(claimed.get(id)||0)+item.qtd);
      return {produto:row.produto,lote:item.lote,unid:item.unid,qtd:item.qtd,estoque_id:id};
    });
    for (const [id,qtd] of claimed) { const row=currentRows().find(item=>Number(item.id)===id); if(!row||Number(row.qtd)<qtd) throw new Error(`Saldo insuficiente na pilha ${row?.pilha||id}.`); }
    return items;
  }
  function validatePreview() { try { allocations();el('qr-confirm-button').disabled=false;status('Itens conferidos. Confira a NF e confirme a baixa.'); } catch(error) {el('qr-confirm-button').disabled=true;status(error.message,true);} }
  window.confirmQrBaixa = async () => {
    if (!usuarioAdminAutorizado) return status('Entre como administrador para dar baixa.',true);
    if (!navigator.onLine || offlineQueue().length) return status('Conecte-se e sincronize as alterações pendentes antes da baixa por QR.',true);
    const button=el('qr-confirm-button');button.disabled=true;
    try {
      const items=allocations(); const session=await sessaoDeEscrita();
      const response=await fetch(SUPABASE_URL+'/rest/v1/rpc/ef_confirmar_baixa_qr',{method:'POST',headers:{...supabaseHeaders,Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'},body:JSON.stringify({p_ordem:order.ordem,p_nf:order.nf,p_filial:order.filial,p_serie:order.serie,p_itens:items})});
      if(!response.ok){const detail=await response.json().catch(()=>({}));throw new Error(detail.message||`Falha ao confirmar a baixa (${response.status}).`);}
      const nf=order.nf;await recarregarEstoque();await carregarHistoricosSupabase().catch(()=>{});window.refreshOverviewMovements?.();window.updateDashboardCards?.();
      window.toggleBaixaModal();alert(`Baixa da NF ${nf} confirmada para ${items.length} ${items.length===1?'item':'itens'}.`);
    } catch (error) {status(error.message||'A baixa não foi confirmada. Confira o estoque antes de tentar novamente.',true);button.disabled=false;}
  };
})();
