const defaults = {
  mediaServerApi: 'http://YOUR-IMAC-IP:8095/api/v1',
  destinationPath: 'Yavor/Courses/Arestovich',
  downloaderService: 'http://127.0.0.1:7071',
  recorderService: 'http://127.0.0.1:7071'
};
let settings = {...defaults};
const detectButton = document.querySelector('#detect');
const downloadButton = document.querySelector('#download');
const playerBox = document.querySelector('#player');
const detectedLabel = document.querySelector('#detectedLabel');
const statusBox = document.querySelector('#status');
const recordButton = document.querySelector('#record');
const serverApiInput = document.querySelector('#serverApi');
const testServerButton = document.querySelector('#testServer');
const serverStatus = document.querySelector('#serverStatus');
const folderTree = document.querySelector('#folderTree');
const folderSelected = document.querySelector('#folderSelected');
let found = null;
const expandedFolders = new Set();
const folderChildren = new Map();

function status(text, kind = '') {
  statusBox.textContent = text || '';
  statusBox.className = `status ${kind}`;
}

function normaliseUrl(value) {
  try { return new URL(value).toString(); } catch (_) { return ''; }
}

function setDetectedLabel(kind) {
  detectedLabel.textContent = `Detected ${kind === 'youtube' ? 'YouTube' : 'Vimeo'} URL`;
}

function explainFetchError(error, service) {
  if (error instanceof TypeError && /fetch/i.test(error.message || '')) {
    return `Cannot reach the local downloader service at ${service}. Start bridge.py and try again.`;
  }
  return error.message || 'Download failed.';
}

function validateServerAddress(value) {
  if (!value) return 'Enter the media server API address.';
  let parsed;
  try { parsed = new URL(value); } catch (_) { return 'Invalid URL syntax. Example: http://192.168.50.120:8095/api/v1'; }
  if (!['http:', 'https:'].includes(parsed.protocol)) return 'Use an http:// or https:// address.';
  if (!parsed.hostname) return 'The server hostname or IP address is missing.';
  if (/YOUR-|YOUR_/i.test(parsed.hostname)) return 'Replace the placeholder hostname with the server IP or DNS name.';
  if (!parsed.pathname.replace(/\/$/, '').endsWith('/api/v1')) return 'The API address must end with /api/v1.';
  return '';
}

function setServerStatus(message, kind = '') {
  serverStatus.textContent = message;
  serverStatus.className = `server-status ${kind}`;
}

function selectDestination(path) {
  settings.destinationPath = path;
  document.querySelector('#output').value = path;
  folderSelected.textContent = path || 'Media library root';
  chrome.storage.local.set({destinationPath: path});
  folderTree.querySelectorAll('.folder-row.selected').forEach(row => row.classList.remove('selected'));
  const selected = folderTree.querySelector(`[data-folder-path="${CSS.escape(path)}"]`);
  selected?.classList.add('selected');
}

async function getFolders(path) {
  const bridge = settings.downloaderService.replace(/\/$/, '');
  const response = await fetch(`${bridge}/api/folders?api=${encodeURIComponent(serverApiInput.value.trim())}&path=${encodeURIComponent(path)}`);
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || `Folder request failed (HTTP ${response.status}).`);
  return Array.isArray(payload.items) ? payload.items.filter(item => item.is_dir) : [];
}

function folderNode(item, depth = 0) {
  const node = document.createElement('div');
  node.className = 'folder-node';
  const row = document.createElement('div');
  row.className = 'folder-row';
  row.dataset.folderPath = item.path;
  const toggle = document.createElement('button');
  toggle.className = 'folder-toggle';
  toggle.textContent = expandedFolders.has(item.path) ? '▾' : '▸';
  toggle.title = `Expand ${item.name}`;
  const name = document.createElement('span');
  name.className = 'folder-name';
  name.textContent = `📁 ${item.name}`;
  row.append(toggle, name);
  row.addEventListener('click', event => {
    event.stopPropagation();
    selectDestination(item.path);
  });
  toggle.addEventListener('click', async event => {
    event.stopPropagation();
    await toggleFolder(item, node, depth);
  });
  node.append(row);
  if (expandedFolders.has(item.path)) {
    const children = document.createElement('div');
    children.className = 'folder-children';
    node.append(children);
    renderFolderChildren(item.path, children, depth + 1);
  }
  return node;
}

