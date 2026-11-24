package com.splayer.next.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.splayer.next.data.JellyfinClient
import com.splayer.next.data.MusicServer
import com.splayer.next.data.Playlist
import com.splayer.next.data.ServerStore
import com.splayer.next.data.ServerType
import com.splayer.next.data.Song
import com.splayer.next.data.SubsonicClient
import com.splayer.next.playback.PlayerController
import com.splayer.next.ui.theme.LocalPalette
import kotlinx.coroutines.launch

/** 流媒体服务器页面栈 */
private sealed interface ServerPage {
    data object ListPage : ServerPage
    data class Edit(val server: MusicServer?) : ServerPage
    data class Browse(val server: MusicServer) : ServerPage
    data class Collection(
        val server: MusicServer,
        val playlist: Playlist,
        val isAlbum: Boolean
    ) : ServerPage
}

/**
 * 流媒体服务器：Subsonic / Navidrome / Jellyfin / Emby。
 * 支持多服务器管理、连接测试、浏览歌曲 / 专辑 / 歌单并在线播放。
 */
@Composable
fun ServersScreen(
    onBack: () -> Unit,
    onPlay: (List<Song>, Int) -> Unit
) {
    val context = LocalContext.current
    val palette = LocalPalette.current
    LaunchedEffect(Unit) { ServerStore.init(context) }
    var page by remember { mutableStateOf<ServerPage>(ServerPage.ListPage) }

    Column(
        Modifier
            .fillMaxSize()
            .background(palette.surface)
            .statusBarsPadding()
            .navigationBarsPadding()
    ) {
        when (val current = page) {
            ServerPage.ListPage -> ServerListPage(
                onBack = onBack,
                onAdd = { page = ServerPage.Edit(null) },
                onEdit = { page = ServerPage.Edit(it) },
                onOpen = { page = ServerPage.Browse(it) }
            )

            is ServerPage.Edit -> ServerEditPage(
                initial = current.server,
                onBack = { page = ServerPage.ListPage },
                onSaved = { page = ServerPage.Browse(it) }
            )

            is ServerPage.Browse -> ServerBrowsePage(
                server = current.server,
                onBack = { page = ServerPage.ListPage },
                onOpenCollection = { playlist, isAlbum ->
                    page = ServerPage.Collection(current.server, playlist, isAlbum)
                },
                onPlay = onPlay
            )

            is ServerPage.Collection -> ServerCollectionPage(
                server = current.server,
                collection = current.playlist,
                isAlbum = current.isAlbum,
                onBack = { page = ServerPage.Browse(current.server) },
                onPlay = onPlay
            )
        }
    }
}

// MARK: - 服务器列表

@Composable
private fun ServerListPage(
    onBack: () -> Unit,
    onAdd: () -> Unit,
    onEdit: (MusicServer) -> Unit,
    onOpen: (MusicServer) -> Unit
) {
    val palette = LocalPalette.current
    val servers = ServerStore.servers
    var pendingDelete by remember { mutableStateOf<MusicServer?>(null) }

    Column(Modifier.fillMaxSize()) {
        ServersHeader(title = "流媒体服务器", onBack = onBack) {
            IconButton(onClick = onAdd) {
                Icon(
                    imageVector = Icons.Filled.Add,
                    contentDescription = "添加服务器",
                    tint = palette.textSecondary,
                    modifier = Modifier.size(22.dp)
                )
            }
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Column {
                    Text(
                        text = "连接你的媒体库",
                        color = palette.textPrimary,
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        text = "支持 Subsonic / Navidrome / Jellyfin / Emby，浏览歌曲、专辑与歌单并在线播放。",
                        color = palette.textSecondary,
                        fontSize = 12.sp,
                        lineHeight = 18.sp
                    )
                }
            }

            if (servers.isEmpty()) {
                item {
                    EmptyHint(
                        text = "还没有添加服务器\n点击右上角 + 添加你的第一台服务器",
                        modifier = Modifier.padding(vertical = 36.dp)
                    )
                }
            } else {
                items(servers, key = { it.id }) { server ->
                    ServerRow(
                        server = server,
                        onOpen = { onOpen(server) },
                        onEdit = { onEdit(server) },
                        onDelete = { pendingDelete = server }
                    )
                }
            }

            item {
                Text(
                    text = "账号与 Token 仅保存在本机。Subsonic 使用用户名 + 密码认证；" +
                        "Jellyfin / Emby 首次浏览时自动登录并缓存 Token。",
                    color = palette.textTertiary,
                    fontSize = 10.sp,
                    lineHeight = 16.sp,
                    modifier = Modifier.padding(top = 8.dp, start = 4.dp, end = 4.dp)
                )
            }
        }
    }

    val deleting = pendingDelete
    if (deleting != null) {
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            containerColor = palette.panel,
            titleContentColor = palette.textPrimary,
            textContentColor = palette.textSecondary,
            title = { Text("删除服务器") },
            text = { Text("确定删除「${deleting.name}」？已下载的歌曲不会被删除。") },
            confirmButton = {
                Text(
                    text = "删除",
                    color = palette.accent,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .clickable {
                            ServerStore.remove(deleting.id)
                            pendingDelete = null
                        }
                        .padding(8.dp)
                )
            },
            dismissButton = {
                Text(
                    text = "取消",
                    color = palette.textSecondary,
                    fontSize = 14.sp,
                    modifier = Modifier
                        .clickable { pendingDelete = null }
                        .padding(8.dp)
                )
            }
        )
    }
}

