const defaults = {
  mediaServerApi: 'http://YOUR-IMAC-IP:8095/api/v1',
  destinationPath: 'Yavor/Courses/Arestovich',
  downloaderService: 'http://127.0.0.1:7071',
  recorderService: 'http://127.0.0.1:7071'
};

const fields = {
  mediaServerApi: document.querySelector('#server'),
  destinationPath: document.querySelector('#path'),
  downloaderService: document.querySelector('#downloader'),
  recorderService: document.querySelector('#recorder')
};

chrome.storage.local.get(defaults, values => {
  for (const [key, field] of Object.entries(fields)) field.value = values[key] || defaults[key];
});

document.querySelector('#save').addEventListener('click', () => {
  const values = Object.fromEntries(Object.entries(fields).map(([key, field]) => [key, field.value.trim()]));
  chrome.storage.local.set(values, () => {
    document.querySelector('#status').textContent = 'Settings saved.';
  });
});
