// PuTTY for iOS website: install-method switch and reveal-on-scroll.

const METHODS = {
  sideloadly: [
    ['Download the IPA', 'PuTTY-iOS-unsigned.ipa from the latest GitHub release.'],
    ['Sign it with Sideloadly', 'Connect your iPhone, drop the IPA onto Sideloadly and sign in with your Apple ID.'],
    ['Trust the profile', 'Settings › General › VPN & Device Management, then Trust.'],
    ['Open PuTTY', 'Free Apple IDs re-sign every 7 days.'],
  ],
  altstore: [
    ['Download the IPA', 'Save PuTTY-iOS-unsigned.ipa on your iPhone.'],
    ['Open it in AltStore', 'Share the IPA to AltStore, with AltServer running on your computer.'],
    ['Trust the profile', 'Settings › General › VPN & Device Management, then Trust.'],
    ['Open PuTTY', 'AltStore refreshes the signature over Wi-Fi.'],
  ],
  trollstore: [
    ['Download the IPA', 'Save PuTTY-iOS-unsigned.ipa on your iPhone.'],
    ['Share it to TrollStore', 'Tap Install when TrollStore asks.'],
    ['Open PuTTY', 'No Apple ID, nothing to trust, nothing to refresh.'],
  ],
};

const list = document.getElementById('step-list');
const tabs = [...document.querySelectorAll('.segmented [role="tab"]')];

function select(tab) {
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

// Show the poster instead of the loop when motion is reduced.
const video = document.querySelector('.phone-main video');
if (video && matchMedia('(prefers-reduced-motion: reduce)').matches) {
  video.removeAttribute('autoplay');
  video.pause();
}

// Reveal once on entry; never leaves content hidden.
(() => {
  const items = document.querySelectorAll('.reveal');
  const show = (el) => el.classList.add('is-in');
  if (!('IntersectionObserver' in window)) { items.forEach(show); return; }
  const io = new IntersectionObserver((entries) => {
    for (const entry of entries) if (entry.isIntersecting) { show(entry.target); io.unobserve(entry.target); }
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0.05 });
  items.forEach((el) => io.observe(el));
  setTimeout(() => items.forEach((el) => {
    const r = el.getBoundingClientRect();
    if (r.top < innerHeight && r.bottom > 0) show(el);
  }), 2500);
})();
