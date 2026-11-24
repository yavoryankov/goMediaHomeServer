package main

import (
	"database/sql"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"log"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

//go:embed web/index.html
var webFS embed.FS

type Config struct {
	Host         string `json:"host"`
	Port         int    `json:"port"`
	MediaRoot    string `json:"media_root"`
	DatabasePath string `json:"database_path"`
}

type App struct {
	cfg Config
	db  *sql.DB
}

type entry struct {
	Name     string `json:"name"`
	Path     string `json:"path"`
	IsDir    bool   `json:"is_dir"`
	Size     int64  `json:"size"`
	Modified string `json:"modified"`
	Mime     string `json:"mime"`
	Keywords string `json:"keywords"`
}

func main() {
	cfg := loadConfig()
	root, err := filepath.Abs(cfg.MediaRoot)
	if err != nil {
		log.Fatal(err)
	}
	if err := os.MkdirAll(root, 0755); err != nil {
		log.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(cfg.DatabasePath), 0755); err != nil {
		log.Fatal(err)
	}
	db, err := sql.Open("sqlite", cfg.DatabasePath)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS files (
	 id INTEGER PRIMARY KEY, relative_path TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
	 is_dir INTEGER NOT NULL, size_bytes INTEGER NOT NULL DEFAULT 0,
		mime_type TEXT NOT NULL DEFAULT '', modified_at TEXT NOT NULL,
		keywords TEXT NOT NULL DEFAULT ''
	); CREATE INDEX IF NOT EXISTS idx_files_path ON files(relative_path);`); err != nil {
		log.Fatal(err)
	}
	if err := ensureKeywordsColumn(db); err != nil {
		log.Fatal(err)
	}
	app := &App{cfg: cfg, db: db}
	if err := app.syncIndex(root); err != nil {
		log.Fatal(err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/health", app.health)
	mux.HandleFunc("/api/v1/files", app.files)
	mux.HandleFunc("/api/v1/folders", app.folders)
	mux.HandleFunc("/api/v1/search", app.search)
	mux.HandleFunc("/api/v1/stream", app.streamQuery)
	mux.HandleFunc("/api/v1/media/", app.streamPath)
	mux.HandleFunc("/api/v1/upload", app.upload)
	mux.HandleFunc("/media/", app.media)
	mux.HandleFunc("/chrome-extension", app.chromeExtension)
	mux.HandleFunc("/downloads/goMediaHomeServer-chrome-extension-v2.zip", app.chromeExtensionDownload)
	mux.HandleFunc("/", app.index)
	addr := fmt.Sprintf("%s:%d", cfg.Host, cfg.Port)
	log.Printf("goMediaHomeServer listening on http://%s (media root: %s)", addr, root)
	log.Fatal(http.ListenAndServe(addr, logging(mux)))
}

func (a *App) chromeExtension(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/chrome-extension" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	serverAPI := "http://" + r.Host + "/api/v1"
	page := `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="theme-color" content="#0c343c"><title>goMediaHomeServer · Chrome plugin</title><style>:root{--nav:#0c343c;--mint:#0c817b;--canvas:#f5f8f9;--edge:#e3ecec;--text:#192c36;--sub:#71848b}*{box-sizing:border-box}body{margin:0;background:var(--canvas);color:var(--text);font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}.app{min-height:100vh;display:grid;grid-template-columns:246px 1fr;grid-template-rows:70px 1fr}.topbar{grid-column:1/-1;background:#fff;border-bottom:1px solid var(--edge);display:flex;align-items:center;gap:16px;padding:0 28px}.hamburger{font-size:23px;color:#405d65}.brand{display:flex;align-items:center;gap:11px;min-width:210px}.brandmark{width:36px;height:36px;border-radius:11px;background:var(--nav);color:#fff;display:grid;place-items:center;font-size:20px}.brand b{display:block;font-size:15px}.brand small{color:#83979c;font-size:10px;letter-spacing:.5px}.crumb{border-left:1px solid var(--edge);padding-left:18px;color:#72888e;font-size:12px}.spacer{flex:1}.online{border:1px solid #d7eee6;border-radius:20px;padding:8px 12px;color:#397f70;background:#f1fbf6;font-size:11px;font-weight:700}.avatar{width:33px;height:33px;border-radius:50%;background:#e6f2ef;color:#0f706b;display:grid;place-items:center;font-weight:800;font-size:11px}.sidebar{grid-row:2;background:var(--nav);color:#c1d6d7;padding:25px 13px}.section{margin:0 15px 11px;color:#78a4a8;text-transform:uppercase;letter-spacing:1.5px;font-size:10px;font-weight:700}.nav{display:block;color:#c1d6d7;text-decoration:none;border-radius:10px;padding:12px 13px;margin-bottom:3px;font-size:12px}.nav:hover,.nav.active{background:#1d5057;color:#fff}.main{padding:42px clamp(18px,4vw,60px)}.main-inner{max-width:960px;margin:auto}.crumbs{color:#8a9ba0;font-size:11px;margin-bottom:18px}.crumbs a{color:#718d92;text-decoration:none}.pagehead{display:flex;justify-content:space-between;align-items:flex-start;gap:20px;margin-bottom:27px}.pagehead h1{font-size:31px;letter-spacing:-1.3px;margin:0 0 7px}.pagehead p{color:#7d9096;margin:0;line-height:1.7}.card{background:#fff;border:1px solid var(--edge);border-radius:16px;box-shadow:0 8px 37px #183d3c08;padding:28px}.card h2{font-size:18px;margin:0 0 8px}.card p{color:var(--sub);line-height:1.7}.api{margin:24px 0;padding:18px;background:#eef4ff;border:1px solid #cbdcff;border-radius:11px}.api b{display:block;font-size:12px;color:#3d5b8a}.api code{display:block;margin-top:9px;padding:12px;background:#fff;border:1px solid #dce5f5;border-radius:8px;word-break:break-all;font-size:14px;color:#18344e}.api span{display:block;margin-top:8px;color:#5e789a;font-size:12px}.download{display:inline-flex;background:var(--mint);color:#fff;text-decoration:none;padding:12px 17px;border-radius:10px;font-weight:700}.download:hover{background:#086b66}.note{margin-top:22px;padding:14px;background:#eef8f5;border-radius:10px;font-size:13px;color:#47746e}.copy-api{display:inline-flex;margin-top:10px;border:1px solid #abc4e9;border-radius:8px;background:#fff;color:#3d5b8a;padding:8px 11px;font-size:12px;font-weight:700;cursor:pointer}.copy-api:hover{background:#f4f8ff}@media(max-width:760px){.app{display:block}.topbar{height:61px;padding:0 14px}.crumb,.online{display:none}.sidebar{display:none}.main{padding:25px 14px}.pagehead h1{font-size:26px}.card{padding:20px}}
</style></head><body><div class="app"><header class="topbar"><span class="hamburger">☰</span><div class="brand"><span class="brandmark">⌂</span><div><b>goMediaHomeServer</b><small>PERSONAL MEDIA CLOUD</small></div></div><div class="crumb">Workspace&nbsp; / &nbsp;<strong>Chrome plugin</strong></div><div class="spacer"></div><span class="online">● LAN · Online</span><span class="avatar">AD</span></header><aside class="sidebar"><div class="section">Main menu</div><a class="nav" href="/">▣&nbsp; All files</a><a class="nav" href="/">◷&nbsp; Recently added</a><a class="nav" href="/">☆&nbsp; Favorites</a><div class="section" style="margin-top:28px">Management</div><a class="nav active" href="/chrome-extension">▣&nbsp; Chrome plugin</a><a class="nav" href="/">⚙&nbsp; Settings</a></aside><main class="main"><div class="main-inner"><div class="crumbs"><a href="/">Library</a> &nbsp; / &nbsp; Chrome plugin</div><div class="pagehead"><div><h1>Chrome plugin</h1><p>Download and configure the goMediaHomeServer browser extension.</p></div></div><section class="card"><h2>Media downloader</h2><p>Download permitted YouTube and Vimeo media to a selected folder in your local media server.</p><div class="api"><b>Media server API address</b><code id="apiAddress">` + html.EscapeString(serverAPI) + `</code><button class="copy-api" id="copyApi" type="button">Copy address</button><span id="copyStatus">Copy this address into the plugin field.</span></div><a class="download" href="/downloads/goMediaHomeServer-chrome-extension-v2.zip">Download plugin v2</a><div class="note">After downloading, unzip the file and open <b>chrome://extensions</b>. Enable <b>Developer mode</b>, choose <b>Load unpacked</b>, and select the unzipped folder. Then enter the API address above in the plugin.</div></section></div></main></div><script>document.getElementById('copyApi').addEventListener('click',async()=>{const address=document.getElementById('apiAddress').textContent;const status=document.getElementById('copyStatus');try{await navigator.clipboard.writeText(address);status.textContent='Copied to clipboard.';status.style.color='#397f70'}catch(_){status.textContent='Copy failed. Select the address manually.';status.style.color='#b13d4f'}});</script></body></html>`
	fmt.Fprint(w, page)
}

func (a *App) chromeExtensionDownload(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/downloads/goMediaHomeServer-chrome-extension-v2.zip" {
		http.NotFound(w, r)
		return
	}
	path := filepath.Join("web", "goMediaHomeServer-chrome-extension-v2.zip")
	if _, err := os.Stat(path); err != nil {
		http.Error(w, "Chrome plugin package is not installed on the server", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Disposition", `attachment; filename="goMediaHomeServer-chrome-extension-v2.zip"`)
	http.ServeFile(w, r, path)
}

func ensureKeywordsColumn(db *sql.DB) error {
	rows, err := db.Query("PRAGMA table_info(files)")
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var cid, notNull, pk int
		var name, columnType string
		var defaultValue any
		if err := rows.Scan(&cid, &name, &columnType, &notNull, &defaultValue, &pk); err != nil {
			return err
		}
		if name == "keywords" {
			return rows.Err()
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	_, err = db.Exec("ALTER TABLE files ADD COLUMN keywords TEXT NOT NULL DEFAULT ''")
	return err
}

func loadConfig() Config {
	cfg := Config{Host: "0.0.0.0", Port: 8095, MediaRoot: "./MediaHomeLibrary", DatabasePath: "./data/gomedia.db"}
	if b, err := os.ReadFile("config.json"); err == nil {
		if err := json.Unmarshal(b, &cfg); err != nil {
			log.Fatal(err)
		}
	}
	if cfg.Port == 0 {
		cfg.Port = 8095
	}
	return cfg
}

func (a *App) syncIndex(root string) error {
	seen := map[string]bool{"": true}
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if path == root {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		seen[rel] = true
		mt := info.ModTime().UTC().Format(time.RFC3339)
		mimeType := ""
		if !info.IsDir() {
			mimeType = mime.TypeByExtension(filepath.Ext(info.Name()))
		}
		_, err = a.db.Exec(`INSERT INTO files(relative_path,name,is_dir,size_bytes,mime_type,modified_at) VALUES(?,?,?,?,?,?)
		ON CONFLICT(relative_path) DO UPDATE SET name=excluded.name,is_dir=excluded.is_dir,size_bytes=excluded.size_bytes,mime_type=excluded.mime_type,modified_at=excluded.modified_at`, rel, info.Name(), info.IsDir(), info.Size(), mimeType, mt)
		return err
	})
	if err != nil {
		return err
	}
	rows, err := a.db.Query("SELECT relative_path FROM files")
	if err != nil {
		return err
	}
	stale := make([]string, 0)
	for rows.Next() {
		var rel string
		if err := rows.Scan(&rel); err != nil {
			rows.Close()
			return err
		}
		if !seen[rel] {
			stale = append(stale, rel)
		}
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, rel := range stale {
		if _, err := a.db.Exec("DELETE FROM files WHERE relative_path=?", rel); err != nil {
			return err
		}
	}
	return nil
}

func (a *App) safePath(rel string) (string, error) {
	rel = strings.TrimSpace(strings.ReplaceAll(rel, "\\", "/"))
	rel = strings.TrimPrefix(rel, "/")
	if rel == "." {
		rel = ""
	}
	root, _ := filepath.Abs(a.cfg.MediaRoot)
	full := filepath.Join(root, filepath.FromSlash(rel))
	clean, _ := filepath.Abs(filepath.Clean(full))
	if clean != root && !strings.HasPrefix(clean, root+string(os.PathSeparator)) {
		return "", errors.New("path escapes media root")
	}
	return clean, nil
}

func (a *App) index(w http.ResponseWriter, r *http.Request) {
	http.ServeFileFS(w, r, webFS, "web/index.html")
}

func (a *App) health(w http.ResponseWriter, r *http.Request) {
	jsonOut(w, http.StatusOK, map[string]any{"status": "ok", "media_root": a.cfg.MediaRoot})
}

func (a *App) files(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		a.listFiles(w, r)
		return
	}
	if r.Method == http.MethodPatch {
		a.rename(w, r)
		return
	}
	if r.Method == http.MethodDelete {
		a.remove(w, r)
		return
	}
	w.WriteHeader(http.StatusMethodNotAllowed)
}

func (a *App) listFiles(w http.ResponseWriter, r *http.Request) {
	rel := r.URL.Query().Get("path")
	full, err := a.safePath(rel)
	if err != nil {
		jsonError(w, 400, err)
		return
	}
	info, err := os.Stat(full)
	if err != nil {
		jsonError(w, 404, err)
		return
	}
	if !info.IsDir() {
		jsonError(w, 400, errors.New("path is not a directory"))
		return
	}
	items, err := os.ReadDir(full)
	if err != nil {
		jsonError(w, 500, err)
		return
	}
	out := make([]entry, 0, len(items))
	for _, item := range items {
		i, err := item.Info()
		if err != nil {
			continue
		}
		p := filepath.ToSlash(filepath.Join(rel, item.Name()))
		mt := i.ModTime().UTC().Format(time.RFC3339)
		m := ""
		if !i.IsDir() {
			m = mime.TypeByExtension(filepath.Ext(i.Name()))
		}
		keywords := ""
		_ = a.db.QueryRow("SELECT keywords FROM files WHERE relative_path=?", p).Scan(&keywords)
		out = append(out, entry{Name: i.Name(), Path: p, IsDir: i.IsDir(), Size: i.Size(), Modified: mt, Mime: m, Keywords: keywords})
	}
	jsonOut(w, 200, map[string]any{"path": strings.Trim(filepath.ToSlash(rel), "/"), "items": out})
}

func (a *App) folders(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		a.listFolders(w, r)
		return
	}
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	var in struct{ Path, Name string }
	if !decodeJSON(w, r, &in) {
		return
	}
	parent, err := a.safePath(in.Path)
	if err != nil {
		jsonError(w, 400, err)
		return
	}
	name := filepath.Base(filepath.Clean(in.Name))
	if name == "." || name == ".." || name != in.Name || strings.ContainsAny(name, "/\\") {
		jsonError(w, 400, errors.New("invalid folder name"))
		return
	}
	if err := os.Mkdir(filepath.Join(parent, name), 0755); err != nil {
		jsonError(w, 409, err)
		return
	}
	_ = a.syncIndex(filepath.Clean(a.cfg.MediaRoot))
	jsonOut(w, 201, map[string]string{"status": "created"})
}

func (a *App) listFolders(w http.ResponseWriter, r *http.Request) {
	rel := r.URL.Query().Get("path")
	full, err := a.safePath(rel)
	if err != nil {
		jsonError(w, http.StatusBadRequest, err)
		return
	}
	info, err := os.Stat(full)
	if err != nil {
		jsonError(w, http.StatusNotFound, err)
		return
	}
	if !info.IsDir() {
		jsonError(w, http.StatusBadRequest, errors.New("path is not a directory"))
		return
	}
	items, err := os.ReadDir(full)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, err)
		return
	}
	out := make([]entry, 0)
	for _, item := range items {
		child, err := item.Info()
		if err != nil || !child.IsDir() {
			continue
		}
		path := filepath.ToSlash(filepath.Join(rel, item.Name()))
		keywords := ""
		_ = a.db.QueryRow("SELECT keywords FROM files WHERE relative_path=?", path).Scan(&keywords)
		out = append(out, entry{Name: child.Name(), Path: path, IsDir: true, Size: child.Size(), Modified: child.ModTime().UTC().Format(time.RFC3339), Keywords: keywords})
	}
	jsonOut(w, http.StatusOK, map[string]any{"path": strings.Trim(filepath.ToSlash(rel), "/"), "items": out})
}

