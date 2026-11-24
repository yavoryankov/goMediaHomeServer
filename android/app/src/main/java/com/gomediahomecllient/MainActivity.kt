package com.gomediahomecllient

import android.content.Context
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem as PlayerMediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.gomediahomecllient.ui.theme.GoMediaHomecllientTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

private const val DEFAULT_API = "http://YOUR-IMAC-IP:8095/api/v1"
private data class MediaFile(val name: String, val path: String, val isDir: Boolean, val size: Long, val mime: String, val keywords: String)
private enum class AppScreen { TYPES, DIRECTORIES, SEARCH, FAVORITE_FILES, FAVORITE_FOLDERS, SETTINGS }

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContent { GoMediaHomecllientTheme { GoMediaApp() } }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GoMediaApp() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val preferences = remember { context.getSharedPreferences("gomedia", Context.MODE_PRIVATE) }
    var apiAddress by rememberSaveable { mutableStateOf(preferences.getString("api", DEFAULT_API) ?: DEFAULT_API) }
    var screen by rememberSaveable { mutableStateOf(AppScreen.TYPES.name) }
    var items by remember { mutableStateOf(emptyList<MediaFile>()) }
    var currentPath by remember { mutableStateOf("") }
    var searchText by rememberSaveable { mutableStateOf("") }
    var recent by remember { mutableStateOf(loadStored(preferences, "recent")) }
    var favorites by remember { mutableStateOf(loadStored(preferences, "favorites")) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var playing by remember { mutableStateOf<MediaFile?>(null) }
    fun baseUrl() = apiAddress.trim().trimEnd('/')
    suspend fun loadDirectory(path: String) {
        loading = true; error = null
        try { val json = JSONObject(getJson("${baseUrl()}/files?path=${encode(path)}")); currentPath = json.optString("path", path); items = parseItems(json.optJSONArray("items")) }
        catch (e: Exception) { error = e.message ?: "The server could not be reached." }; loading = false
    }
    suspend fun search() {
        if (searchText.trim().isEmpty()) return
        loading = true; error = null
        try { items = parseItems(JSONObject(getJson("${baseUrl()}/search?q=${encode(searchText.trim())}")).optJSONArray("items")) }
        catch (e: Exception) { error = e.message ?: "Search failed." }; loading = false
    }
    fun openFile(file: MediaFile) {
        if (file.isDir) scope.launch { loadDirectory(file.path) }
        else { recent = listOf(file) + recent.filterNot { it.path == file.path }.take(5); saveStored(preferences, "recent", recent); playing = file }
    }
    fun toggleFavorite(file: MediaFile) { favorites = if (favorites.any { it.path == file.path }) favorites.filterNot { it.path == file.path } else listOf(file) + favorites; saveStored(preferences, "favorites", favorites) }
    LaunchedEffect(Unit) { loadDirectory("") }
    if (playing != null) { PlayerScreen(playing!!, baseUrl(), favorites.any { it.path == playing!!.path }, { toggleFavorite(playing!!) }) { playing = null }; return }
    Scaffold(
        topBar = { TopAppBar(title = { Text(screenTitle(AppScreen.valueOf(screen))) }) },
        bottomBar = { NavigationBar { listOf(AppScreen.TYPES to Icons.Default.GridView, AppScreen.DIRECTORIES to Icons.Default.Folder, AppScreen.SEARCH to Icons.Default.Search, AppScreen.FAVORITE_FILES to Icons.Default.Star, AppScreen.FAVORITE_FOLDERS to Icons.Default.FolderSpecial, AppScreen.SETTINGS to Icons.Default.Settings).forEach { (target, icon) -> NavigationBarItem(screen == target.name, { screen = target.name }, icon = { Icon(icon, screenTitle(target)) }) } } }
    ) { padding ->
        when (AppScreen.valueOf(screen)) {
            AppScreen.TYPES -> TypesScreen({ query -> searchText = query; screen = AppScreen.SEARCH.name; scope.launch { search() } }, Modifier.padding(padding))
            AppScreen.DIRECTORIES -> DirectoryScreen(items, currentPath, loading, error, ::openFile, { scope.launch { loadDirectory(currentPath) } }, Modifier.padding(padding))
            AppScreen.SEARCH -> SearchScreen(searchText, { searchText = it }, items, loading, error, ::openFile, { scope.launch { search() } }, Modifier.padding(padding))
            AppScreen.FAVORITE_FILES -> FavoritesScreen("Favorite Files", recent.filterNot { it.isDir }.take(6), favorites.filterNot { it.isDir }, ::openFile, ::toggleFavorite, Modifier.padding(padding))
            AppScreen.FAVORITE_FOLDERS -> FavoritesScreen("Favorite Folders", emptyList(), favorites.filter { it.isDir }, ::openFile, ::toggleFavorite, Modifier.padding(padding))
            AppScreen.SETTINGS -> SettingsScreen(apiAddress, { apiAddress = it; preferences.edit().putString("api", it).apply() }, { scope.launch { loadDirectory(currentPath) } }, loading, error, Modifier.padding(padding))
        }
    }
}

