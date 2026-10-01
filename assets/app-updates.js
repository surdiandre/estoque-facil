(() => {
  const VERSION = '211';
  let readyVersion = null;
  const status = text => {const el=document.getElementById('app-update-status');if(el)el.textContent=text;};
  function offer(version) {
    if (!version || version === VERSION) return;
    readyVersion=version;
    status(`Versão ${version} pronta. Salve qualquer formulário aberto antes de atualizar.`);
    const button=document.getElementById('app-update-apply');if(button)button.hidden=false;
  }
  window.applyAppUpdate = () => {
    if(!readyVersion)return;
    if(typeof offlineQueue==='function'&&offlineQueue().length){status('Sincronize as alterações pendentes antes de atualizar.');return;}
    location.reload();
  };
  function workerVersion(worker) {
    return new Promise(resolve=>{
      if(!worker)return resolve(null);
      const channel=new MessageChannel();
      const timer=setTimeout(()=>{channel.port1.close();resolve(null);},2500);
      channel.port1.onmessage=e=>{clearTimeout(timer);channel.port1.close();resolve(e.data?.version||null);};
      worker.postMessage({type:'GET_VERSION'},[channel.port2]);
    });
  }
  window.checkAppUpdate = async () => {
    const button=document.getElementById('app-update-check');button.disabled=true;
    try {
      if(!navigator.onLine)throw new Error('Conecte-se à internet para verificar atualizações.');
      status('Verificando a versão publicada…');
      const response=await fetch('./app-version.json?t='+Date.now(),{cache:'no-store'});
      if(!response.ok)throw new Error('Não foi possível consultar a versão publicada. Tente novamente.');
      const remote=await response.json();
      if(!/^\d+$/.test(String(remote.version)))throw new Error('A versão publicada não pôde ser identificada.');
      if(String(remote.version)===VERSION){status('Você está usando a versão mais recente: v'+VERSION+'.');return;}
      if(!('serviceWorker' in navigator))throw new Error('Nova versão disponível. Feche e abra a página para atualizar.');
      const registration=await navigator.serviceWorker.getRegistration();
      if(!registration)throw new Error('Feche e abra o aplicativo para carregar a nova versão.');
      await registration.update();
      const current=await workerVersion(registration.active);
      if(current===String(remote.version)){offer(current);return;}
      status('Nova versão encontrada. Baixando os arquivos; o botão de atualização aparecerá quando estiver pronta.');
    } catch(e){status(e.message||'Não foi possível verificar a atualização.');}
    finally{button.disabled=false;}
  };
  if('serviceWorker' in navigator && /^https?:$/.test(location.protocol)){
    navigator.serviceWorker.addEventListener('message',e=>{if(e.data?.type==='APP_UPDATED')offer(e.data.version);});
    navigator.serviceWorker.register('./sw.js',{updateViaCache:'none'}).then(r=>r.update()).catch(()=>{});
  }
})();
