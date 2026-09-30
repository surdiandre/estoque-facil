(() => {
  // Ajuste estes dados se a cooperativa quiser acompanhar outra unidade.
  const WEATHER_LOCATION = Object.freeze({
    label: 'Campos Novos · SC',
    latitude: -27.4019,
    longitude: -51.2257,
    timeZone: 'America/Sao_Paulo'
  });
  const API_URL = `https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=${WEATHER_LOCATION.latitude}&lon=${WEATHER_LOCATION.longitude}`;
  const CACHE_KEY = 'estoque-facil-weather-v4-campos-novos';
  const FALLBACK_CACHE_MS = 4 * 60 * 60 * 1000;
  const STALE_LIMIT_MS = 12 * 60 * 60 * 1000;
  const RETRY_MS = 15 * 60 * 1000;
  const icons = {
    clear: 'fa-sun', night: 'fa-moon', partly: 'fa-cloud-sun', cloud: 'fa-cloud',
    rain: 'fa-cloud-rain', shower: 'fa-cloud-showers-heavy', thunder: 'fa-cloud-bolt',
    fog: 'fa-smog', snow: 'fa-snowflake'
  };
  let nextRetryAt = 0;
  let pending = false;

  function element(id) { return document.getElementById(id); }
  function setText(id, value) { const node = element(id); if (node) node.textContent = value; }
  function setRefreshing(value) {
    const button = element('weather-refresh-button');
    if (!button) return;
    button.disabled = value;
    button.classList.toggle('is-refreshing', value);
    button.setAttribute('aria-busy', String(value));
  }
  function displayNumber(number, digits = 0) {
    return new Intl.NumberFormat('pt-BR', {maximumFractionDigits:digits, minimumFractionDigits:digits}).format(number);
  }
  function timeLabel(date) {
    return new Intl.DateTimeFormat('pt-BR', {timeZone:WEATHER_LOCATION.timeZone, hour:'2-digit', minute:'2-digit'}).format(date);
  }
  function dateParts(date) {
    const parts = new Intl.DateTimeFormat('pt-BR', {timeZone:WEATHER_LOCATION.timeZone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',hourCycle:'h23'}).formatToParts(date);
    const pick = type => parts.find(part => part.type === type).value;
    return {key:`${pick('year')}-${pick('month')}-${pick('day')}`, hour:Number(pick('hour'))};
  }
  function describeSymbol(code = '') {
    const symbol = String(code).toLowerCase();
    if (symbol.includes('thunder')) return {label:'Trovoadas', icon:icons.thunder};
    if (symbol.includes('snow') || symbol.includes('sleet')) return {label:'Neve', icon:icons.snow};
    if (symbol.includes('rainshowers')) return {label:'Pancadas de chuva', icon:icons.shower};
    if (symbol.includes('heavyrain')) return {label:'Chuva forte', icon:icons.rain};
    if (symbol.includes('lightrain')) return {label:'Chuva fraca', icon:icons.rain};
    if (symbol.includes('rain')) return {label:'Chuva', icon:icons.rain};
    if (symbol.includes('fog')) return {label:'Nevoeiro', icon:icons.fog};
    if (symbol.includes('partlycloudy') || symbol.includes('fair')) return {label:'Sol entre nuvens', icon:icons.partly};
    if (symbol.includes('cloudy')) return {label:'Nublado', icon:icons.cloud};
    if (symbol.includes('clearsky')) return {label:'Céu limpo', icon:symbol.endsWith('_night') ? icons.night : icons.clear};
    return {label:'Previsão do tempo', icon:icons.partly};
  }
  function readCache() {
    try {
      const saved = JSON.parse(localStorage.getItem(CACHE_KEY) || 'null');
      return saved && Number.isFinite(saved.updated) && Number.isFinite(saved.expiresAt)
        && Number.isFinite(saved.model?.temperature) && Array.isArray(saved.model.hours)
        && Array.isArray(saved.model.days) ? saved : null;
    }
    catch { return null; }
  }
  function saveCache(value) {
    try { localStorage.setItem(CACHE_KEY, JSON.stringify(value)); } catch { /* Modo privativo sem armazenamento. */ }
  }
  function dailyPrecipitation(entries) {
    const hourly = new Map();
    entries.forEach(item => {
      const start = Date.parse(item.time);
      if (!Number.isFinite(start)) return;
      const periods = [[1, item.data?.next_1_hours], [6, item.data?.next_6_hours], [12, item.data?.next_12_hours]];
      // A menor janela disponível prevalece, sem somar períodos sobrepostos.
      periods.forEach(([length, period]) => {
        if (!period) return;
        const amount = period.details?.precipitation_amount;
        const code = String(period.summary?.symbol_code || '').toLowerCase();
        for (let hour = 0; hour < length; hour++) {
          const key = start + hour * 3600000;
          const previous = hourly.get(key);
          if (!previous || length < previous.length) hourly.set(key, {
            length, amount:Number.isFinite(amount) ? amount / length : null, code
          });
        }
      });
    });
    const days = new Map();
    hourly.forEach((period, timestamp) => {
      const key = dateParts(new Date(timestamp)).key;
      const day = days.get(key) || {rain:0, hasAmount:false, rainCode:false, thunder:false};
      if (period.amount != null) { day.rain += period.amount; day.hasAmount = true; }
      day.rainCode ||= /rain|sleet|snow/.test(period.code);
      day.thunder ||= period.code.includes('thunder');
      days.set(key, day);
    });
    return days;
  }
  function modelFromForecast(response) {
    const entries = response?.properties?.timeseries;
    if (!Array.isArray(entries) || !entries.length) throw new Error('Previsão vazia');
    const now = Date.now();
    const first = entries.findIndex(item => Date.parse(item.time) >= now - 30 * 60 * 1000);
    if (first < 0) throw new Error('Previsão antiga');
    const current = entries[first];
    const instant = current?.data?.instant?.details;
    if (!Number.isFinite(instant?.air_temperature)) throw new Error('Temperatura ausente');
    const summary = current.data.next_1_hours?.summary || current.data.next_6_hours?.summary || {};
    const rainSix = current.data.next_6_hours?.details?.precipitation_amount;
    const hours = [3, 6, 9].map(offset => {
      const target = Date.parse(current.time) + offset * 60 * 60 * 1000;
      const entry = entries.find(item => Date.parse(item.time) >= target);
      const temperature = entry?.data?.instant?.details?.air_temperature;
      if (!entry || !Number.isFinite(temperature)) return null;
      return {
        time:entry.time,
        temperature,
        icon:describeSymbol(entry.data.next_1_hours?.summary?.symbol_code || entry.data.next_6_hours?.summary?.symbol_code).icon,
        rain:entry.data.next_1_hours?.details?.precipitation_amount ?? null
      };
    }).filter(Boolean);
    const today = dateParts(new Date());
    const startDay = Date.parse(`${today.key}T00:00:00Z`);
    const precipitation = dailyPrecipitation(entries);
    const days = Array.from({length:6}, (_, index) => {
      const dateKey = new Date(startDay + (index + 1) * 86400000).toISOString().slice(0,10);
      const group = entries.filter(item => dateParts(new Date(item.time)).key === dateKey);
      const temperatures = group.map(item => item.data?.instant?.details?.air_temperature).filter(Number.isFinite);
      const midday = group.reduce((best,item) => Math.abs(dateParts(new Date(item.time)).hour - 12) < Math.abs(dateParts(new Date(best.time)).hour - 12) ? item : best,group[0]);
      const symbolCode = midday?.data?.next_1_hours?.summary?.symbol_code || midday?.data?.next_6_hours?.summary?.symbol_code || midday?.data?.next_12_hours?.summary?.symbol_code;
      const dailyRain = precipitation.get(dateKey);
      const thunder = dailyRain?.thunder;
      const rain = dailyRain?.rainCode || (dailyRain?.hasAmount && dailyRain.rain >= 0.2);
      const condition = thunder ? {label:'Trovoadas',icon:icons.thunder}
        : rain ? {label:'Chuva prevista',icon:icons.rain} : describeSymbol(symbolCode);
      const middayDate = midday ? new Date(midday.time) : new Date(`${dateKey}T15:00:00Z`);
      const label = new Intl.DateTimeFormat('pt-BR',{timeZone:WEATHER_LOCATION.timeZone,weekday:'short',day:'2-digit',month:'2-digit'}).format(middayDate);
      return {label:label.charAt(0).toUpperCase()+label.slice(1), min:temperatures.length ? Math.min(...temperatures) : null,
        max:temperatures.length ? Math.max(...temperatures) : null, condition,
        rain:dailyRain?.hasAmount ? dailyRain.rain : null};
    });
    return {
      forecastTime:current.time,
      temperature:instant.air_temperature,
      condition:describeSymbol(summary.symbol_code),
      rainSix:Number.isFinite(rainSix) ? rainSix : null,
      wind:Number.isFinite(instant.wind_speed) ? instant.wind_speed * 3.6 : null,
      humidity:Number.isFinite(instant.relative_humidity) ? instant.relative_humidity : null,
      hours, days
    };
  }
  function render(model, updated, stale = false) {
    setText('weather-location', WEATHER_LOCATION.label);
    setText('weather-temperature', `${displayNumber(Math.round(model.temperature))}°`);
    setText('weather-condition', model.condition.label);
    element('weather-symbol').firstElementChild.className = `fa-solid ${model.condition.icon}`;
    setText('weather-rain', model.rainSix == null ? '—' : `${displayNumber(model.rainSix, 1)} mm`);
    setText('weather-wind', model.wind == null ? '—' : `${displayNumber(Math.round(model.wind))} km/h`);
    setText('weather-humidity', model.humidity == null ? '—' : `${displayNumber(Math.round(model.humidity))}%`);
    setText('weather-updated', `${stale ? 'Dados salvos' : 'Atualizado'} às ${timeLabel(new Date(updated))}`);
    setText('weather-footnote', stale ? 'Sem conexão com a fonte. Confira o horário dos dados salvos.' : 'Estimativa meteorológica; consulte os avisos locais antes de operar.');
    const list = element('weather-hours');
    list.replaceChildren();
    model.hours.forEach(hour => {
      const item = document.createElement('div');
      item.className = 'weather-card-hour';
      const icon = document.createElement('i');
      icon.className = `fa-solid ${hour.icon}`;
      icon.setAttribute('aria-hidden', 'true');
      const detail = document.createElement('span');
      const time = document.createElement('strong');
      time.textContent = timeLabel(new Date(hour.time));
      const label = document.createElement('small');
      label.textContent = `${displayNumber(Math.round(hour.temperature))}°C`;
      detail.append(time, label);
      const rain = document.createElement('em');
      rain.textContent = hour.rain == null ? '—' : `${displayNumber(hour.rain, 1)} mm`;
      rain.title = 'Chuva prevista na hora seguinte';
      item.append(icon, detail, rain);
      list.append(item);
    });
    const button = element('weather-six-day-button');
    const daysList = element('weather-six-days');
    button.disabled = !model.days.some(day => day.min != null);
    daysList.replaceChildren();
    model.days.forEach(day => {
      const item = document.createElement('div');
      item.className = 'weather-card-day';
      const date = document.createElement('span'); date.textContent = day.label;
      const icon = document.createElement('i'); icon.className = `fa-solid ${day.condition.icon}`; icon.setAttribute('aria-hidden','true');
      const condition = document.createElement('small'); condition.textContent = day.min == null ? 'Indisponível' : day.condition.label;
      const temperatures = document.createElement('strong');
      temperatures.textContent = day.min == null ? '—' : `${displayNumber(Math.round(day.min))}° / ${displayNumber(Math.round(day.max))}°`;
      const values = document.createElement('div');
      values.className = 'weather-card-day-values';
      values.append(temperatures);
      if (day.rain != null && day.rain >= 0.2) {
        const precipitation = document.createElement('em');
        precipitation.className = 'weather-card-day-rain';
        precipitation.textContent = `${displayNumber(day.rain, 1)} mm`;
        precipitation.setAttribute('aria-label', `Chuva prevista: ${displayNumber(day.rain, 1)} milímetros`);
        const drop = document.createElement('i');
        drop.className = 'fa-solid fa-droplet';
        drop.setAttribute('aria-hidden', 'true');
        precipitation.prepend(drop);
        values.append(precipitation);
      }
      item.append(date,icon,condition,values);
      daysList.append(item);
    });
  }
  function renderUnavailable() {
    setText('weather-location', WEATHER_LOCATION.label);
    setText('weather-updated', 'Previsão indisponível');
    setText('weather-temperature', '—');
    setText('weather-condition', 'Não foi possível consultar o tempo');
    element('weather-symbol').firstElementChild.className = 'fa-solid fa-cloud';
    setText('weather-rain', '—');
    setText('weather-wind', '—');
    setText('weather-humidity', '—');
    setText('weather-footnote', 'Verifique sua conexão e tente novamente mais tarde.');
    element('weather-hours').replaceChildren();
    element('weather-six-days').replaceChildren();
    element('weather-six-days').hidden = true;
    element('weather-now-view').hidden = false;
    const button = element('weather-six-day-button');
    button.disabled = true;
    button.setAttribute('aria-expanded','false');
    element('weather-view-label').textContent = 'Próximos 6 dias';
  }
  async function refresh(force = false) {
    if (!element('weather-card-title') || pending || (!force && Date.now() < nextRetryAt) || document.hidden) return;
    const cached = readCache();
    if (cached && !force && Date.now() < cached.expiresAt) {
      render(cached.model, cached.updated);
      return;
    }
    if (cached && Date.now() - cached.updated < STALE_LIMIT_MS) render(cached.model, cached.updated, true);
    if (!navigator.onLine) {
      if (!cached || Date.now() - cached.updated >= STALE_LIMIT_MS) renderUnavailable();
      return;
    }
    pending = true;
    setRefreshing(true);
    try {
      const response = await fetch(API_URL, {signal:AbortSignal.timeout(9000)});
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const model = modelFromForecast(await response.json());
      const updated = Date.now();
      const serverExpiry = Date.parse(response.headers.get('Expires') || '');
      // Expires pode não ser exposto por CORS; o intervalo local então é conservador.
      const expiresAt = Number.isFinite(serverExpiry) && serverExpiry > updated
        ? serverExpiry + Math.random() * 15 * 60 * 1000
        : updated + FALLBACK_CACHE_MS + Math.random() * 15 * 60 * 1000;
      saveCache({model, updated, expiresAt});
      render(model, updated);
    } catch {
      nextRetryAt = Date.now() + RETRY_MS;
      if (!cached || Date.now() - cached.updated >= STALE_LIMIT_MS) renderUnavailable();
    } finally { pending = false; setRefreshing(false); }
  }
  function init() {
    if (!element('weather-card-title')) return;
    element('weather-refresh-button').addEventListener('click', () => {
      nextRetryAt = 0;
      refresh(true);
    });
    element('weather-six-day-button').addEventListener('click', () => {
      const panel = element('weather-six-days');
      const showingDays = panel.hidden;
      panel.hidden = !showingDays;
      element('weather-now-view').hidden = showingDays;
      element('weather-six-day-button').setAttribute('aria-expanded',String(showingDays));
      element('weather-view-label').textContent = showingDays ? 'Voltar para agora' : 'Próximos 6 dias';
    });
    refresh();
    window.addEventListener('online', () => { nextRetryAt = 0; refresh(); }, {passive:true});
    document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, {once:true});
  else init();
})();
