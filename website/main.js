// PuTTY for iOS website: reveals, the install-method dialog, screenshot picker, feature switches, install slider, cards.

const METHODS = {
  sideloadly: {
    hint: 'Signs the IPA with your Apple ID from a Mac or PC. Free accounts re-sign every 7 days.',
    steps: ['Connect your iPhone to a Mac or PC with Sideloadly open.', 'Drop PuTTY-iOS-unsigned.ipa onto Sideloadly.', 'Sign in with your Apple ID and press Start.'],
  },
  altstore: {
    hint: 'Installs from the phone once AltServer runs on your computer. Refreshes itself over Wi-Fi.',
    steps: ['Install AltStore on your iPhone through AltServer.', 'Open the IPA on your iPhone and share it to AltStore.', 'AltStore signs it with your Apple ID and installs it.'],
  },
  trollstore: {
    hint: 'Installs the IPA permanently on iOS versions TrollStore supports. No Apple ID, no refresh.',
    steps: ['Open the IPA on your iPhone.', 'Share it to TrollStore.', 'Tap Install. Nothing to trust, nothing to refresh.'],
  },
};

const STAGES = [
  { name: 'Download', clause: 'Download the unsigned IPA.', detail: 'One file from the GitHub release, built straight from the source you can read.' },
  { name: 'Sign', clause: 'Sign it with your tool of choice.', detail: 'iOS only runs signed apps, so a sideloading tool signs it for your phone.' },
  { name: 'Trust', clause: 'Trust your own certificate.', detail: 'Once, in Settings, so iOS lets the app open.' },
  { name: 'Connect', clause: 'Type a host and press Open.', detail: 'Accept the host key, answer “login as:”, and you are in.' },
];

let method = 'sideloadly';

function renderSteps() {
  const list = document.getElementById('sign-steps');
  list.replaceChildren(...METHODS[method].steps.map((text) => Object.assign(document.createElement('li'), { textContent: text })));
  document.getElementById('method-hint').textContent = METHODS[method].hint;
}

// Install method: the "connection type" radios in the hero dialog.
document.querySelectorAll('input[name="method"]').forEach((radio) => {
  radio.addEventListener('change', () => { method = radio.value; renderSteps(); });
});
renderSteps();

// Screenshot picker.
const SHOTS = {
  clip: { fact: 'Fifteen seconds, unedited apart from two cuts: a host, the security alert, and a shell.' },
  config: { alt: 'The PuTTY Configuration window on iPhone, with saved sessions Home Server, Raspberry Pi and Router', fact: 'The category tree, saved sessions and the Load, Save, Delete and Open buttons, where your hands expect them.' },
  'security-alert': { alt: 'The PuTTY Security Alert showing an ssh-ed25519 fingerprint with Yes, No and Cancel', fact: 'A new server shows its SHA256 fingerprint and waits for Yes, No or Cancel before anything is trusted.' },
  terminal: { alt: 'A terminal session showing a calendar and the sixteen PuTTY colours with a green block cursor', fact: 'A full xterm with PuTTY’s own sixteen colours, the green block cursor and a key bar for Esc, Ctrl and arrows.' },
};
const showcase = document.querySelector('.showcase');
const shot = document.getElementById('shot');
const tabs = [...document.querySelectorAll('.shot-picker [role="tab"]')];
function pick(tab) {
  tabs.forEach((t) => { const on = t === tab; t.setAttribute('aria-selected', String(on)); t.tabIndex = on ? 0 : -1; });
  const key = tab.dataset.shot;
  showcase.dataset.colour = tab.dataset.colour;
  document.getElementById('shot-fact').textContent = SHOTS[key].fact;
  const video = document.getElementById('clip');
  if (key === 'clip') {
    shot.hidden = true; video.hidden = false;
    if (!matchMedia('(prefers-reduced-motion: reduce)').matches) video.play().catch(() => {});
    return;
  }
  video.pause(); video.hidden = true; shot.hidden = false;
  shot.style.opacity = '0';
  setTimeout(() => { shot.src = `assets/${key}.jpg`; shot.alt = SHOTS[key].alt; shot.style.opacity = '1'; }, 150);
}
tabs.forEach((tab, i) => {
  tab.tabIndex = i === 0 ? 0 : -1;
  tab.addEventListener('click', () => pick(tab));
  tab.addEventListener('keydown', (e) => {
    const step = e.key === 'ArrowDown' || e.key === 'ArrowRight' ? 1 : e.key === 'ArrowUp' || e.key === 'ArrowLeft' ? -1 : 0;
    if (!step) return;
    e.preventDefault();
    const next = tabs[(i + step + tabs.length) % tabs.length];
    next.focus(); pick(next);
  });
});
Object.keys(SHOTS).filter((k) => k !== 'clip').forEach((k) => { const img = new Image(); img.src = `assets/${k}.jpg`; });
// Respect reduced motion: show the poster frame instead of the loop.
if (matchMedia('(prefers-reduced-motion: reduce)').matches) { const v = document.getElementById('clip'); v.removeAttribute('autoplay'); v.pause(); }

