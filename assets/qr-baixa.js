/* Estoque Fácil — leitura e conferência de ordens com QR. O QR não executa baixa sem confirmação. */
(() => {
  let cameraStream = null, video = null, scanner = null, scanToken = 0, order = null, activePileMenu = null;
  const el = id => document.getElementById(id);
  document.addEventListener('click', event => { if(activePileMenu&&!activePileMenu.element.contains(event.target))activePileMenu.close(); });
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
  window.resetQrBaixa = () => { activePileMenu?.close(); window.stopQrScanner(); order = null; el('qr-preview')?.classList.add('hidden'); if (el('qr-order-items')) el('qr-order-items').replaceChildren(); status('Leia o QR impresso na ordem de saída. Confira todos os itens antes de confirmar.'); };
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
    const source = typeof raw === 'string' ? raw : String(raw ?? '');
    if (Array.from(source).length > 12000) throw new Error('QR excede o limite de 12.000 caracteres.');
    let data;
    try { data = JSON.parse(source); } catch (_) { throw new Error('Formato inválido: JSON malformado.'); }
    const invalid = message => { throw new Error('Formato inválido: ' + message + '.'); };
    if (!data || typeof data !== 'object' || Array.isArray(data)) invalid('o conteúdo precisa ser um objeto JSON');
    const topKeys = ['v', 'seq_saida', 'nr_nf', 'itens'];
    const extraTopKeys = Object.keys(data).filter(key => !topKeys.includes(key));
    if (extraTopKeys.length) invalid('campo não permitido no QR v3: ' + extraTopKeys[0]);
    if (!Number.isInteger(data.v) || data.v !== 3) invalid('v precisa ser o número inteiro 3');
    if (typeof data.seq_saida !== 'string' || !data.seq_saida.trim()) invalid('seq_saida precisa ser uma string não vazia');
    if (typeof data.nr_nf !== 'string' || !data.nr_nf.trim()) invalid('nr_nf precisa ser uma string não vazia');
    if (!Array.isArray(data.itens)) invalid('itens precisa ser um array');
    if (!data.itens.length) throw new Error('QR sem itens.');
    if (data.itens.length > 50) throw new Error('QR excede o limite de 50 itens.');

    const allowedItemKeys = ['codigo', 'produto', 'lote', 'quantidade'];
    const rows = Array.isArray(currentRows()) ? currentRows() : [];
    const items = data.itens.map((item, index) => {
      const itemNumber = index + 1;
      if (!item || typeof item !== 'object' || Array.isArray(item)) invalid('item ' + itemNumber + ' precisa ser um objeto');
      const extraItemKeys = Object.keys(item).filter(key => !allowedItemKeys.includes(key));
      if (extraItemKeys.length) {
        if (extraItemKeys[0] === 'unid') invalid('campo não permitido no item: unid');
        invalid('campo não permitido no item ' + itemNumber + ': ' + extraItemKeys[0]);
      }
      if (typeof item.codigo !== 'string' || !item.codigo.trim()) invalid('codigo do item ' + itemNumber + ' precisa ser uma string não vazia');
      if (typeof item.produto !== 'string' || !item.produto.trim()) invalid('produto do item ' + itemNumber + ' precisa ser uma string não vazia');
      if (typeof item.lote !== 'string') throw new Error('Item ' + itemNumber + ': lote precisa ser string.');
      if (!item.lote.trim()) invalid('lote do item ' + itemNumber + ' não pode ser vazio');
      if (typeof item.quantidade !== 'number' || !Number.isSafeInteger(item.quantidade) || item.quantidade <= 0) {
        throw new Error('Item ' + itemNumber + ': quantidade inválida; use um número inteiro positivo sem separador.');
      }

      const codigo = item.codigo.trim();
      const produto = item.produto.trim();
      const lote = item.lote;
      const quantidade = item.quantidade;
      const lotRows = rows.filter(row => normalize(row.lote) === normalize(lote));
      const codeEntry = window.efProductCodes?.byCode(codigo) || null;
      const namedLotRows = lotRows.filter(row => normalize(row.produto) === normalize(produto));
      const stockNameRows = rows.filter(row => normalize(row.produto) === normalize(produto));
      let selectedProduct = '';
      let matchSource = '';
      let warning = '';
      let candidates = [];

      if (codeEntry?.produto) {
        selectedProduct = String(codeEntry.produto).trim();
        matchSource = 'código';
        candidates = rows.filter(row => normalize(row.produto) === normalize(selectedProduct) && normalize(row.lote) === normalize(lote));
        if (!candidates.length) {
          warning = lotRows.length
            ? 'O código está vinculado a ' + selectedProduct + ', mas não há uma pilha deste produto para o lote informado. Confira o cadastro do produto e do lote.'
            : 'O código está vinculado a ' + selectedProduct + ', mas o lote não foi encontrado no estoque. Confira o cadastro antes de adicionar à carga.';
        }
      } else if (namedLotRows.length) {
        selectedProduct = String(namedLotRows[0].produto).trim();
        matchSource = 'nome e lote';
        candidates = namedLotRows;
      } else if (stockNameRows.length) {
        selectedProduct = String(stockNameRows[0].produto).trim();
        matchSource = 'nome';
        candidates = rows.filter(row => normalize(row.produto) === normalize(selectedProduct) && normalize(row.lote) === normalize(lote));
        warning = candidates.length
          ? ''
          : 'O produto foi identificado pelo nome, mas não há uma pilha desse produto para o lote informado. Confira e escolha manualmente.';
      } else {
        candidates = lotRows;
        warning = lotRows.length
          ? 'Produto não identificado por código ou nome. Escolha manualmente o produto correspondente.'
          : 'Produto e lote sem correspondência no estoque. O item foi preservado; escolha manualmente o produto e confira o cadastro antes de adicionar à carga.';
      }

      const optionRows = lotRows.length ? lotRows : rows;
      const productOptions = [];
      const productKeys = new Set();
      for (const row of optionRows) {
        const name = String(row.produto || '').trim();
        const key = normalize(name);
        if (name && !productKeys.has(key)) { productKeys.add(key); productOptions.push(name); }
      }
      if (selectedProduct && !productKeys.has(normalize(selectedProduct))) productOptions.push(selectedProduct);

      return {codigo, produto, lote, quantidade, candidates, productOptions, selectedProduct, matchSource, warning, sameProduct:false};
    });

    const codeCounts = new Map();
    for (const item of items) {
      const key = item.codigo.trim().replace(/^0+(?=\d)/, '').toUpperCase();
      codeCounts.set(key, (codeCounts.get(key) || 0) + 1);
    }
    for (const item of items) {
      const key = item.codigo.trim().replace(/^0+(?=\d)/, '').toUpperCase();
      item.sameProduct = codeCounts.get(key) > 1;
    }
    order = {nf:data.nr_nf.trim(), seqSaida:data.seq_saida.trim(), items};
  }

  function orderSnapshot() {
    return {
      seq_saida:order.seqSaida,
      nr_nf:order.nf,
      items:order.items.map(item => ({
        codigo:item.codigo,
        produto:item.produto,
        lote:item.lote,
        quantidade:item.quantidade,
        selectedProduct:item.selectedProduct,
        candidates:item.candidates.map(row => row.id),
        productOptions:item.productOptions,
        matchSource:item.matchSource,
        warning:item.warning,
        sameProduct:item.sameProduct
      }))
    };
  }

  window.efQrV3 = Object.freeze({
    parse(raw) { parseOrder(raw); return orderSnapshot(); },
    render(raw) { parseOrder(raw); renderOrder(); return orderSnapshot(); }
  });

  function renderOrder() {
    activePileMenu?.close();
    el('qr-order-nf').textContent = 'NF ' + order.nf;
    el('qr-order-id').textContent = 'Seq. saída ' + order.seqSaida;
    const container=el('qr-order-items'); container.replaceChildren();
    const refreshItemViews=[];let refreshingItemViews=false;
    const refreshOtherItems=currentIndex=>{
      if(refreshingItemViews)return;
      refreshingItemViews=true;
      try{refreshItemViews.forEach((refresh,viewIndex)=>{if(viewIndex!==currentIndex)refresh?.();});}
      finally{refreshingItemViews=false;}
    };
    order.items.forEach((item,index)=>{
      item.allocations=[];
      const block=document.createElement('div');block.className='qr-item';
      const title=document.createElement('strong');title.textContent=item.produto;
      const info=document.createElement('small');
      info.textContent=(item.codigo?'Código '+item.codigo+' · ':'')+'Lote '+item.lote+' · Retirar '+new Intl.NumberFormat('pt-BR').format(item.quantidade);
      block.append(title,info);
      if(item.sameProduct){
        const badge=document.createElement('span');
        badge.className='qr-same-product-badge';
        badge.setAttribute('role','note');
        badge.textContent='⚠ mesmo produto';
        badge.style.cssText='display:inline-flex;align-items:center;width:max-content;margin:6px 0;padding:4px 8px;border:1px solid #f0c36d;border-radius:999px;background:#fff7df;color:#805400;font-size:11px;font-weight:800';
        block.append(badge);
      }

      const productLabel=document.createElement('label');productLabel.textContent='Produto no Estoque Fácil';productLabel.htmlFor='qr-item-produto-'+index;
      const productSelect=document.createElement('select');productSelect.id='qr-item-produto-'+index;
      productSelect.append(new Option('Selecione o produto cadastrado',''));
      [...item.productOptions].sort((a,b)=>a.localeCompare(b,'pt-BR')).forEach(product=>productSelect.append(new Option(product,product)));
      productSelect.value=item.selectedProduct || '';
      const hasSelectedProductRows=!!item.selectedProduct && item.candidates.some(row=>normalize(row.produto)===normalize(item.selectedProduct));
      if(hasSelectedProductRows) { productSelect.hidden=true; productLabel.hidden=true; }
      if(hasSelectedProductRows && item.matchSource){
        const hint=document.createElement('small');hint.className='qr-match-note';
        hint.textContent='Cadastro identificado pelo '+item.matchSource+': '+item.selectedProduct;
        block.append(hint);
      }
      if(item.warning){
        const warning=document.createElement('small');warning.className='qr-item-error';warning.textContent=item.warning;
        block.append(warning);
      }
      block.append(productLabel,productSelect);

      const allocationsList=document.createElement('div');allocationsList.id='qr-item-allocations-'+index;allocationsList.className='qr-allocation-list';
      const progress=document.createElement('div');progress.id='qr-item-progress-'+index;progress.className='qr-allocation-progress';
      const warningBox=document.createElement('div');warningBox.id='qr-item-warning-'+index;warningBox.className='qr-allocation-warning';
      const label=document.createElement('label');label.id='qr-item-pile-label-'+index;label.textContent='Escolha a pilha';label.htmlFor='qr-item-pilha-'+index;
      const picker=document.createElement('div');picker.id='qr-item-pile-picker-'+index;picker.className='qr-pile-picker';
      const toggle=document.createElement('button');toggle.type='button';toggle.id='qr-item-pilha-'+index;toggle.className='qr-pile-picker-toggle';toggle.setAttribute('aria-haspopup','menu');toggle.setAttribute('aria-expanded','false');toggle.setAttribute('aria-labelledby',label.id);
      const toggleText=document.createElement('span');toggleText.className='qr-pile-picker-caption';
      const toggleArrow=document.createElement('span');toggleArrow.className='qr-pile-picker-arrow';toggleArrow.setAttribute('aria-hidden','true');toggleArrow.textContent='▾';
      toggle.append(toggleText,toggleArrow);
      const menu=document.createElement('div');menu.id='qr-item-pile-options-'+index;menu.className='qr-pile-picker-menu';menu.setAttribute('role','menu');menu.hidden=true;toggle.setAttribute('aria-controls',menu.id);
      picker.append(toggle,menu);
      block.append(allocationsList,progress,warningBox,label,picker);
      container.append(block);

      let menuOpen=false;
      const currentCandidates=()=>currentRows().filter(row=>normalize(row.produto)===normalize(productSelect.value)&&normalize(row.lote)===normalize(item.lote));
      const allocatedForPile=(id,excludingItem=null)=>order.items.reduce((sum,other)=>sum+(other===excludingItem?0:(other.allocations||[]).reduce((subtotal,allocation)=>subtotal+(Number(allocation.pilha_id)===Number(id)?allocation.quantidade:0),0)),0);
      const allocatedForItem=()=>item.allocations.reduce((sum,allocation)=>sum+allocation.quantidade,0);
      const remaining=()=>Math.max(0,item.quantidade-allocatedForItem());
      const rowAvailable=row=>Math.max(0,Math.floor(Number(row.qtd)-allocatedForPile(row.id,item)));
      const sortPiles=(rows)=>rows.sort((a,b)=>String(a.pilha||'').trim().localeCompare(String(b.pilha||'').trim(),'pt-BR')||Number(a.id)-Number(b.id));
      const compatibleRows=()=>{
        const candidates=sortPiles(currentCandidates());
        const used=new Set(item.allocations.map(allocation=>Number(allocation.pilha_id)));
        const assignedUnit=item.allocations.length?normalize(currentRows().find(row=>Number(row.id)===Number(item.allocations[0].pilha_id))?.unid):'';
        return candidates.filter(row=>!used.has(Number(row.id))&&rowAvailable(row)>0&&(!assignedUnit||normalize(row.unid)===assignedUnit));
      };
      const totalAvailable=()=>{
        const rows=currentCandidates();
        const units=item.allocations.length?[normalize(currentRows().find(row=>Number(row.id)===Number(item.allocations[0].pilha_id))?.unid)]:[...new Set(rows.map(row=>normalize(row.unid)))];
        return Math.max(0,...units.map(unit=>rows.filter(row=>normalize(row.unid)===unit).reduce((sum,row)=>sum+Math.max(0,Number(row.qtd)-allocatedForPile(row.id,item)),0)));
      };
      const closeMenu=()=>{
        menuOpen=false;menu.hidden=true;toggle.setAttribute('aria-expanded','false');block.classList.remove('qr-dropdown-open');
        if(activePileMenu?.element===picker)activePileMenu=null;
      };
      const openMenu=()=>{
        if(!compatibleRows().length)return;
        if(activePileMenu&&activePileMenu.element!==picker)activePileMenu.close();
        menuOpen=true;menu.hidden=false;toggle.setAttribute('aria-expanded','true');block.classList.add('qr-dropdown-open');
        activePileMenu={element:picker,close:closeMenu};
      };
      const renderAllocationState=(rows=compatibleRows())=>{
        allocationsList.replaceChildren();
        item.allocations.forEach((allocation,allocationIndex)=>{
          const row=currentRows().find(candidate=>Number(candidate.id)===Number(allocation.pilha_id));
          const entry=document.createElement('div');entry.className='qr-allocation-row';
          const text=document.createElement('span');text.textContent='✓ '+(row?.pilha||'Pilha '+allocation.pilha_id)+' · '+new Intl.NumberFormat('pt-BR').format(allocation.quantidade)+(row?.unid?' '+row.unid:'')+(allocation.esgotada?' (esgotada)':'');
          const remove=document.createElement('button');remove.type='button';remove.className='qr-allocation-remove';remove.textContent='Remover';remove.setAttribute('aria-label','Remover alocação da pilha '+(row?.pilha||allocation.pilha_id));
          remove.addEventListener('click',()=>{item.allocations.splice(allocationIndex,1);refreshPiles(false);refreshOtherItems(index);});
          entry.append(text,remove);allocationsList.append(entry);
        });
        const unit=item.allocations.length?currentRows().find(row=>Number(row.id)===Number(item.allocations[0].pilha_id))?.unid:(currentCandidates()[0]?.unid||'');
        const quantityUnit=unit?' '+unit:'';
        const allocated=allocatedForItem(),left=remaining();
        progress.textContent=left===0?'Total: '+new Intl.NumberFormat('pt-BR').format(allocated)+' de '+new Intl.NumberFormat('pt-BR').format(item.quantidade)+quantityUnit+' ✅ Completo':'⏳ Faltam '+new Intl.NumberFormat('pt-BR').format(left)+quantityUnit;
        const capacity=totalAvailable();
        warningBox.className='qr-allocation-warning';
        if(!currentCandidates().length){warningBox.textContent='Não há pilha compatível para este produto e lote. Escolha o produto correto ou confira o cadastro.';}
        else if(capacity<item.quantidade){warningBox.textContent='⚠ Saldo total insuficiente: disponível '+new Intl.NumberFormat('pt-BR').format(capacity)+quantityUnit+'; faltam '+new Intl.NumberFormat('pt-BR').format(item.quantidade-capacity)+quantityUnit+'.';}
        else if(left===0&&capacity>item.quantidade){warningBox.className='qr-allocation-note';warningBox.textContent='Total das pilhas: '+new Intl.NumberFormat('pt-BR').format(capacity)+quantityUnit+'. Sobra '+new Intl.NumberFormat('pt-BR').format(capacity-item.quantidade)+quantityUnit+'.';}
        else if(left>0&&!currentCandidates().some(row=>rowAvailable(row)>=left)){warningBox.textContent='Distribua a quantidade entre as pilhas.';}
        else {warningBox.textContent='';}
        const next=rows[0];
        toggle.hidden=left===0||!next;
        if(next){
          const preview='Pilha '+next.pilha+' · disponível '+new Intl.NumberFormat('pt-BR').format(rowAvailable(next))+(next.unid?' '+next.unid:'');
          toggleText.textContent=preview;
          toggle.setAttribute('aria-label','Escolher pilha. Próxima opção: '+preview);
        }else toggleText.textContent='Item completo';
        if(!next)closeMenu();
      };
      function choosePile(row){
        const current=compatibleRows().find(candidate=>Number(candidate.id)===Number(row.id));
        if(!current){closeMenu();refreshPiles(false);return;}
        const available=rowAvailable(current),left=remaining(),amount=Math.min(available,left);
        if(amount<=0){closeMenu();refreshPiles(false);return;}
        item.allocations.push({pilha_id:Number(current.id),quantidade:amount,esgotada:amount===available});
        closeMenu();refreshPiles(false);refreshOtherItems(index);
      }
      function refreshPiles(initial=false){
        const rows=compatibleRows();
        menu.replaceChildren();
        rows.forEach(row=>{
          const option=document.createElement('button');option.type='button';option.className='qr-pile-picker-option';option.setAttribute('role','menuitem');option.dataset.stockId=String(row.id);
          option.textContent='Pilha '+row.pilha+' · disponível '+new Intl.NumberFormat('pt-BR').format(rowAvailable(row))+(row.unid?' '+row.unid:'');
          option.addEventListener('click',()=>choosePile(row));
          menu.append(option);
        });
        renderAllocationState(rows);
        if(initial&&!item.allocations.length&&rows.length){
          const full=rows.some(row=>rowAvailable(row)>=remaining());
          if(full&&rowAvailable(rows[0])<=remaining())choosePile(rows[0]);
          else validatePreview();
        }else validatePreview();
      }
      toggle.addEventListener('click',()=>menuOpen?closeMenu():openMenu());
      menu.addEventListener('keydown',event=>{if(event.key==='Escape'){closeMenu();toggle.focus();}});
      productSelect.addEventListener('change',()=>{item.allocations=[];closeMenu();refreshPiles(true);refreshOtherItems(index);});
      refreshItemViews[index]=()=>refreshPiles(false);
      refreshPiles(true);
    });
    el('qr-preview').classList.remove('hidden');validatePreview();
  }

  function allocations() {
    if (!order) throw new Error('Leia o QR antes de confirmar.');
    const claimed=new Map(),merged=new Map();
    order.items.forEach((item,index)=>{
      const allocated=(item.allocations||[]).reduce((sum,allocation)=>sum+allocation.quantidade,0);
      if(allocated!==item.quantidade) throw new Error('Item '+(index+1)+': faltam '+(item.quantidade-allocated)+' para completar a quantidade do QR.');
      if(!item.allocations.length) throw new Error('Item '+(index+1)+': escolha uma pilha compatível.');
      for(const allocation of item.allocations){
        const id=Number(allocation.pilha_id),row=currentRows().find(candidate=>Number(candidate.id)===id);
        if(!row||normalize(row.produto)!==normalize(el('qr-item-produto-'+index).value)||normalize(row.lote)!==normalize(item.lote)) throw new Error('A pilha selecionada não corresponde ao produto e lote do item '+(index+1)+'.');
        claimed.set(id,(claimed.get(id)||0)+allocation.quantidade);
        const previous=merged.get(id);
        if(previous){previous.qtd+=allocation.quantidade;}
        else merged.set(id,{produto:row.produto,lote:item.lote,unid:row.unid,qtd:allocation.quantidade,estoque_id:id});
      }
    });
    for (const [id,qtd] of claimed) {
      const row=currentRows().find(item=>Number(item.id)===id);
      if(!row||Number(row.qtd)<qtd) throw new Error('Saldo insuficiente na pilha '+(row?.pilha||id)+'.');
    }
    return [...merged.values()];
  }

  function confirmExistingNfMerge() {
    let draft;
    try { draft = JSON.parse(localStorage.getItem('estoquefacil_carga_draft_v1') || 'null'); }
    catch (_) { return true; }
    if (!draft || typeof draft !== 'object') return true;
    const existingNfs = Array.isArray(draft.nfs) ? draft.nfs.map(value => String(value).trim()) : (draft.nf ? [String(draft.nf).trim()] : []);
    if (!existingNfs.some(value => normalize(value) === normalize(order.nf))) return true;
    const existingOrders = Array.isArray(draft.qrOrders) ? draft.qrOrders.map(String) : [];
    if (existingOrders.includes(order.seqSaida)) return true;
    return window.confirm('A NF ' + order.nf + ' já está no rascunho e este QR informa outra sequência de saída (' + order.seqSaida + '). Deseja somar os itens deste QR à NF existente? O chip da NF continuará aparecendo uma única vez.');
  }

  function validatePreview() { try { allocations();el('qr-confirm-button').disabled=false;status('QR validado. Adicione os itens à carga para continuar.'); } catch(error) {el('qr-confirm-button').disabled=true;status(error.message,true);} }
  window.addQrItemsToCarga = () => {
    if (!usuarioAdminAutorizado) return status('Entre como administrador para adicionar itens à carga.',true);
    const button=el('qr-confirm-button');button.disabled=true;
    try {
      if(!confirmExistingNfMerge()) { button.disabled=false; status('A inclusão foi cancelada. A NF permanece no rascunho sem receber os itens deste QR.',true); return; }
      const items=allocations();
      const accepted=window.addQrOrderItemsToCarga?.({seqSaida:order.seqSaida,nf:order.nf,nfs:[order.nf],serie:'',filial:'1',items});
      if (!accepted) { button.disabled=false; return; }
      const nf=order.nf,count=items.length;
      window.resetQrBaixa();
      status('Itens da NF '+nf+' adicionados à carga ('+count+' '+(count===1?'item':'itens')+').');
    } catch (error) {status(error.message||'Não foi possível adicionar os itens do QR.',true);button.disabled=false;}
  };
})();