func (a *App) search(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if q == "" {
		jsonOut(w, http.StatusOK, map[string]any{"query": "", "items": []entry{}})
		return
	}
	term := "%" + strings.ToLower(q) + "%"
	rows, err := a.db.Query(`SELECT name, relative_path, is_dir, size_bytes, modified_at, mime_type, keywords
		FROM files WHERE lower(name) LIKE ? OR lower(relative_path) LIKE ? OR lower(keywords) LIKE ?
		ORDER BY lower(name), relative_path`, term, term, term)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, err)
		return
	}
	defer rows.Close()
	items := make([]entry, 0)
	for rows.Next() {
		var item entry
		var isDir int
		if err := rows.Scan(&item.Name, &item.Path, &isDir, &item.Size, &item.Modified, &item.Mime, &item.Keywords); err != nil {
			jsonError(w, http.StatusInternalServerError, err)
			return
		}
		item.IsDir = isDir != 0
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		jsonError(w, http.StatusInternalServerError, err)
		return
	}
	jsonOut(w, http.StatusOK, map[string]any{"query": q, "items": items})
}

func (a *App) streamQuery(w http.ResponseWriter, r *http.Request) {
	a.serveStream(w, r, r.URL.Query().Get("path"))
}

func (a *App) streamPath(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/v1/media/")
	if strings.HasSuffix(path, "/stream") {
		path = strings.TrimSuffix(path, "/stream")
	}
	a.serveStream(w, r, path)
}