@Composable
private fun ServerRow(
    server: MusicServer,
    onOpen: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    val palette = LocalPalette.current
    Panel(Modifier.fillMaxWidth().pressable(onOpen), corner = 18.dp) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                Modifier
                    .size(38.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(
                        Brush.linearGradient(
                            listOf(palette.accent, palette.accent.copy(alpha = 0.55f))
                        )
                    ),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Filled.Dns,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(19.dp)
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    text = server.name,
                    color = palette.textPrimary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = "${server.type.label} · ${server.baseUrl}",
                    color = palette.textTertiary,
                    fontSize = 10.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            IconButton(onClick = onEdit, modifier = Modifier.size(34.dp)) {
                Icon(
                    imageVector = Icons.Filled.Edit,
                    contentDescription = "编辑",
                    tint = palette.textSecondary,
                    modifier = Modifier.size(17.dp)
                )
            }
            IconButton(onClick = onDelete, modifier = Modifier.size(34.dp)) {
                Icon(
                    imageVector = Icons.Filled.Delete,
                    contentDescription = "删除",
                    tint = palette.textTertiary,
                    modifier = Modifier.size(17.dp)
                )
            }
        }
    }
}

// MARK: - 添加 / 编辑服务器

@Composable
private fun ServerEditPage(
    initial: MusicServer?,
    onBack: () -> Unit,
    onSaved: (MusicServer) -> Unit
) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()

    var type by remember { mutableStateOf(initial?.type ?: ServerType.SUBSONIC) }
    var name by remember { mutableStateOf(initial?.name ?: "") }
    var baseUrl by remember { mutableStateOf(initial?.baseUrl ?: "") }
    var username by remember { mutableStateOf(initial?.username ?: "") }
    var password by remember { mutableStateOf(initial?.password ?: "") }
    var testing by remember { mutableStateOf(false) }
    var testResult by remember { mutableStateOf<String?>(null) }

    fun buildProbe(): MusicServer = MusicServer(
        id = initial?.id ?: "",
        type = type,
        name = name.trim().ifBlank { defaultServerName(baseUrl) },
        baseUrl = baseUrl.trim().trimEnd('/'),
        username = username.trim(),
        password = password,
        token = "",
        userId = ""
    )

    fun validate(server: MusicServer): String? {
        if (!server.baseUrl.startsWith("http://") && !server.baseUrl.startsWith("https://")) {
            return "服务器地址需要以 http:// 或 https:// 开头"
        }
        if (username.isBlank()) return "请填写用户名"
        if (password.isBlank()) return "请填写密码"
        return null
    }

    Column(Modifier.fillMaxSize()) {
        ServersHeader(
            title = if (initial == null) "添加服务器" else "编辑服务器",
            subtitle = type.label,
            onBack = onBack
        )

        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp)
        ) {
            Text(
                text = "协议类型",
                color = palette.textSecondary,
                fontSize = 11.sp,
                modifier = Modifier.padding(start = 6.dp, bottom = 7.dp)
            )
            Panel(Modifier.fillMaxWidth(), corner = 18.dp) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 12.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    ServerType.entries.forEach { entry ->
                        ChoiceChip(entry.label, type == entry) {
                            type = entry
                            testResult = null
                        }
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            Text(
                text = type.hint,
                color = palette.textTertiary,
                fontSize = 10.sp,
                modifier = Modifier.padding(start = 6.dp)
            )

            Spacer(Modifier.height(16.dp))
            ServerField(
                label = "服务器名称（可选）",
                value = name,
                placeholder = defaultServerName(baseUrl),
                onChange = { name = it }
            )
            Spacer(Modifier.height(14.dp))
            ServerField(
                label = "服务器地址",
                value = baseUrl,
                placeholder = if (type == ServerType.SUBSONIC) {
                    "http://192.168.1.10:4533"
                } else {
                    "http://192.168.1.10:8096"
                },
                keyboardType = KeyboardType.Uri,
                onChange = { baseUrl = it }
            )
            Spacer(Modifier.height(14.dp))
            ServerField(
                label = "用户名",
                value = username,
                placeholder = "登录账号",
                onChange = { username = it }
            )
            Spacer(Modifier.height(14.dp))
            ServerField(
                label = if (type == ServerType.SUBSONIC) "密码" else "密码（用于登录获取 Token）",
                value = password,
                placeholder = "登录密码",
                secret = true,
                keyboardType = KeyboardType.Password,
                onChange = { password = it }
            )

            if (testResult != null) {
                Spacer(Modifier.height(14.dp))
                Text(
                    text = testResult ?: "",
                    color = if (testResult!!.startsWith("连接成功")) palette.accent else palette.textSecondary,
                    fontSize = 12.sp,
                    lineHeight = 18.sp,
                    modifier = Modifier.padding(horizontal = 6.dp)
                )
            }

            Spacer(Modifier.height(20.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Panel(Modifier.weight(1f).pressable {
                    if (testing) return@pressable
                    val probe = buildProbe()
                    validate(probe)?.let {
                        testResult = "请先完善信息：$it"
                        return@pressable
                    }
                    testing = true
                    testResult = null
                    scope.launch {
                        val result = runCatching {
                            when (type) {
                                ServerType.SUBSONIC -> SubsonicClient.ping(probe)
                                else -> JellyfinClient.test(probe)
                            }
                        }
                        testResult = result.fold(
                            { it },
                            { "连接失败：${it.message ?: "网络异常"}" }
                        )
                        testing = false
                    }
                }, corner = 16.dp) {
                    Box(
                        Modifier.fillMaxWidth().padding(vertical = 14.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = if (testing) "测试中…" else "测试连接",
                            color = palette.textPrimary,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
                Box(
                    Modifier
                        .weight(1f)
                        .height(48.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .background(palette.accent)
                        .pressable {
                            val probe = buildProbe()
                            validate(probe)?.let {
                                testResult = "请先完善信息：$it"
                                return@pressable
                            }
                            onSaved(ServerStore.save(probe))
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "保存",
                        color = palette.onAccent,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }

            Spacer(Modifier.height(14.dp))
            Text(
                text = "说明：服务器地址填写协议与端口，不要包含 /rest 或 /web 路径。" +
                    if (type == ServerType.EMBY) " Emby 会自动补全 /emby 前缀。" else "",
                color = palette.textTertiary,
                fontSize = 10.sp,
                lineHeight = 16.sp,
                modifier = Modifier.padding(horizontal = 6.dp)
            )
            Spacer(Modifier.height(28.dp))
        }
    }
}

@Composable
private fun ServerField(
    label: String,
    value: String,
    placeholder: String,
    keyboardType: KeyboardType = KeyboardType.Text,
    secret: Boolean = false,
    onChange: (String) -> Unit
) {
    val palette = LocalPalette.current
    Column {
        Text(
            text = label,
            color = palette.textSecondary,
            fontSize = 11.sp,
            modifier = Modifier.padding(start = 6.dp, bottom = 6.dp)
        )
        Box(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(palette.field)
                .padding(horizontal = 14.dp, vertical = 12.dp)
        ) {
            BasicTextField(
                value = value,
                onValueChange = onChange,
                singleLine = true,
                textStyle = TextStyle(color = palette.textPrimary, fontSize = 14.sp),
                cursorBrush = SolidColor(palette.accent),
                keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
                visualTransformation = if (secret) {
                    PasswordVisualTransformation()
                } else {
                    VisualTransformation.None
                },
                modifier = Modifier.fillMaxWidth(),
                decorationBox = { innerTextField ->
                    Box {
                        if (value.isEmpty()) {
                            Text(
                                text = placeholder,
                                color = palette.textTertiary,
                                fontSize = 14.sp
                            )
                        }
                        innerTextField()
                    }
                }
            )
        }
    }
}

// MARK: - 浏览服务器内容

@Composable
private fun ServerBrowsePage(
    server: MusicServer,
    onBack: () -> Unit,
    onOpenCollection: (Playlist, Boolean) -> Unit,
    onPlay: (List<Song>, Int) -> Unit
) {
    val palette = LocalPalette.current
    var tab by remember { mutableStateOf(0) }
    var refresh by remember { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var songs by remember { mutableStateOf<List<Song>>(emptyList()) }
    var albums by remember { mutableStateOf<List<Playlist>>(emptyList()) }
    var playlists by remember { mutableStateOf<List<Playlist>>(emptyList()) }

    LaunchedEffect(server.id, tab, refresh) {
        loading = true
        error = null
        val result = runCatching {
            when (tab) {
                0 -> songs = loadServerSongs(server)
                1 -> albums = loadServerAlbums(server)
                else -> playlists = loadServerPlaylists(server)
            }
        }
        error = result.exceptionOrNull()?.let { "加载失败：${it.message ?: "网络异常"}" }
        loading = false
    }

    Column(Modifier.fillMaxSize()) {
        ServersHeader(title = server.name, subtitle = server.baseUrl, onBack = onBack) {
            IconButton(onClick = { refresh++ }) {
                Icon(
                    imageVector = Icons.Filled.Refresh,
                    contentDescription = "刷新",
                    tint = palette.textSecondary,
                    modifier = Modifier.size(20.dp)
                )
            }
        }
        Row(
            Modifier.padding(horizontal = 18.dp, vertical = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ChoiceChip("歌曲", tab == 0) { tab = 0 }
            ChoiceChip("专辑", tab == 1) { tab = 1 }
            ChoiceChip("歌单", tab == 2) { tab = 2 }
        }

        Box(Modifier.weight(1f)) {
            when {
                loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = palette.accent, strokeWidth = 2.dp)
                }

                error != null -> Column(
                    Modifier.fillMaxSize().padding(horizontal = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        text = error ?: "",
                        color = palette.textSecondary,
                        fontSize = 12.sp,
                        lineHeight = 18.sp
                    )
                    Spacer(Modifier.height(12.dp))
                    ChoiceChip("重试", true) { refresh++ }
                }

                tab == 0 -> ServerSongsView(songs = songs, onPlay = onPlay)

                tab == 1 -> ServerCollectionsView(
                    items = albums,
                    emptyText = "服务器上没有专辑",
                    onOpen = { onOpenCollection(it, true) }
                )

                else -> ServerCollectionsView(
                    items = playlists,
                    emptyText = "服务器上没有歌单",
                    onOpen = { onOpenCollection(it, false) }
                )
            }
        }
    }
}

@Composable
private fun ServerSongsView(songs: List<Song>, onPlay: (List<Song>, Int) -> Unit) {
    val palette = LocalPalette.current
    if (songs.isEmpty()) {
        EmptyHint("服务器上没有歌曲，点右上角刷新重试", Modifier.padding(top = 60.dp))
        return
    }
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            PlayButton(onClick = { onPlay(songs, 0) }, text = "随机播放")
            Spacer(Modifier.weight(1f))
            Text(text = "共 ${songs.size} 首", color = palette.textTertiary, fontSize = 11.sp)
        }
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp)
        ) {
            itemsIndexed(songs, key = { _, song -> song.id }) { index, song ->
                SongRow(
                    song = song,
                    index = index,
                    active = PlayerController.currentSong?.id == song.id,
                    playing = PlayerController.isPlaying,
                    onClick = { onPlay(songs, index) }
                )
            }
        }
    }
}

@Composable
private fun ServerCollectionsView(
    items: List<Playlist>,
    emptyText: String,
    onOpen: (Playlist) -> Unit
) {
    if (items.isEmpty()) {
        EmptyHint(emptyText, Modifier.padding(top = 60.dp))
        return
    }
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 18.dp, end = 18.dp, top = 12.dp, bottom = 24.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        gridItems(items, key = { it.id }) { item ->
            PlaylistCard(playlist = item, onClick = { onOpen(item) }, width = null)
        }
    }
}

// MARK: - 专辑 / 歌单详情

@Composable
private fun ServerCollectionPage(
    server: MusicServer,
    collection: Playlist,
    isAlbum: Boolean,
    onBack: () -> Unit,
    onPlay: (List<Song>, Int) -> Unit
) {
    val palette = LocalPalette.current
    var songs by remember { mutableStateOf<List<Song>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var refresh by remember { mutableIntStateOf(0) }

    LaunchedEffect(server.id, collection.id, refresh) {
        loading = true
        error = null
        val result = runCatching {
            songs = if (isAlbum) {
                loadServerAlbumSongs(server, collection.id)
            } else {
                loadServerPlaylistSongs(server, collection.id)
            }
        }
        error = result.exceptionOrNull()?.let { "加载失败：${it.message ?: "网络异常"}" }
        loading = false
    }

    Column(Modifier.fillMaxSize()) {
        ServersHeader(
            title = collection.title,
            subtitle = if (isAlbum) "专辑" else "歌单",
            onBack = onBack
        ) {
            IconButton(onClick = { refresh++ }) {
                Icon(
                    imageVector = Icons.Filled.Refresh,
                    contentDescription = "刷新",
                    tint = palette.textSecondary,
                    modifier = Modifier.size(20.dp)
                )
            }
        }

        when {
            loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = palette.accent, strokeWidth = 2.dp)
            }

            error != null -> Column(
                Modifier.fillMaxSize().padding(horizontal = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    text = error ?: "",
                    color = palette.textSecondary,
                    fontSize = 12.sp,
                    lineHeight = 18.sp
                )
                Spacer(Modifier.height(12.dp))
                ChoiceChip("重试", true) { refresh++ }
            }

            else -> LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp)
            ) {
                item {
                    Row(Modifier.padding(vertical = 10.dp)) {
                        CoverBox(
                            url = collection.coverUrl,
                            tint = collection.tint,
                            modifier = Modifier.size(112.dp),
                            corner = 20.dp
                        )
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                text = collection.title,
                                color = palette.textPrimary,
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Bold,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                            Spacer(Modifier.height(4.dp))
                            Text(
                                text = collection.subtitleLabel,
                                color = palette.textTertiary,
                                fontSize = 11.sp,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                            Spacer(Modifier.height(12.dp))
                            PlayButton(
                                onClick = { if (songs.isNotEmpty()) onPlay(songs, 0) },
                                size = 44.dp
                            )
                        }
                    }
                    if (songs.isEmpty()) {
                        EmptyHint(
                            text = if (isAlbum) "专辑里没有歌曲" else "歌单里没有歌曲",
                            modifier = Modifier.padding(top = 40.dp)
                        )
                    }
                }
                itemsIndexed(songs, key = { _, song -> song.id }) { index, song ->
                    SongRow(
                        song = song,
                        index = index,
                        active = PlayerController.currentSong?.id == song.id,
                        playing = PlayerController.isPlaying,
                        showIndex = false,
                        onClick = { onPlay(songs, index) }
                    )
                }
            }
        }
    }
}