@Composable private fun TypesScreen(onType: (String) -> Unit, modifier: Modifier) { Column(modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) { Text("Browse by type", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold); Text("Choose a category to find content quickly.", color = Color.Gray); TypeCard("Video", "Movies and recordings", Icons.Default.PlayArrow, Color(0xFF7E57C2)) { onType(".mp4") }; TypeCard("Music", "Audio and music files", Icons.Default.MusicNote, Color(0xFF1976D2)) { onType(".mp3") }; TypeCard("Documents", "PDF, text and office files", Icons.Default.Description, Color(0xFFEF8C00)) { onType(".pdf") } } }

@Composable private fun TypeCard(title: String, subtitle: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, onClick: () -> Unit) { Card(Modifier.fillMaxWidth().clickable(onClick = onClick), shape = RoundedCornerShape(18.dp)) { Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) { Icon(icon, title, tint = color, modifier = Modifier.size(42.dp)); Column(Modifier.padding(start = 16.dp)) { Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold); Text(subtitle, color = Color.Gray) }; Spacer(Modifier.weight(1f)); Icon(Icons.Default.ArrowForward, null) } } }

@Composable private fun DirectoryScreen(items: List<MediaFile>, path: String, loading: Boolean, error: String?, onOpen: (MediaFile) -> Unit, onRefresh: () -> Unit, modifier: Modifier) { Column(modifier.fillMaxSize()) { Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { IconButton(onClick = onRefresh) { Icon(Icons.Default.Refresh, "Refresh") }; Text(if (path.isEmpty()) "Library" else path, fontWeight = FontWeight.SemiBold) }; MediaList(items, loading, error, onOpen) } }

@Composable private fun SearchScreen(query: String, onQuery: (String) -> Unit, items: List<MediaFile>, loading: Boolean, error: String?, onOpen: (MediaFile) -> Unit, onSearch: () -> Unit, modifier: Modifier) { Column(modifier.fillMaxSize()) { Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) { OutlinedTextField(query, onQuery, Modifier.weight(1f), placeholder = { Text("File name or keyword") }, singleLine = true); IconButton(onClick = onSearch) { Icon(Icons.Default.Search, "Search") } }; Text("Results", Modifier.padding(horizontal = 16.dp), fontWeight = FontWeight.Bold); MediaList(items, loading, error, onOpen) } }

@Composable private fun FavoritesScreen(title: String, recent: List<MediaFile>, favorites: List<MediaFile>, onOpen: (MediaFile) -> Unit, onToggle: (MediaFile) -> Unit, modifier: Modifier) { LazyColumn(modifier.fillMaxSize()) { if (recent.isNotEmpty()) item { Text("Recently opened", Modifier.padding(16.dp), fontWeight = FontWeight.Bold) }; items(recent, key = { "recent-${it.path}" }) { MediaRow(it, onOpen, onToggle) }; item { HorizontalDivider(); Text(title, Modifier.padding(16.dp), fontWeight = FontWeight.Bold) }; if (favorites.isEmpty()) item { Text("No favorites yet.", Modifier.padding(16.dp), color = Color.Gray) }; items(favorites, key = { "favorite-${it.path}" }) { MediaRow(it, onOpen, onToggle) } } }

@Composable private fun SettingsScreen(api: String, onApi: (String) -> Unit, onTest: () -> Unit, loading: Boolean, error: String?, modifier: Modifier) { Column(modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Default.Settings, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(36.dp)); Text("Connection", Modifier.padding(start = 12.dp), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) }; Text("Configure and test your media server", color = Color.Gray); OutlinedTextField(api, onApi, Modifier.fillMaxWidth(), label = { Text("API address") }, singleLine = true); Text("LAN: ${runCatching { URL(api).host }.getOrDefault("Invalid address")}", color = Color.Gray); Button(onClick = onTest, Modifier.fillMaxWidth()) { if (loading) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Icon(Icons.Default.CheckCircle, null); Text("  Test connection") }; if (error != null) Text(error, color = MaterialTheme.colorScheme.error) } }

