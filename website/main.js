// PuTTY for iOS: install-method switch, typed headlines, reveals on scroll.

const METHODS = {
  sideloadly: [
    ['Download the IPA', 'PuTTY-iOS-unsigned.ipa from the latest GitHub release'],
    ['Sign it with Sideloadly', 'Connect your iPhone, drop the IPA onto Sideloadly and sign in with your Apple ID'],
    ['Trust the profile', 'Settings › General › VPN & Device Management, then Trust'],
    ['Open PuTTY', 'Free Apple IDs re-sign every 7 days'],
  ],
  altstore: [
    ['Download the IPA', 'Save PuTTY-iOS-unsigned.ipa on your iPhone'],
    ['Open it in AltStore', 'Share the IPA to AltStore, with AltServer running on your computer'],
    ['Trust the profile', 'Settings › General › VPN & Device Management, then Trust'],
    ['Open PuTTY', 'AltStore refreshes the signature over Wi-Fi'],
  ],
  trollstore: [
    ['Download the IPA', 'Save PuTTY-iOS-unsigned.ipa on your iPhone'],
    ['Share it to TrollStore', 'Tap Install when TrollStore asks'],
    ['Open PuTTY', 'No Apple ID, nothing to trust, nothing to refresh'],
  ],
};

const list = document.getElementById('steps');
const tabs = [...document.querySelectorAll('.segmented [role="tab"]')];

const indicator = document.querySelector('.seg-indicator');

function select(tab) {
  indicator.style.setProperty('--i', tabs.indexOf(tab));
  tabs.forEach((t) => {
    const on = t === tab;
    t.setAttribute('aria-selected', String(on));
    t.tabIndex = on ? 0 : -1;
  });
  list.replaceChildren(...METHODS[tab.dataset.method].map(([title, text]) => {
    const li = document.createElement('li');
    const strong = document.createElement('strong');
    const span = document.createElement('span');
    strong.textContent = title;
    span.textContent = text;
    li.append(strong, span);
    return li;
  }));
}

tabs.forEach((tab, i) => {
  tab.addEventListener('click', () => select(tab));
  tab.addEventListener('keydown', (e) => {
    const step = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
    if (!step) return;
    e.preventDefault();
    const next = tabs[(i + step + tabs.length) % tabs.length];
    next.focus();
    select(next);
  });
});

const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

// The headline is typed behind PuTTY's cursor, like a line in the terminal.
function type(el, delay = 0) {
  const text = el.dataset.text || el.textContent;
  if (reduced) { el.textContent = text; return; }
  // Hold the finished line's height so nothing below moves while it is typed.
  el.textContent = text;
  el.parentElement.style.minHeight = `${el.parentElement.offsetHeight}px`;
  el.textContent = '';
  let i = 0;
  const step = () => {
    i += 1;
    el.textContent = text.slice(0, i);
    if (i < text.length) setTimeout(step, 38 + (text[i - 1] === ' ' ? 40 : 0));
  };
  setTimeout(step, delay);
}
const heroLine = document.querySelector('[data-type="hero"]');
if (heroLine) type(heroLine, 320);

// Sections rise once as they arrive; the closing line is typed when it comes into view.
const revealables = [...document.querySelectorAll('[data-reveal]')];
if (!reduced && 'IntersectionObserver' in window) {
  const closer = document.querySelector('[data-type="closer"]');
  const closerHeading = closer ? closer.parentElement : null;
  if (closer) { closer.dataset.text = closer.textContent; closer.style.visibility = 'hidden'; }
  const io = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      const el = entry.target;
      if (el === closerHeading) {
        closer.style.visibility = '';
        type(closer, 120);
      } else {
        el.classList.add('is-in');
      }
      io.unobserve(el);
    }
  }, { rootMargin: '0px 0px -12% 0px', threshold: 0.1 });
  revealables.forEach((el) => io.observe(el));
  if (closerHeading) io.observe(closerHeading);
} else {
  revealables.forEach((el) => el.classList.add('is-in'));
}

// The bar gets its own background once the page moves under it.
const nav = document.querySelector('.nav');
const onScroll = () => nav.classList.toggle('is-scrolled', window.scrollY > 24);
window.addEventListener('scroll', onScroll, { passive: true });
onScroll();

// Show the poster instead of the loop when motion is reduced.
const video = document.querySelector('.hero-phone video');
if (video && reduced) {
  video.removeAttribute('autoplay');
  video.pause();
}
