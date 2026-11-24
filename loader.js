/* Arrowflow Web loader: actual Godot byte progress, accessible recovery, and original arrow motifs. */
(() => {
  const FADE_MS = 320;
  const motion = window.matchMedia?.('(prefers-reduced-motion: reduce)');
  const ids = {root:'arrowflow-loader', message:'arrowflow-loader-message', detail:'arrowflow-loader-detail', progress:'arrowflow-loader-progress', retry:'arrowflow-loader-retry'};
  let phase = 'idle', percent = null, startedAt = 0, lastProgressAt = 0;
  let watchTimer = null, readyTimer = null, readyPromise = null, resolveReady = null, retryBound = false;
  const copy = key => typeof window.t === 'function' ? window.t(key) : key;
  const now = () => performance.now();

  function nodes() {
    const ui = Object.fromEntries(Object.entries(ids).map(([key,id]) => [key,document.getElementById(id)]));
    return Object.values(ui).every(Boolean) ? ui : null;
  }

  function currentNotice() {
    if (!['downloading','preparing'].includes(phase) || now() - startedAt < 30000) return '';
    return now() - lastProgressAt >= 30000 ? 'loader.stalled_notice' : 'loader.loading_notice';
  }

  function render() {
    const ui = nodes();
    if (!ui) return;
    const failure = phase === 'failure';
    const busy = ['downloading','preparing','finishing','fading'].includes(phase);
    const notice = currentNotice();
    ui.root.hidden = phase === 'idle' || phase === 'ready';
    ui.root.dataset.state = phase;
    ui.root.setAttribute('aria-busy',String(busy));
    ui.message.textContent = copy(failure ? 'loader.error' : 'loader.overlay_loading');
    ui.detail.hidden = !failure && !notice;
    ui.detail.textContent = failure ? copy('loader.error_detail') : notice ? copy(notice) : '';
    ui.retry.hidden = !failure && !notice;
    ui.retry.textContent = copy('loader.retry');
    if (percent !== null && !failure) {
      ui.progress.max = 100;
      ui.progress.value = percent;
      ui.progress.setAttribute('aria-valuetext',copy(phase === 'preparing' || phase === 'finishing' || phase === 'fading' ? 'loader.preparing_detail' : 'loader.downloading'));
    } else {
      ui.progress.removeAttribute('value');
      ui.progress.setAttribute('aria-valuetext',copy(failure ? 'loader.error_detail' : 'loader.progress_unknown'));
    }

    const status = document.getElementById('status');
    const statusProgress = document.getElementById('status-progress');
    const statusLabel = document.getElementById('status-label');
    const statusNotice = document.getElementById('status-notice');
    const statusRetry = document.getElementById('retry');
    status?.classList?.toggle('error',failure);
    if (statusLabel) statusLabel.textContent = copy(failure ? 'loader.error' : ['preparing','finishing','fading'].includes(phase) ? 'loader.preparing' : percent === null ? 'loader.progress_unknown' : 'loader.downloading');
    if (statusProgress) {
      if (percent !== null && !failure) { statusProgress.max = 100; statusProgress.value = percent; }
      else { statusProgress.removeAttribute('value'); statusProgress.removeAttribute('max'); }
    }
    if (statusNotice) statusNotice.textContent = failure ? copy('loader.error_detail') : '';
    if (statusRetry && failure) { statusRetry.textContent = copy('loader.retry'); statusRetry.style.display = 'inline-block'; }
  }

  function bindRetry() {
    const retry = nodes()?.retry;
    if (!retry || retryBound) return;
    retryBound = true;
    retry.addEventListener('click',() => window.location.reload());
  }

  function stopWatch() {
    if (watchTimer !== null) clearTimeout(watchTimer);
    watchTimer = null;
  }

  function watch() {
    if (!['downloading','preparing'].includes(phase)) return;
    render();
    watchTimer = setTimeout(watch,1000);
  }

  function cancelReady() {
    if (readyTimer !== null) clearTimeout(readyTimer);
    readyTimer = null;
    if (resolveReady) resolveReady(false);
    resolveReady = null;
    readyPromise = null;
    document.getElementById('status')?.removeAttribute('data-arrowflow-fade');
  }

  const onStartupError = () => failure();

  function begin() {
    cancelReady();
    stopWatch();
    bindRetry();
    window.removeEventListener('error',onStartupError);
    window.removeEventListener('unhandledrejection',onStartupError);
    document.getElementById('status')?.style.setProperty('visibility','visible');
    document.getElementById('status')?.classList?.remove('error');
    phase = 'downloading'; percent = null; startedAt = now(); lastProgressAt = startedAt;
    window.addEventListener('error',onStartupError);
    window.addEventListener('unhandledrejection',onStartupError);
    render(); watch();
  }

  function scriptReady() {
    if (!['downloading','preparing'].includes(phase)) return;
    phase = 'preparing'; lastProgressAt = now(); render();
  }

  function progress(current,total) {
    if (!['downloading','preparing'].includes(phase)) return;
    if (Number.isFinite(current) && Number.isFinite(total) && current >= 0 && total > 0) {
      percent = Math.max(0,Math.min(100,Math.floor(current * 100 / total)));
      phase = percent === 100 ? 'preparing' : 'downloading';
      lastProgressAt = now();
    } else {
      percent = null;
      if (phase !== 'preparing') phase = 'downloading';
    }
    render();
  }

  function preparing() {
    if (!['downloading','preparing'].includes(phase)) return;
    phase = 'preparing'; lastProgressAt = now(); render();
  }

  function failure() {
    if (phase === 'ready') return;
    stopWatch(); cancelReady();
    window.removeEventListener('error',onStartupError);
    window.removeEventListener('unhandledrejection',onStartupError);
    phase = 'failure'; percent = null; render();
  }

  function ready() {
    if (phase === 'ready') return Promise.resolve(true);
    if (phase === 'failure') return Promise.resolve(false);
    if (readyPromise) return readyPromise;
    stopWatch();
    window.removeEventListener('error',onStartupError);
    window.removeEventListener('unhandledrejection',onStartupError);
    percent = 100; phase = 'finishing'; render();
    readyPromise = new Promise(resolve => {
      resolveReady = resolve;
      const finish = () => {
        readyTimer = null; phase = 'ready'; render();
        document.getElementById('status')?.removeAttribute('data-arrowflow-fade');
        const done = resolveReady; resolveReady = null; done?.(true);
      };
      const startFade = () => {
        readyTimer = null;
        const status = document.getElementById('status');
        if (document.hidden || motion?.matches || !status) { finish(); return; }
        phase = 'fading'; render();
        status.style.setProperty('--arrowflow-fade-duration',FADE_MS + 'ms');
        status.setAttribute('data-arrowflow-fade','true');
        readyTimer = setTimeout(finish,FADE_MS + 60);
      };
      readyTimer = setTimeout(startFade,document.hidden ? 0 : motion?.matches ? 80 : 360);
    });
    return readyPromise;
  }

  window.ArrowflowLoader = {begin,scriptReady,progress,preparing,failure,ready,refresh:render};
  document.addEventListener('DOMContentLoaded',() => { bindRetry(); render(); },{once:true});
  document.addEventListener('visibilitychange',() => { if (document.hidden && ['finishing','fading'].includes(phase)) { if (readyTimer !== null) clearTimeout(readyTimer); phase = 'ready'; render(); const done = resolveReady; resolveReady = null; done?.(true); } });
})();