@Composable private fun MediaList(items: List<MediaFile>, loading: Boolean, error: String?, onOpen: (MediaFile) -> Unit) { when { loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }; error != null -> Text(error, Modifier.padding(24.dp), color = MaterialTheme.colorScheme.error); items.isEmpty() -> Text("No files found.", Modifier.padding(24.dp), color = Color.Gray); else -> LazyColumn { items(items, key = { it.path }) { MediaRow(it, onOpen, null) } } } }

@Composable private fun MediaRow(file: MediaFile, onOpen: (MediaFile) -> Unit, onToggle: ((MediaFile) -> Unit)?) { ListItem(headlineContent = { Text(file.name, maxLines = 2) }, supportingContent = { Text(if (file.isDir) "Folder" else "${file.mime.ifEmpty { "File" }} · ${formatSize(file.size)}") }, leadingContent = { Icon(if (file.isDir) Icons.Default.Folder else Icons.Default.Description, null, tint = if (file.isDir) Color(0xFF008577) else MaterialTheme.colorScheme.primary) }, trailingContent = { if (onToggle != null) IconButton(onClick = { onToggle(file) }) { Icon(Icons.Default.Star, "Favorite", tint = Color(0xFFFFB300)) } else if (!file.isDir) Icon(Icons.Default.PlayArrow, "Play") }, modifier = Modifier.clickable { onOpen(file) }); HorizontalDivider() }

@Composable private fun PlayerScreen(file: MediaFile, api: String, isFavorite: Boolean, onFavorite: () -> Unit, onClose: () -> Unit) { val context = LocalContext.current; val player = remember { ExoPlayer.Builder(context).build() }; DisposableEffect(file.path) { player.setMediaItem(PlayerMediaItem.fromUri("${api.trimEnd('/')}/stream?path=${encode(file.path)}")); player.prepare(); player.playWhenReady = true; onDispose { player.release() } }; Box(Modifier.fillMaxSize()) { AndroidView(factory = { PlayerView(it).apply { this.player = player } }, Modifier.fillMaxSize()); Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.SpaceBetween) { IconButton(onClick = onClose) { Icon(Icons.Default.ArrowBack, "Close", tint = Color.White) }; IconButton(onClick = onFavorite) { Icon(if (isFavorite) Icons.Default.Star else Icons.Default.StarBorder, "Favorite", tint = if (isFavorite) Color.Yellow else Color.White) } } } }

private suspend fun getJson(url: String): String = withContext(Dispatchers.IO) { val connection = URL(url).openConnection() as HttpURLConnection; connection.connectTimeout = 5000; connection.readTimeout = 15000; try { if (connection.responseCode !in 200..299) error("HTTP ${connection.responseCode}"); connection.inputStream.bufferedReader().use { it.readText() } } finally { connection.disconnect() } }
private fun encode(value: String) = URLEncoder.encode(value, "UTF-8")
private fun parseItems(array: JSONArray?): List<MediaFile> = buildList { if (array == null) return@buildList; for (index in 0 until array.length()) { val item = array.getJSONObject(index); add(MediaFile(item.optString("name"), item.optString("path"), item.optBoolean("is_dir"), item.optLong("size"), item.optString("mime"), item.optString("keywords"))) } }
private fun loadStored(preferences: android.content.SharedPreferences, key: String): List<MediaFile> = runCatching { parseItems(JSONArray(preferences.getString(key, "[]"))) }.getOrDefault(emptyList())
private fun saveStored(preferences: android.content.SharedPreferences, key: String, items: List<MediaFile>) { val array = JSONArray(); items.forEach { array.put(JSONObject().apply { put("name", it.name); put("path", it.path); put("is_dir", it.isDir); put("size", it.size); put("mime", it.mime); put("keywords", it.keywords) }) }; preferences.edit().putString(key, array.toString()).apply() }
private fun formatSize(size: Long): String = when { size >= 1_000_000_000 -> "%.1f GB".format(size / 1_000_000_000.0); size >= 1_000_000 -> "%.1f MB".format(size / 1_000_000.0); size >= 1_000 -> "%.1f KB".format(size / 1_000.0); else -> "$size B" }
private fun screenTitle(screen: AppScreen) = when (screen) { AppScreen.TYPES -> "Media Types"; AppScreen.DIRECTORIES -> "Directories"; AppScreen.SEARCH -> "Search"; AppScreen.FAVORITE_FILES -> "Favorite Files"; AppScreen.FAVORITE_FOLDERS -> "Favorite Folders"; AppScreen.SETTINGS -> "Settings" }