func (a *App) serveStream(w http.ResponseWriter, r *http.Request, rel string) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	full, err := a.safePath(rel)
	if err != nil {
		http.Error(w, "bad path", http.StatusBadRequest)
		return
	}
	file, err := os.Open(full)
	if err != nil {
		if os.IsNotExist(err) {
			http.NotFound(w, r)
			return
		}
		http.Error(w, "cannot open media", http.StatusInternalServerError)
		return
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || info.IsDir() {
		http.NotFound(w, r)
		return
	}
	contentType := mime.TypeByExtension(filepath.Ext(info.Name()))
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Accept-Ranges", "bytes")
	w.Header().Set("Cache-Control", "private, no-cache")
	http.ServeContent(w, r, info.Name(), info.ModTime(), file)
}

func (a *App) upload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if err := r.ParseMultipartForm(32 << 20); err != nil {
		jsonError(w, 400, err)
		return
	}
	dir := r.FormValue("path")
	targetDir, err := a.safePath(dir)
	if err != nil {
		jsonError(w, 400, err)
		return
	}
	if err := os.MkdirAll(targetDir, 0755); err != nil {
		jsonError(w, 500, err)
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		jsonError(w, 400, err)
		return
	}
	defer file.Close()
	name := filepath.Base(header.Filename)
	if name == "." || name == ".." || name != header.Filename || strings.ContainsAny(name, "/\\") {
		jsonError(w, 400, errors.New("invalid file name"))
		return
	}
	dest := filepath.Join(targetDir, name)
	if _, err := os.Stat(dest); err == nil {
		jsonError(w, 409, errors.New("file already exists"))
		return
	}
	tmp, err := os.CreateTemp(targetDir, ".upload-*")
	if err != nil {
		jsonError(w, 500, err)
		return
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err = io.Copy(tmp, file); err != nil {
		tmp.Close()
		jsonError(w, 500, err)
		return
	}
	if err = tmp.Close(); err != nil {
		jsonError(w, 500, err)
		return
	}
	if err = os.Rename(tmpName, dest); err != nil {
		jsonError(w, 500, err)
		return
	}
	_ = a.syncIndex(filepath.Clean(a.cfg.MediaRoot))
	jsonOut(w, 201, map[string]string{"status": "uploaded", "path": filepath.ToSlash(filepath.Join(dir, name))})
}