// MARK: - 组件与工具

@Composable
private fun ServersHeader(
    title: String,
    subtitle: String? = null,
    onBack: () -> Unit,
    trailing: @Composable (() -> Unit)? = null
) {
    val palette = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(36.dp)
                .clip(CircleShape)
                .clickable { onBack() },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = "返回",
                tint = palette.textPrimary,
                modifier = Modifier.size(20.dp)
            )
        }
        Spacer(Modifier.width(4.dp))
        Column(Modifier.weight(1f)) {
            Text(
                text = title,
                color = palette.textPrimary,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            if (!subtitle.isNullOrBlank()) {
                Text(
                    text = subtitle,
                    color = palette.textTertiary,
                    fontSize = 10.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        if (trailing != null) trailing()
    }
}

private suspend fun loadServerSongs(server: MusicServer): List<Song> = when (server.type) {
    ServerType.SUBSONIC -> SubsonicClient.randomSongs(server)
    else -> JellyfinClient.randomSongs(server)
}

private suspend fun loadServerAlbums(server: MusicServer): List<Playlist> = when (server.type) {
    ServerType.SUBSONIC -> SubsonicClient.albums(server)
    else -> JellyfinClient.albums(server)
}

private suspend fun loadServerPlaylists(server: MusicServer): List<Playlist> = when (server.type) {
    ServerType.SUBSONIC -> SubsonicClient.playlists(server)
    else -> JellyfinClient.playlists(server)
}

private suspend fun loadServerAlbumSongs(server: MusicServer, albumId: String): List<Song> =
    when (server.type) {
        ServerType.SUBSONIC -> SubsonicClient.albumSongs(server, albumId)
        else -> JellyfinClient.albumSongs(server, albumId)
    }

private suspend fun loadServerPlaylistSongs(server: MusicServer, playlistId: String): List<Song> =
    when (server.type) {
        ServerType.SUBSONIC -> SubsonicClient.playlistSongs(server, playlistId)
        else -> JellyfinClient.playlistSongs(server, playlistId)
    }

private fun defaultServerName(url: String): String {
    val host = runCatching { java.net.URL(url.trim()).host }.getOrNull()
    return host?.takeIf { it.isNotBlank() } ?: "我的服务器"
}