async function renderFolderChildren(path, container, depth) {
  container.replaceChildren();
  if (!folderChildren.has(path)) {
    const loading = document.createElement('div');
    loading.className = 'folder-state';
    loading.textContent = 'Loading…';
    container.append(loading);
    try { folderChildren.set(path, await getFolders(path)); }
    catch (error) { loading.textContent = error.message; return; }
  }
  const children = folderChildren.get(path);
  if (!children.length) {
    const empty = document.createElement('div');
    empty.className = 'folder-state';
    empty.textContent = 'No subfolders';
    container.append(empty);
    return;
  }
  children.forEach(item => container.append(folderNode(item, depth)));
}

async function toggleFolder(item, node, depth) {
  if (expandedFolders.has(item.path)) expandedFolders.delete(item.path);
  else expandedFolders.add(item.path);
  const rebuilt = folderNode(item, depth);
  node.replaceWith(rebuilt);
}

async function loadFolderTree() {
  folderTree.replaceChildren();
  const root = document.createElement('div');
  root.className = 'folder-node';
  const rootRow = document.createElement('div');
  rootRow.className = 'folder-row';
  rootRow.dataset.folderPath = '';
  rootRow.innerHTML = '<span class="folder-toggle empty">▸</span><span class="folder-name">📚 Media library root</span>';
  rootRow.addEventListener('click', () => selectDestination(''));
  root.append(rootRow);
  const children = document.createElement('div');
  children.className = 'folder-children';
  root.append(children);
  folderTree.append(root);
  try { await renderFolderChildren('', children, 0); }
  catch (error) { children.textContent = error.message; }
  selectDestination(settings.destinationPath);
}

testServerButton.addEventListener('click', async () => {
  const api = serverApiInput.value.trim();
  const syntaxError = validateServerAddress(api);
  if (syntaxError) { setServerStatus(`✕ ${syntaxError}`, 'error'); status(syntaxError, 'error'); return; }
  testServerButton.disabled = true;
  setServerStatus('Checking server…');
  try {
    const bridge = settings.downloaderService.replace(/\/$/, '');
    const response = await fetch(`${bridge}/api/folders?api=${encodeURIComponent(api)}&path=`);
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(payload.error || `Server check failed (HTTP ${response.status}).`);
    settings.mediaServerApi = api;
    chrome.storage.local.set({mediaServerApi: api});
    folderChildren.clear();
    await loadFolderTree();
    setServerStatus('✓ Server is reachable.', 'ok');
    status('Media server is reachable.', 'ok');
  } catch (error) {
    setServerStatus(`✕ ${error.message}`, 'error');
    status(error.message, 'error');
  } finally {
    testServerButton.disabled = false;
  }
});

async function activeTab() {
  const tabs = await chrome.tabs.query({active: true, lastFocusedWindow: true});
  if (!tabs[0]?.id || !tabs[0].url) throw new Error('No active web tab.');
  return tabs[0];
}