func (a *App) rename(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Path, NewPath string
		Keywords      *string `json:"keywords"`
	}
	if !decodeJSON(w, r, &in) {
		return
	}
	old, err := a.safePath(in.Path)
	if err != nil {
		jsonError(w, 400, err)
		return
	}
	nextRel := in.NewPath
	if nextRel == "" {
		nextRel = in.Path
	}
	next, err := a.safePath(nextRel)
	if err != nil {
		jsonError(w, 400, err)
		return
	}
	if _, err := os.Stat(old); err != nil {
		jsonError(w, 404, err)
		return
	}
	if in.NewPath != "" && filepath.Clean(old) != filepath.Clean(next) {
		if _, err := os.Stat(next); err == nil {
			jsonError(w, 409, errors.New("destination already exists"))
			return
		}
		if err := os.MkdirAll(filepath.Dir(next), 0755); err != nil {
			jsonError(w, 500, err)
			return
		}
		if err := os.Rename(old, next); err != nil {
			jsonError(w, 500, err)
			return
		}
	}
	if in.Keywords != nil {
		keywordsPath := filepath.ToSlash(strings.Trim(nextRel, "/"))
		if _, err := a.db.Exec("UPDATE files SET keywords=? WHERE relative_path=?", normalizeKeywords(*in.Keywords), keywordsPath); err != nil {
			jsonError(w, 500, err)
			return
		}
	}
	_ = a.syncIndex(filepath.Clean(a.cfg.MediaRoot))
	jsonOut(w, 200, map[string]string{"status": "updated"})
}

