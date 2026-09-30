(() => {
  const hero = document.querySelector('.dashboard-hero');
  if (!hero) return;

  const images = [...hero.querySelectorAll('[data-hero-image]')];
  const buttons = [...hero.querySelectorAll('[data-hero-go]')];
  const headline = hero.querySelector('#hero-headline');
  const eyebrow = hero.querySelector('.hero-eyebrow');
  const copy = hero.querySelector('.hero-copy');
  if (images.length !== 5 || buttons.length !== images.length || !headline || !eyebrow || !copy) return;

  const eyebrowMessages = [
    'GESTÃO QUE MOVE O CAMPO',
    'PROTEÇÃO EM CADA PASSADA',
    'A FORÇA DA COLHEITA',
    'RECEBIMENTO COM CUIDADO',
    'SEMEANDO O FUTURO'
  ];

  const messages = [
    'Controle hoje<br>um amanhã<br>mais produtivo.',
    'Cuidado em cada<br>aplicação protege<br>a próxima safra.',
    'Cada colheita<br>carrega dedicação<br>e muito trabalho.',
    'Juntos, recebemos<br>o resultado de<br>uma grande safra.',
    'Toda grande colheita<br>começa com<br>um bom plantio.'
  ];

  let active = 0;
  let changing = false;

  function showSlide(next) {
    if (changing || next === active || next < 0 || next >= images.length) return;
    changing = true;
    copy.classList.add('is-transitioning');

    window.setTimeout(() => {
      images[active].classList.remove('is-active');
      images[active].setAttribute('aria-hidden', 'true');
      active = next;
      images[active].classList.add('is-active');
      images[active].removeAttribute('aria-hidden');
      eyebrow.textContent = eyebrowMessages[active];
      headline.innerHTML = messages[active];
      buttons.forEach((button, index) => {
        const selected = index === active;
        button.classList.toggle('is-active', selected);
        button.setAttribute('aria-pressed', String(selected));
      });
      window.requestAnimationFrame(() => {
        copy.classList.remove('is-transitioning');
        changing = false;
      });
    }, 220);
  }

  buttons.forEach((button, index) => button.addEventListener('click', () => showSlide(index)));

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (!reducedMotion) {
    window.setInterval(() => {
      if (!document.hidden) showSlide((active + 1) % images.length);
    }, 9000);
  }
})();
