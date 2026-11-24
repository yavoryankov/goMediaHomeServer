let SERVER = 'http://127.0.0.1:7071';
let state = { active: false, sessionId: '', path: '', tabId: null };

async function readJson(response) {
  const text = await response.text();
  try { return text ? JSON.parse(text) : {}; }
  catch (_) { throw new Error(`Local bridge returned an invalid response: ${text.slice(0, 160)}`); }
}

async function saveState() {
  await chrome.storage.local.set({ recorderState: state });
}

async function loadState() {
  const saved = await chrome.storage.local.get(['recorderState', 'recorderService']);
  if (saved.recorderService) SERVER = saved.recorderService;
  if (saved.recorderState) state = saved.recorderState;
}

async function ensureOffscreen() {
  if (chrome.offscreen.hasDocument && await chrome.offscreen.hasDocument()) return;
  await chrome.offscreen.createDocument({
    url: 'offscreen.html',
    reasons: ['USER_MEDIA'],
    justification: 'Запис на аудио и видео от текущия Chrome таб.'
  });
}

async function startRecording(message) {
  await loadState();
  if (state.active) throw new Error('Вече има активен запис.');
  const tabs = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  const tab = tabs[0];
  if (!tab?.id) throw new Error('Няма активен таб.');
  if (tab.url?.startsWith('chrome://') || tab.url?.startsWith('chrome-extension://')) {
    throw new Error('Chrome не позволява запис на системни страници. Отвори видео страница.');
  }
  const streamId = await chrome.tabCapture.getMediaStreamId({ targetTabId: tab.id });
  const startResponse = await fetch(`${SERVER}/api/recordings/start`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      directory: message.directory,
      filename: message.filename,
      media_server_api: message.mediaServerApi
    })
  });
  const started = await readJson(startResponse);
  if (!startResponse.ok) throw new Error(started.error || 'Локалният сървър отказа записа.');
  await ensureOffscreen();
  state = { active: true, sessionId: started.session_id, path: started.path, tabId: tab.id };
  await saveState();
  const ready = await chrome.runtime.sendMessage({
    target: 'offscreen', type: 'START_CAPTURE', streamId, sessionId: started.session_id
  });
  if (!ready?.ok) {
    await fetch(`${SERVER}/api/recordings/cancel?session_id=${encodeURIComponent(started.session_id)}`, { method: 'POST' });
    state = { active: false, sessionId: '', path: '', tabId: null };
    await saveState();
    throw new Error(ready?.error || 'Chrome не даде достъп до таба.');
  }
  return { ok: true, path: started.path, absolute_path: started.absolute_path };
}

async function stopRecording() {
  await loadState();
  if (!state.active) return { ok: false, error: 'Няма активен запис.' };
  const response = await chrome.runtime.sendMessage({ target: 'offscreen', type: 'STOP_CAPTURE' });
  if (!response?.ok) throw new Error(response?.error || 'Записът не може да бъде спрян.');
  state = { active: false, sessionId: '', path: '', tabId: null };
  await saveState();
  if (chrome.offscreen.hasDocument && await chrome.offscreen.hasDocument()) await chrome.offscreen.closeDocument();
  return response;
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  (async () => {
    try {
      if (message.type === 'START_RECORDING') sendResponse(await startRecording(message));
      else if (message.type === 'STOP_RECORDING') sendResponse(await stopRecording());
      else if (message.type === 'STATUS') { await loadState(); sendResponse(state); }
      else if (message.type === 'CHUNK' && message.sessionId === state.sessionId) {
        const response = await fetch(`${SERVER}/api/recordings/chunk?session_id=${encodeURIComponent(state.sessionId)}`, {
          method: 'POST', headers: { 'Content-Type': 'video/webm' }, body: message.data
        });
        const result = await readJson(response);
        if (!response.ok) throw new Error(result.error || 'Грешка при записване на сегмента.');
        sendResponse({ ok: true });
      } else if (message.type === 'FINISH' && message.sessionId === state.sessionId) {
        const response = await fetch(`${SERVER}/api/recordings/finish?session_id=${encodeURIComponent(state.sessionId)}`, { method: 'POST' });
        const result = await readJson(response);
        if (!response.ok) throw new Error(result.error || 'Грешка при приключване на файла.');
        sendResponse({ ok: true, path: result.path, absolute_path: result.absolute_path });
      }
    } catch (error) { sendResponse({ ok: false, error: error.message }); }
  })();
  return true;
});

chrome.tabs.onRemoved.addListener(async tabId => {
  if (state.active && tabId === state.tabId) {
    try { await stopRecording(); } catch (_) {}
  }
});

loadState();