// Feature switches.
document.querySelectorAll('.feature').forEach((band) => {
  const box = band.querySelector('input[type="checkbox"]');
  const sync = () => band.classList.toggle('is-on', box.checked);
  box.addEventListener('change', sync);
  sync();
});

// Install slider.
const range = document.getElementById('stage');
const frags = [...document.querySelectorAll('.frag')];
const names = [...document.querySelectorAll('.stage-names span')];
const clause = document.getElementById('clause');
const detail = document.getElementById('clause-detail');
function setStage(i) {
  frags.forEach((f) => f.classList.toggle('is-active', Number(f.dataset.stage) === i));
  names.forEach((n, j) => n.classList.toggle('is-current', j === i));
  clause.textContent = STAGES[i].clause;
  detail.textContent = STAGES[i].detail;
  range.setAttribute('aria-valuetext', STAGES[i].name);
  range.parentElement.style.setProperty('--pct', `${(i / 3) * 100}%`);
}
range.addEventListener('input', () => setStage(Number(range.value)));
setStage(0);

// Index cards: one open at a time.
const cards = [...document.querySelectorAll('.card')];
cards.forEach((card) => {
  card.querySelector('.card-head').addEventListener('click', () => {
    cards.forEach((c) => {
      const open = c === card;
      c.classList.toggle('is-open', open);
      c.querySelector('.card-head').setAttribute('aria-expanded', String(open));
      c.querySelector('.card-body').hidden = !open;
    });
  });
});

// Reveal once on entry; never leaves content hidden.
(() => {
  const targets = document.querySelectorAll('[data-reveal], .stage, [data-shutter], .features, .faq, .blocks, .footer');
  const show = (el) => el.classList.add('is-in');
  if (!('IntersectionObserver' in window)) { targets.forEach(show); return; }
  const io = new IntersectionObserver((entries) => {
    for (const entry of entries) if (entry.isIntersecting) { show(entry.target); io.unobserve(entry.target); }
  }, { rootMargin: '0px 0px -10% 0px', threshold: 0.05 });
  targets.forEach((el) => io.observe(el));
  // Features and cards also reveal one by one.
  const items = document.querySelectorAll('.feature, .card');
  const io2 = new IntersectionObserver((entries) => {
    for (const entry of entries) if (entry.isIntersecting) { show(entry.target); io2.unobserve(entry.target); }
  }, { rootMargin: '0px 0px -8% 0px' });
  items.forEach((el) => io2.observe(el));
  window.addEventListener('load', () => setTimeout(() => targets.forEach((el) => {
    const r = el.getBoundingClientRect();
    if (r.top < innerHeight && r.bottom > 0) show(el);
  }), 2500));
})();