async function findPlayer() {
  const tab = await activeTab();
  if (/^(https?:\/\/)?(www\.)?(youtube\.com|youtu\.be)\//i.test(tab.url)) {
    found = {tab, player: normaliseUrl(tab.url), page: tab.url, kind: 'youtube'};
    setDetectedLabel(found.kind);
    playerBox.textContent = found.player;
    downloadButton.disabled = false;
    status('YouTube video detected.', 'ok');
    return found;
  }
  const result = await chrome.scripting.executeScript({
    target: {tabId: tab.id},
    func: () => {
      const urls = [];
      for (const iframe of document.querySelectorAll('iframe')) {
        if (iframe.src && /vimeo\.com/i.test(iframe.src)) urls.push(iframe.src);
      }
      for (const node of document.querySelectorAll('[data-vimeo-url],[data-vimeo-id],a[href*="vimeo.com"]')) {
        const value = node.dataset?.vimeoUrl || (node.dataset?.vimeoId ? `https://player.vimeo.com/video/${node.dataset.vimeoId}` : node.href);
        if (value && /vimeo\.com/i.test(value)) urls.push(value);
      }
      const html = document.documentElement?.innerHTML || '';
      const embedded = html.match(/https?:\\?\/\\?\/player\.vimeo\.com\\?\/video\\?\/\d+[^"'<> ]*/i)?.[0];
      if (embedded) urls.push(embedded.replaceAll('\\/', '/'));
      return [...new Set(urls)].map(value => new URL(value, location.href).toString());
    }
  });
  const player = result?.[0]?.result?.find(url => /vimeo\.com/i.test(url));
  if (!player) throw new Error('No Vimeo or YouTube video was detected in the current tab.');
  found = {tab, player: normaliseUrl(player), page: tab.url, kind: 'vimeo'};
  setDetectedLabel(found.kind);
  playerBox.textContent = found.player;
  downloadButton.disabled = false;
  status('Vimeo video detected.', 'ok');
  return found;
}

async function cookiesFor(url) {
  try { return await chrome.cookies.getAll({url}); } catch (_) { return []; }
}

async function allCookies(page, player) {
  const lists = await Promise.all([cookiesFor(page), cookiesFor(player)]);
  const seen = new Set();
  return lists.flat().filter(cookie => {
    const key = `${cookie.domain}\t${cookie.path}\t${cookie.name}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

detectButton.addEventListener('click', async () => {
  detectButton.disabled = true;
  try { await findPlayer(); } catch (error) { status(error.message, 'error'); }
  finally { detectButton.disabled = false; }
});

downloadButton.addEventListener('click', async () => {
  downloadButton.disabled = true;
  try {
    if (!found) await findPlayer();
    const cookies = document.querySelector('#useCookies').checked ? await allCookies(found.page, found.player) : [];
    status('Starting the local download…');
    const response = await fetch(`${settings.downloaderService}/tools/${found.kind}/download`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        // Send the actual player URL.  The outer page can be a course/order
        // page whose iframe is created by JavaScript and is not discoverable
        // by yt-dlp's generic extractor.  Keep the outer page as Referer so
        // Vimeo still sees the authenticated embed context.
        urls: found.player,
        referer: found.page,
        cookies,
        use_chrome: false,
        format: document.querySelector('#format').value,
        name: document.querySelector('#name').value.trim(),
        output: document.querySelector('#output').value.trim(),
        media_server_api: serverApiInput.value.trim(),
        destination_path: settings.destinationPath
      })
    });
    if (!response.ok) throw new Error((await response.json()).message || `HTTP ${response.status}`);
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    for (;;) {
      const part = await reader.read();
      buffer += decoder.decode(part.value || new Uint8Array(), {stream: !part.done});
      const lines = buffer.split('\n'); buffer = lines.pop();
      for (const line of lines) if (line.trim()) {
        const item = JSON.parse(line);
        if (item.type === 'error' || item.type === 'item-error') status(item.message, 'error');
        else if (item.type === 'done' || item.type === 'item-done') status(item.message, 'ok');
        else if (item.type === 'stage') status(item.message);
      }
      if (part.done) break;
    }
    if (buffer.trim()) { const item = JSON.parse(buffer); status(item.message || 'Done.', item.type === 'error' ? 'error' : 'ok'); }
  } catch (error) { status(explainFetchError(error, settings.downloaderService), 'error'); }
  finally { downloadButton.disabled = false; }
});

async function refreshRecorder() {
  const state = await chrome.runtime.sendMessage({type: 'STATUS'});
  const active = Boolean(state?.active);
  recordButton.textContent = active ? 'Stop recording' : 'Start recording';
  recordButton.classList.toggle('stop', active);
  serverApiInput.disabled = active;
}

recordButton.addEventListener('click', async () => {
  recordButton.disabled = true;
  try {
    const state = await chrome.runtime.sendMessage({type: 'STATUS'});
    if (state?.active) {
      const result = await chrome.runtime.sendMessage({type: 'STOP_RECORDING'});
      if (!result?.ok) throw new Error(result?.error || 'Recording could not be stopped.');
      status(`Recording saved: ${result.path || 'completed'}`, 'ok');
    } else {
      const result = await chrome.runtime.sendMessage({
        type: 'START_RECORDING',
        directory: settings.destinationPath,
        filename: document.querySelector('#name').value.trim() || 'capture',
        mediaServerApi: serverApiInput.value.trim()
      });
      if (!result?.ok) throw new Error(result?.error || 'Recording could not be started.');
      status(`Recording to ${result.path || settings.destinationPath}…`);
    }
  } catch (error) { status(error.message, 'error'); }
  finally { recordButton.disabled = false; await refreshRecorder(); }
});

chrome.storage.local.get(defaults, values => {
  settings = {...defaults, ...values};
  serverApiInput.value = settings.mediaServerApi;
  serverApiInput.addEventListener('input', () => {
    setServerStatus('Not tested yet.');
    const syntaxError = validateServerAddress(serverApiInput.value.trim());
    if (syntaxError && serverApiInput.value.trim()) setServerStatus(`✕ ${syntaxError}`, 'error');
  });
  serverApiInput.addEventListener('change', () => {
    settings.mediaServerApi = serverApiInput.value.trim();
    chrome.storage.local.set({mediaServerApi: settings.mediaServerApi});
    folderChildren.clear();
    loadFolderTree().catch(error => status(error.message, 'error'));
  });
  document.querySelector('#output').value = settings.destinationPath;
  Promise.all([findPlayer().catch(() => {}), refreshRecorder().catch(() => {}), loadFolderTree()]);
});
