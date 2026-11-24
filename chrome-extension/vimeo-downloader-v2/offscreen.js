let recorder = null;
let stream = null;
let audioContext = null;
let pending = [];
let stopResolve = null;
let stopReject = null;

function chooseMime() {
  return ['video/webm;codecs=vp9,opus', 'video/webm;codecs=vp8,opus', 'video/webm']
    .find(value => MediaRecorder.isTypeSupported(value)) || '';
}

async function startCapture(streamId) {
  if (recorder) throw new Error('Вече има активен запис.');
  stream = await navigator.mediaDevices.getUserMedia({
    audio: { mandatory: { chromeMediaSource: 'tab', chromeMediaSourceId: streamId } },
    video: { mandatory: { chromeMediaSource: 'tab', chromeMediaSourceId: streamId } }
  });
  // tabCapture otherwise mutes the tab for the user; route the captured audio
  // back to the local output while it is being recorded.
  audioContext = new AudioContext();
  await audioContext.resume().catch(() => {});
  const source = audioContext.createMediaStreamSource(stream);
  source.connect(audioContext.destination);
  const mimeType = chooseMime();
  recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
  pending = [];
  recorder.ondataavailable = event => {
    if (!event.data.size) return;
    const upload = event.data.arrayBuffer().then(data => chrome.runtime.sendMessage({
      type: 'CHUNK', sessionId: currentSessionId, data
    })).then(result => {
      if (!result?.ok) throw new Error(result?.error || 'Грешка при записване на сегмента.');
    });
    pending.push(upload);
  };
  recorder.onstop = async () => {
    try {
      await Promise.all(pending);
      const result = await chrome.runtime.sendMessage({ type: 'FINISH', sessionId: currentSessionId });
      if (!result?.ok) throw new Error(result?.error || 'Грешка при приключване на файла.');
      stopResolve(result);
    } catch (error) {
      stopReject?.(error);
    } finally { cleanup(); }
  };
  recorder.start(1000);
}

function stopCapture() {
  if (!recorder) throw new Error('Няма активен запис.');
  return new Promise((resolve, reject) => {
    stopResolve = resolve;
    stopReject = reject;
    recorder.stop();
  });
}

let currentSessionId = '';
function cleanup() {
  recorder = null;
  stream?.getTracks().forEach(track => track.stop());
  stream = null;
  audioContext?.close().catch(() => {});
  audioContext = null;
  pending = [];
  currentSessionId = '';
  stopResolve = null;
  stopReject = null;
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  (async () => {
    try {
      if (message.type === 'START_CAPTURE') {
        currentSessionId = message.sessionId;
        await startCapture(message.streamId);
        sendResponse({ ok: true });
      } else if (message.type === 'STOP_CAPTURE') {
        sendResponse(await stopCapture());
      }
    } catch (error) { sendResponse({ ok: false, error: error.message }); }
  })();
  return true;
});
