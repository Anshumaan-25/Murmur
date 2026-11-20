const canvas = document.getElementById('wave');
const pen = canvas.getContext('2d');
const button = document.getElementById('play');
const caption = document.getElementById('example');
const clock = document.getElementById('clock');
const sentence = caption.textContent;
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
let playing = false;
let progress = 1;
let frame;

function paint() {
  if (!pen) return;
  const w = canvas.clientWidth, h = canvas.clientHeight;
  const scale = Math.min(devicePixelRatio || 1, 2);
  const width = Math.round(w * scale), height = Math.round(h * scale);
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
  }
  pen.setTransform(scale, 0, 0, scale, 0, 0);
  pen.clearRect(0, 0, w, h);
  const t = playing && !reducedMotion.matches ? progress * 3 : 0;
  // Offset cross sections give the signal depth without a rendering library.
  for (let line = 0; line < 59; line++) {
    const z = line / 58;
    pen.beginPath();
    pen.strokeStyle = 'rgba(' + Math.round(100 + z * 90) + ',242,' + Math.round(155 + z * 45) + ',' + (0.23 + 0.54 * z) + ')';
    pen.lineWidth = 0.9;
    for (let step = 0; step <= 240; step++) {
      const x = step / 240;
      const swell = Math.exp(-Math.pow((x - .54) * 3.4, 2));
      const f = x * 13.6 - z * 2.9 + t;
      const height = (Math.sin(f) * .27 + Math.sin(f * 1.79 + z * 2.5) * .105) * swell;
      const y = h * (.49 + height + (z - .5) * (.13 + .17 * swell));
      if (step === 0) pen.moveTo(0, y); else pen.lineTo(x * w, y);
    }
    pen.stroke();
  }
}

function finish() {
  playing = false;
  progress = 1;
  cancelAnimationFrame(frame);
  caption.textContent = sentence;
  clock.textContent = '0:04 / 0:04';
  document.getElementById('play-label').textContent = 'Replay demo';
  document.getElementById('play-icon').textContent = '↻';
  paint();
}

button.hidden = false;
button.addEventListener('click', () => {
  if (playing) { finish(); return; }
  playing = true;
  const start = performance.now();
  document.getElementById('play-label').textContent = 'Finish demo';
  document.getElementById('play-icon').textContent = '■';
  let lastPaint = -Infinity;
  function tick(now) {
    progress = Math.min(1, (now - start) / 4000);
    if (progress >= 1) { finish(); return; }
    caption.textContent = progress < .85 ? 'Listening…' : 'Finishing dictation…';
    clock.textContent = '0:0' + Math.floor(progress * 4) + ' / 0:04';
    if (!reducedMotion.matches && now - lastPaint >= 40) {
      paint();
      lastPaint = now;
    }
    frame = requestAnimationFrame(tick);
  }
  tick(start);
});
new ResizeObserver(paint).observe(canvas);
document.addEventListener('visibilitychange', () => { if (document.hidden && playing) finish(); });

function openLinkedQuestion() {
  if (location.hash === '#first-open') document.getElementById('first-open').open = true;
}
document.querySelector('.setup-link').addEventListener('click', () => { document.getElementById('first-open').open = true; });
addEventListener('hashchange', openLinkedQuestion);
openLinkedQuestion();

const code = document.querySelector('meta[name="goatcounter-code"]').content.trim();
if (/^[a-z0-9][a-z0-9-]*$/.test(code) && location.protocol === 'https:') {
  document.getElementById('metrics-note').textContent = 'This website uses GoatCounter to estimate visits and count download-button clicks. These measurements cover the website only.';
  if (navigator.doNotTrack !== '1' && !navigator.globalPrivacyControl) {
    const analytics = document.createElement('script');
    analytics.async = true;
    analytics.dataset.goatcounter = 'https://' + code + '.goatcounter.com/count';
    analytics.src = 'https://gc.zgo.at/count.js';
    document.head.appendChild(analytics);
  }
}