func normalizeKeywords(value string) string {
	parts := strings.Split(value, ",")
	clean := make([]string, 0, len(parts))
	seen := map[string]bool{}
	for _, part := range parts {
		word := strings.TrimSpace(part)
		key := strings.ToLower(word)
		if word != "" && !seen[key] {
			clean = append(clean, word)
			seen[key] = true
		}
	}
	return strings.Join(clean, ", ")
}

func (a *App) remove(w http.ResponseWriter, r *http.Request) {
	rel := r.URL.Query().Get("path")
	full, err := a.safePath(rel)
	if err != nil || rel == "" {
		jsonError(w, 400, errors.New("invalid delete path"))
		return
	}
	if err := os.RemoveAll(full); err != nil {
		jsonError(w, 500, err)
		return
	}
	_ = a.syncIndex(filepath.Clean(a.cfg.MediaRoot))
	jsonOut(w, 200, map[string]string{"status": "deleted"})
}

func (a *App) media(w http.ResponseWriter, r *http.Request) {
	rel := strings.TrimPrefix(r.URL.Path, "/media/")
	full, err := a.safePath(rel)
	if err != nil {
		http.Error(w, "bad path", 400)
		return
	}
	info, err := os.Stat(full)
	if err != nil || info.IsDir() {
		http.NotFound(w, r)
		return
	}
	http.ServeFile(w, r, full)
}

func decodeJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		jsonError(w, 400, err)
		return false
	}
	return true
}
func jsonOut(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
func jsonError(w http.ResponseWriter, status int, err error) {
	jsonOut(w, status, map[string]string{"error": err.Error()})
}
func logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start))
	})
}

var _ = strconv.IntSize
