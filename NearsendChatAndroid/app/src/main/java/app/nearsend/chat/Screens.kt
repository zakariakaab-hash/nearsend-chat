package app.nearsend.chat

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.ui.platform.LocalClipboardManager
import android.util.Patterns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.annotation.StringRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.window.Dialog
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.ui.draw.alpha
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.foundation.horizontalScroll
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.os.LocaleListCompat
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

private fun timeOf(ms: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(ms))

/** Each language is listed in its own language so people can find it whatever the app is currently showing. */
val LANGUAGES = listOf(
    "en" to "English", "sv" to "Svenska", "es" to "Español", "fr" to "Français", "de" to "Deutsch", "pt" to "Português",
    "it" to "Italiano", "ar" to "العربية", "tr" to "Türkçe", "ru" to "Русский", "zh-CN" to "简体中文", "ja" to "日本語",
)

// ───────────────────────── Nearby + radar ─────────────────────────

@Composable
fun NearbyScreen(store: ChatStore, onOpenChat: (Peer) -> Unit) {
    val p = LocalPalette.current
    val ctx = LocalContext.current
    val live = !store.simulated
    val statusOk = store.meshActive && (store.simulated || store.bluetoothState == "ready")
    val needsSettings = live && store.bluetoothState in listOf("off", "unauthorized")
    @StringRes val statusText = when {
        !store.meshActive -> R.string.st_paused
        store.simulated -> R.string.st_demo
        else -> when (store.bluetoothState) {
            "ready" -> R.string.st_live
            "off" -> R.string.st_off
            "unauthorized" -> R.string.st_denied
            "unsupported" -> R.string.st_unsupported
            else -> R.string.st_starting
        }
    }
    val subtitle: Int? = when {
        live && store.bluetoothState == "unauthorized" -> R.string.sub_denied
        live && store.bluetoothState == "off" -> R.string.sub_off
        live && store.peers.isEmpty() -> R.string.sub_empty
        else -> null
    }
    val switchLabel = stringResource(R.string.mesh_switch)
    var network by remember { mutableStateOf(false) }
    var newPost by remember { mutableStateOf(false) }
    if (newPost) NewPostDialog(store) { newPost = false }
    LazyColumn(Modifier.fillMaxSize().statusBarsPadding(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { PageTitle(R.string.tab_nearby) }
        item {
            Card {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        StatusPill(stringResource(statusText), if (statusOk) p.secure else p.inkSecondary)
                        Text(if (store.peers.size == 1) stringResource(R.string.one_person) else stringResource(R.string.n_people, store.peers.size),
                            color = p.ink, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                        Text(if (subtitle != null) stringResource(subtitle) else stringResource(R.string.n_relay, store.relayedCount), color = p.inkSecondary, fontSize = 13.sp)
                        if (needsSettings) Text(stringResource(R.string.open_settings), color = p.link, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.clickable { if (store.bluetoothState == "off") SystemSettings.openBluetooth(ctx) else SystemSettings.openAppSettings(ctx) })
                    }
                    Switch(store.meshActive, { store.setMesh(it) }, Modifier.semantics { contentDescription = switchLabel },
                        colors = SwitchDefaults.colors(checkedTrackColor = ActionBlue, checkedThumbColor = Color.White))
                }
            }
        }
        item {
            Card(padding = 12.dp) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    Chip(stringResource(R.string.net_view), network) { network = !network }
                }
                Radar(store.peers, Modifier.fillMaxWidth().height(320.dp), network)
            }
        }
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.posts_title), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f).semantics { heading() })
                Text("+ " + stringResource(R.string.post_new), color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clickable { newPost = true }.padding(8.dp))
            }
        }
        if (store.posts.isEmpty()) item { Card { Text(stringResource(R.string.posts_empty), color = p.inkSecondary, fontSize = 14.sp) } }
        items(store.posts, key = { "post-" + it.id }) { PostCard(it) }
        items(store.peers, key = { it.id }) { peer ->
            Card(Modifier.clickable { onOpenChat(peer) }, padding = 12.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Avatar(peer.name, online = true)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(peer.name, color = p.ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                            if (peer.verified) Icon(Icons.Filled.Verified, stringResource(R.string.verified), tint = ActionBlue, modifier = Modifier.size(15.dp))
                        }
                        Text(if (peer.hops == 1) stringResource(R.string.direct_dbm, peer.rssi) else stringResource(R.string.n_hops_relay, peer.hops),
                            color = p.inkSecondary, fontSize = 13.sp)
                    }
                    SignalBars(peer.rssi)
                }
            }
        }
    }
}

private fun radiusFor(p: Peer) = ((-40 - p.rssi) / 55f).coerceIn(0.18f, 1f)
/** Golden-angle spread from the id so people don't bunch together and stay put between updates. */
private fun angleFor(p: Peer): Float {
    var h = 0
    for (c in p.id) h = (h * 31 + c.code) and 0xFFFFFF
    return ((h * 137.508) % 360.0).toFloat() * Math.PI.toFloat() / 180f
}

@Composable
fun Radar(peers: List<Peer>, modifier: Modifier = Modifier, network: Boolean = false) {
    val p = LocalPalette.current
    val rot by rememberInfiniteTransition(label = "sweep").animateFloat(
        0f, 360f, infiniteRepeatable(tween(4000, easing = LinearEasing)), label = "r",
    )
    val tail = 0.16f   // fraction of a turn the fading tail covers
    val desc = stringResource(R.string.radar) + ": " + if (peers.size == 1) stringResource(R.string.one_person) else stringResource(R.string.n_people, peers.size)
    BoxWithConstraints(modifier.semantics { contentDescription = desc }, contentAlignment = Alignment.Center) {
        val box = minOf(maxWidth, maxHeight)
        Canvas(Modifier.size(box)) {
            val c = center
            val r = size.minDimension / 2
            for (i in 1..4) drawCircle(p.ink.copy(alpha = 0.10f), r * i / 4, c, style = Stroke(1.dp.toPx()))
            drawLine(p.ink.copy(alpha = 0.08f), Offset(c.x, 0f), Offset(c.x, size.height))
            drawLine(p.ink.copy(alpha = 0.08f), Offset(0f, c.y), Offset(size.width, c.y))
            // Thin sweep: a short fading tail that ends in a bright leading edge, then rotates.
            rotate(rot, c) {
                drawCircle(
                    Brush.sweepGradient(
                        colorStops = arrayOf(
                            0f to ActionBlue.copy(alpha = 0f), (1 - tail) to ActionBlue.copy(alpha = 0f),
                            0.999f to ActionBlue.copy(alpha = 0.45f), 1f to ActionBlue.copy(alpha = 0f)),
                        center = c),
                    r, c)
                drawLine(ActionBlue, c, Offset(c.x + r, c.y), strokeWidth = 2.dp.toPx())
            }
            if (network) {
                // Lines show how each person is reached: straight from us, or through the person who passed them on.
                val box2 = box.toPx() / 2
                fun spot(peer: Peer): Offset {
                    val a = angleFor(peer); val rr = radiusFor(peer) * box2
                    return Offset(c.x + cos(a) * rr, c.y + sin(a) * rr - 7.dp.toPx())   // dot sits ~7 dp above the label column's centre
                }
                val dash = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 5.dp.toPx()))
                peers.forEach { peer ->
                    val from = if (peer.hops == 1) null else peers.firstOrNull { it.id == peer.via }
                    drawLine(ActionBlue.copy(alpha = if (peer.hops == 1) 0.7f else 0.5f), from?.let(::spot) ?: c, spot(peer),
                        strokeWidth = 2.dp.toPx(), pathEffect = if (peer.hops == 1) null else dash)
                }
            }
            drawCircle(ActionBlue.copy(alpha = 0.25f), 12.dp.toPx(), c)
            drawCircle(Color.White, 8.dp.toPx(), c)
            drawCircle(ActionBlue, 6.dp.toPx(), c)
        }
        peers.forEach { peer ->
            val rr = radiusFor(peer) * (box.value / 2)
            val a = angleFor(peer)
            Column(Modifier.offset(x = (cos(a) * rr).dp, y = (sin(a) * rr).dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.size(13.dp).background(if (peer.hops == 1) ActionBlue else Color.White, CircleShape).border(2.dp, ActionBlue, CircleShape))
                Text(peer.name, color = p.ink, fontSize = 11.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}

@Composable
private fun Chip(label: String, on: Boolean, onClick: () -> Unit) {
    val p = LocalPalette.current
    Text(label, color = if (on) Color.White else p.link, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.clip(CircleShape).background(if (on) ActionBlue else p.ink.copy(alpha = 0.06f))
            .clickable(onClick = onClick).semantics { selected = on }.padding(horizontal = 12.dp, vertical = 6.dp))
}

@Composable
private fun PostCard(post: Post) {
    val p = LocalPalette.current
    val left = post.expMs - System.currentTimeMillis()
    Card(padding = 14.dp) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Filled.Campaign, null, tint = ActionBlue, modifier = Modifier.size(22.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(if (post.mine) post.name + " (" + stringResource(R.string.lbl_you) + ")" else post.name, color = p.ink, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                Text(post.text, color = p.ink, fontSize = 15.sp)
                Text(buildString {
                    append(if (left >= 3_600_000) stringResource(R.string.post_left_h, (left / 3_600_000).toInt())
                        else stringResource(R.string.post_left_min, maxOf(1, (left / 60_000).toInt())))
                    if (post.hops > 1) append(" · ").append(stringResource(R.string.n_hops, post.hops))
                }, color = p.inkSecondary, fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun NewPostDialog(store: ChatStore, onClose: () -> Unit) {
    val p = LocalPalette.current
    var text by remember { mutableStateOf("") }
    var hours by remember { mutableIntStateOf(6) }
    Dialog(onDismissRequest = onClose) {
        Column(Modifier.widthIn(max = 420.dp).fillMaxWidth().glass(24.dp, solid = true).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.posts_title), color = p.ink, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                Text(stringResource(R.string.cancel), color = p.link, fontSize = 15.sp, modifier = Modifier.clickable(onClick = onClose).padding(8.dp))
            }
            Box(Modifier.fillMaxWidth().glass(12.dp).padding(horizontal = 16.dp, vertical = 12.dp)) {
                if (text.isEmpty()) Text(stringResource(R.string.post_hint), color = p.inkSecondary, fontSize = 16.sp)
                BasicTextField(text, { text = it.take(500) }, Modifier.fillMaxWidth().heightIn(min = 72.dp), textStyle = TextStyle(color = p.ink, fontSize = 16.sp), cursorBrush = SolidColor(ActionBlue))
            }
            Text(stringResource(R.string.post_for), color = p.inkSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(1, 6, 24).forEach { h -> Chip(stringResource(R.string.post_hours, h), hours == h) { hours = h } }
            }
            Text(stringResource(R.string.post_public), color = p.inkSecondary, fontSize = 12.sp)
            val ok = text.isNotBlank()
            Box(Modifier.alpha(if (ok) 1f else 0.4f)) {
                PrimaryButton(stringResource(R.string.post_send)) { if (ok) { store.post(text, hours); onClose() } }
            }
        }
    }
}

// ───────────────────────── Chats ─────────────────────────

@Composable
fun ChatsScreen(store: ChatStore, startAdd: Boolean = false, onOpen: (String) -> Unit, onOpenPeer: (Peer) -> Unit) {
    val p = LocalPalette.current
    var adding by remember { mutableStateOf(startAdd) }
    var writing by remember { mutableStateOf(false) }
    var grouping by remember { mutableStateOf(false) }
    val sorted = store.conversations.sortedWith(compareBy<Conversation> { it.id != PUBLIC_CHANNEL_ID }
        .thenByDescending { it.messages.lastOrNull()?.timeMs ?: 0L })
    LazyColumn(Modifier.fillMaxSize().statusBarsPadding(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PageTitle(R.string.tab_chats, Modifier.weight(1f))
                RoundIconButton(Icons.Filled.QrCode, stringResource(R.string.add_verify)) { adding = true }
                RoundIconButton(Icons.Filled.Edit, stringResource(R.string.write_to)) { writing = true }
            }
        }
        if (store.conversations.size <= 1) item {
            Card {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.Forum, null, tint = ActionBlue, modifier = Modifier.size(30.dp))
                    Text(stringResource(R.string.no_chats), color = p.ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    Text(stringResource(R.string.no_chats_hint), color = p.inkSecondary, fontSize = 13.sp, textAlign = TextAlign.Center)
                    PrimaryButton(stringResource(R.string.add_verify)) { adding = true }
                }
            }
        }
        items(sorted, key = { it.id }) { c ->
            val isPublic = c.id == PUBLIC_CHANNEL_ID
            Card(Modifier.clickable { onOpen(c.id) }, padding = 12.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Avatar(if (isPublic) "#" else c.peer.name, 52.dp, online = !isPublic && !c.isGroup && c.peer.hops == 1)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row {
                            Text(if (isPublic) stringResource(R.string.nearby_channel) else c.peer.name, color = p.ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                            c.messages.lastOrNull()?.let { Text(timeOf(it.timeMs), color = p.inkSecondary, fontSize = 12.sp) }
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            val last = c.messages.lastOrNull()
                            Text(when {
                                last == null -> if (isPublic) stringResource(R.string.public_hint) else ""
                                last.sender != null -> "${last.sender}: ${last.text}"
                                else -> last.text
                            }, color = p.inkSecondary, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                            if (c.unread > 0) Text("${c.unread}", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                                modifier = Modifier.background(ActionBlue, CircleShape).padding(horizontal = 8.dp, vertical = 3.dp))
                        }
                    }
                }
            }
        }
    }
    if (adding) AddOrVerifyDialog(store) { adding = false }
    if (writing) WriteToDialog(store, onPick = { writing = false; onOpenPeer(it) }, onNewGroup = { writing = false; grouping = true }) { writing = false }
    if (grouping) NewGroupDialog(store, onCreated = { grouping = false; onOpen(it) }) { grouping = false }
}

@Composable
private fun RoundIconButton(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(44.dp).glass(22.dp).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = LocalPalette.current.link, modifier = Modifier.size(22.dp))
    }
}

// ───────────────────────── Thread ─────────────────────────

@Composable
fun ThreadScreen(store: ChatStore, conversationId: String, peer: Peer, startInfo: Boolean, onBack: () -> Unit) {
    val p = LocalPalette.current
    val isPublic = conversationId == PUBLIC_CHANNEL_ID
    val conv = store.conversations.firstOrNull { it.id == conversationId }
    val messages = conv?.messages ?: emptyList()
    val members = conv?.members
    val livePeer = store.peers.firstOrNull { it.id == conversationId } ?: peer
    val online = isPublic || store.peers.any { it.id == conversationId }
    val encrypted = store.simulated || livePeer.fingerprint.isNotEmpty()
    var draft by remember { mutableStateOf("") }
    var showInfo by remember { mutableStateOf(startInfo) }
    val listState = rememberLazyListState()
    DisposableEffect(conversationId) {
        store.activeConversation = conversationId
        store.ensureConversation(peer); store.markRead(conversationId)
        onDispose { if (store.activeConversation == conversationId) store.activeConversation = null }
    }
    LaunchedEffect(messages.size) {
        store.markRead(conversationId)
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size)
    }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().statusBarsPadding().imePadding()) {
            Row(Modifier.fillMaxWidth().glass(0.dp).padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back), tint = p.link, modifier = Modifier.clickable(onClick = onBack).padding(8.dp))
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(if (isPublic) stringResource(R.string.nearby_channel) else livePeer.name, color = p.ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    Text(when {
                        isPublic -> stringResource(R.string.public_channel)
                        members != null -> stringResource(R.string.group_members, members.size)
                        !online && store.canCarryTo(conversationId) -> stringResource(R.string.carry_hint)
                        !online -> stringResource(R.string.out_of_range)
                        livePeer.hops == 1 -> stringResource(R.string.direct_link)
                        else -> stringResource(R.string.n_hops, livePeer.hops)
                    }, color = if (online || members != null) p.secure else p.inkSecondary, fontSize = 11.sp, textAlign = TextAlign.Center)
                }
                if (isPublic) Spacer(Modifier.width(40.dp))
                else Icon(Icons.Filled.Info, stringResource(R.string.contact_info), tint = p.link, modifier = Modifier.clickable { showInfo = true }.padding(8.dp))
            }
            LazyColumn(Modifier.weight(1f), state = listState, contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                item {
                    Box(Modifier.fillMaxWidth().padding(vertical = 10.dp), contentAlignment = Alignment.Center) {
                        SkyPill { Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(if (isPublic) Icons.Filled.Campaign else Icons.Filled.Lock, null, tint = Color.White, modifier = Modifier.size(13.dp))
                            Text(stringResource(if (isPublic) R.string.public_hint else if (members != null) R.string.group_e2e else if (encrypted) R.string.e2e else R.string.waiting_keys), color = Color.White, fontSize = 12.sp)
                        } }
                    }
                }
                items(messages, key = { it.id }) { m -> Bubble(m, isPublic || members != null) { store.retry(m.id, conversationId) } }
            }
            Row(Modifier.fillMaxWidth().glass(0.dp).navigationBarsPadding().padding(12.dp, 8.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.weight(1f).glass(16.dp).padding(horizontal = 16.dp, vertical = 12.dp)) {
                    if (draft.isEmpty()) Text(stringResource(R.string.message), color = p.inkSecondary, fontSize = 16.sp)
                    BasicTextField(draft, { draft = it }, Modifier.fillMaxWidth(), textStyle = TextStyle(color = p.ink, fontSize = 16.sp), cursorBrush = SolidColor(ActionBlue), maxLines = 5)
                }
                val canSend = draft.isNotBlank()
                Box(Modifier.size(46.dp).background(if (canSend) ActionBlue else ActionBlue.copy(alpha = 0.4f), RoundedCornerShape(12.dp))
                    .clickable(enabled = canSend) { store.send(draft.trim(), conversationId); draft = "" }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.ArrowUpward, stringResource(R.string.send), tint = Color.White)
                }
            }
        }
        if (showInfo && members != null) GroupInfo(livePeer.name, members, store, onClose = { showInfo = false }, onLeave = { store.leaveGroup(conversationId); onBack() })
        else if (showInfo) PeerInfo(livePeer, store, onClose = { showInfo = false }, onRemoved = { showInfo = false; onBack() })
    }
}

@Composable
private fun Bubble(m: Message, showSender: Boolean, onRetry: () -> Unit) {
    val p = LocalPalette.current
    val stateName = stringResource(when (m.state) {
        Delivery.Sending -> R.string.state_sending; Delivery.Sent -> R.string.state_sent; Delivery.Relayed -> R.string.state_relayed
        Delivery.Delivered -> R.string.state_delivered; Delivery.Failed -> R.string.state_failed
    })
    Row(Modifier.fillMaxWidth().clickable(enabled = m.state == Delivery.Failed, onClick = onRetry), horizontalArrangement = if (m.mine) Arrangement.End else Arrangement.Start) {
        Column(horizontalAlignment = if (m.mine) Alignment.End else Alignment.Start, modifier = Modifier.widthIn(max = 300.dp)) {
            if (showSender && !m.mine && m.sender != null)
                Text(m.sender, color = Color.White.copy(alpha = 0.9f), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 6.dp))
            Text(linkify(m.text, if (m.mine) Color.White else p.link), color = if (m.mine) Color.White else p.ink, fontSize = 16.sp,
                modifier = (if (m.mine) Modifier.background(ActionBlue, RoundedCornerShape(20.dp)) else Modifier.glass(20.dp)).padding(horizontal = 14.dp, vertical = 10.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.padding(top = 3.dp)) {
                Text(timeOf(m.timeMs), color = Color.White.copy(alpha = 0.85f), fontSize = 11.sp)
                if (!m.mine && m.hops > 1) Text(stringResource(R.string.dot_n_hops, m.hops), color = Color.White.copy(alpha = 0.85f), fontSize = 11.sp)
                if (m.mine) Icon(when (m.state) {
                    Delivery.Sending -> Icons.Filled.Schedule
                    Delivery.Sent -> Icons.Filled.Check
                    Delivery.Relayed -> Icons.Filled.CallSplit
                    Delivery.Delivered -> Icons.Filled.CheckCircle
                    Delivery.Failed -> Icons.Filled.Warning
                }, stateName, tint = Color.White.copy(alpha = 0.85f), modifier = Modifier.size(12.dp))
                if (m.state == Delivery.Failed) Text(stringResource(R.string.tap_retry), color = Color.White.copy(alpha = 0.85f), fontSize = 11.sp)
            }
        }
    }
}

/** Contact info: nickname, QR or fingerprint verification, block and remove. */
@Composable
private fun PeerInfo(peer: Peer, store: ChatStore, onClose: () -> Unit, onRemoved: () -> Unit) {
    val p = LocalPalette.current
    var nick by remember { mutableStateOf(store.nicknames[peer.fingerprint] ?: "") }
    var confirmRemove by remember { mutableStateOf(false) }
    val isBlocked = peer.id in store.blocked
    val close = { if (nick != (store.nicknames[peer.fingerprint] ?: "")) store.setNickname(peer, nick); onClose() }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)).clickable(onClick = close), contentAlignment = Alignment.BottomCenter) {
        Column(Modifier.fillMaxWidth().glass(24.dp).clickable(enabled = false) {}.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Avatar(peer.name, 72.dp)
            Text(peer.name, color = p.ink, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
            if (isBlocked) StatusPill(stringResource(R.string.blocked_hint), Color(0xFFD93025))
            if (peer.fingerprint.isNotEmpty()) Box(Modifier.fillMaxWidth().glass(12.dp).padding(horizontal = 16.dp, vertical = 12.dp)) {
                if (nick.isEmpty()) Text(stringResource(R.string.nickname), color = p.inkSecondary, fontSize = 16.sp)
                BasicTextField(nick, { nick = it }, Modifier.fillMaxWidth(), singleLine = true, textStyle = TextStyle(color = p.ink, fontSize = 16.sp),
                    cursorBrush = SolidColor(ActionBlue), keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { store.setNickname(peer, nick) }))
            }
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Filled.Key, null, tint = p.ink, modifier = Modifier.size(16.dp))
                    Text(stringResource(R.string.their_fp), color = p.ink, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                }
                Text(peer.fingerprint.ifEmpty { "—" }, color = p.link, fontFamily = FontFamily.Monospace, fontSize = 18.sp)
                Text(stringResource(R.string.their_fp_hint), color = p.inkSecondary, fontSize = 13.sp)
            }
            ScanQrButton(store, onDone = close)
            GlassButton(stringResource(if (peer.verified) R.string.remove_verif else R.string.mark_verif), p.link) { store.toggleVerified(peer); close() }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                GlassButton(stringResource(if (isBlocked) R.string.unblock else R.string.block), p.link, Modifier.weight(1f)) { store.toggleBlocked(peer.id) }
                GlassButton(stringResource(R.string.remove_contact), Color(0xFFD93025), Modifier.weight(1f)) { confirmRemove = true }
            }
            Text(stringResource(R.string.close), color = p.link, fontSize = 15.sp, modifier = Modifier.clickable(onClick = close).padding(8.dp))
        }
    }
    if (confirmRemove) AlertDialog(
        onDismissRequest = { confirmRemove = false },
        title = { Text(stringResource(R.string.remove_confirm)) },
        text = { Text(stringResource(R.string.remove_confirm_body)) },
        confirmButton = { TextButton({ confirmRemove = false; store.removeContact(peer); onRemoved() }) { Text(stringResource(R.string.remove), color = Color(0xFFD93025)) } },
        dismissButton = { TextButton({ confirmRemove = false }) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun GlassButton(title: String, color: Color, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(modifier.fillMaxWidth().glass(12.dp).clickable(onClick = onClick).padding(vertical = 14.dp), contentAlignment = Alignment.Center) {
        Text(title, color = color, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
    }
}

/** Opens the camera scanner; shows whether the scanned person is now verified. */
@Composable
fun ScanQrButton(store: ChatStore, secondary: Boolean = false, onDone: () -> Unit = {}) {
    var result by remember { mutableStateOf<Pair<ChatStore.ScanResult, String>?>(null) }
    val launcher = rememberLauncherForActivityResult(ScanContract()) { r -> if (r.contents != null) result = store.applyScan(r.contents) }
    val title = stringResource(R.string.scan_qr)
    val scan = { launcher.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setPrompt(title).setBeepEnabled(false).setOrientationLocked(false)) }
    if (secondary) GlassButton(title, LocalPalette.current.link) { scan() } else PrimaryButton(title) { scan() }
    result?.let { (kind, name) -> ScanResultDialog(kind, name) { result = null; onDone() } }
}

/** Outcome of scanning a QR code or pasting a contact code. */
@Composable
private fun ScanResultDialog(kind: ChatStore.ScanResult, name: String, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(when (kind) {
            ChatStore.ScanResult.Verified -> R.string.verified
            ChatStore.ScanResult.Mismatch -> R.string.qr_mismatch
            ChatStore.ScanResult.Invalid -> R.string.qr_invalid
            ChatStore.ScanResult.Added -> R.string.contact_added
        })) },
        text = if (kind == ChatStore.ScanResult.Invalid) null else {
            { Text(name + "\n\n" + stringResource(when (kind) {
                ChatStore.ScanResult.Verified -> R.string.qr_verified_body
                ChatStore.ScanResult.Added -> R.string.contact_added_body
                else -> R.string.qr_mismatch_body
            })) }
        },
        confirmButton = { TextButton(onDismiss) { Text(stringResource(R.string.close)) } },
    )
}

/** One place to connect with someone: our QR (id, name, key, one-time code), scan theirs, or swap codes as text (unverified). */
@Composable
fun AddOrVerifyDialog(store: ChatStore, onClose: () -> Unit) {
    val p = LocalPalette.current
    val ctx = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val qr = remember { qrBitmap(store.myQr()) }
    var pasted by remember { mutableStateOf<Pair<ChatStore.ScanResult, String>?>(null) }
    val shareTitle = stringResource(R.string.share_text)
    val shareMessage = stringResource(R.string.share_message)
    LaunchedEffect(Unit) { store.lastVerified = null }
    Dialog(onDismissRequest = onClose) {
        Column(Modifier.widthIn(max = 420.dp).fillMaxWidth().glass(24.dp, solid = true).verticalScroll(rememberScrollState()).padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(stringResource(R.string.add_verify), color = p.ink, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
            Text(stringResource(R.string.add_verify_hint), color = p.inkSecondary, fontSize = 13.sp, textAlign = TextAlign.Center)
            Image(qr, stringResource(R.string.my_qr), Modifier.fillMaxWidth().aspectRatio(1f).background(Color.White, RoundedCornerShape(16.dp)).padding(14.dp),
                filterQuality = FilterQuality.None)
            Text(store.nickname, color = p.ink, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            Text(store.myFingerprint, color = p.inkSecondary, fontFamily = FontFamily.Monospace, fontSize = 12.sp, textAlign = TextAlign.Center)
            store.lastVerified?.let { StatusPill("✓ " + stringResource(R.string.verified) + " · " + it) }
            ScanQrButton(store)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                GlassButton(shareTitle, p.link, Modifier.weight(1f)) {
                    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, shareMessage + "\n\n" + store.myTextCode())
                    ctx.startActivity(Intent.createChooser(send, shareTitle))
                }
                GlassButton(stringResource(R.string.paste_code), p.link, Modifier.weight(1f)) { pasted = store.applyText(clipboard.getText()?.text) }
            }
            Text(stringResource(R.string.text_code_note), color = p.inkSecondary, fontSize = 12.sp, textAlign = TextAlign.Center)
            Text(stringResource(R.string.close), color = p.link, fontSize = 15.sp, modifier = Modifier.clickable(onClick = onClose).padding(8.dp))
        }
    }
    pasted?.let { (kind, name) -> ScanResultDialog(kind, name) { pasted = null } }
}

/** Pick who to write to: people in range first, then saved contacts (their messages wait until they're in range). */
@Composable
fun WriteToDialog(store: ChatStore, onPick: (Peer) -> Unit, onNewGroup: () -> Unit, onClose: () -> Unit) {
    val p = LocalPalette.current
    val inRange = store.peers.filter { it.id !in store.blocked }
    val saved = store.conversations.filter { !it.isGroup }.map { it.peer }.filter { c -> c.id != PUBLIC_CHANNEL_ID && inRange.none { it.id == c.id } }
    var adding by remember { mutableStateOf(false) }
    Dialog(onDismissRequest = onClose) {
        Column(Modifier.widthIn(max = 420.dp).fillMaxWidth().glass(24.dp, solid = true).verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.write_to), color = p.ink, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                Text(stringResource(R.string.close), color = p.link, fontSize = 15.sp, modifier = Modifier.clickable(onClick = onClose).padding(8.dp))
            }
            Row(Modifier.fillMaxWidth().clickable(onClick = onNewGroup).padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.size(40.dp).background(ActionBlue, CircleShape), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.Groups, null, tint = Color.White, modifier = Modifier.size(22.dp))
                }
                Text(stringResource(R.string.new_group), color = p.link, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            }
            if (inRange.isEmpty() && saved.isEmpty()) {
                Text(stringResource(R.string.write_to_empty), color = p.inkSecondary, fontSize = 14.sp)
                PrimaryButton(stringResource(R.string.add_verify)) { adding = true }
            }
            listOf(R.string.in_range to inRange, R.string.contacts to saved).forEach { (label, people) ->
                if (people.isNotEmpty()) Text(stringResource(label), color = p.inkSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                people.forEach { peer ->
                    Row(Modifier.fillMaxWidth().clickable { onPick(peer) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Avatar(peer.name, 40.dp, online = label == R.string.in_range && peer.hops == 1)
                        Text(peer.name, color = p.ink, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        if (peer.verified) Icon(Icons.Filled.Verified, stringResource(R.string.verified), tint = ActionBlue, modifier = Modifier.size(16.dp))
                    }
                }
            }
        }
    }
    if (adding) AddOrVerifyDialog(store) { adding = false }
}

/** Name a group and tick who is in it: people in range and saved contacts. */
@Composable
private fun NewGroupDialog(store: ChatStore, onCreated: (String) -> Unit, onClose: () -> Unit) {
    val p = LocalPalette.current
    val inRange = store.peers.filter { it.id !in store.blocked }
    val people = inRange + store.conversations.filter { !it.isGroup && it.id != PUBLIC_CHANNEL_ID && it.id !in store.blocked }
        .map { it.peer }.filter { c -> inRange.none { it.id == c.id } }
    var name by remember { mutableStateOf("") }
    var picked by remember { mutableStateOf(setOf<String>()) }
    Dialog(onDismissRequest = onClose) {
        Column(Modifier.widthIn(max = 420.dp).fillMaxWidth().glass(24.dp, solid = true).verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.new_group), color = p.ink, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                Text(stringResource(R.string.cancel), color = p.link, fontSize = 15.sp, modifier = Modifier.clickable(onClick = onClose).padding(8.dp))
            }
            Box(Modifier.fillMaxWidth().glass(12.dp).padding(horizontal = 16.dp, vertical = 12.dp)) {
                if (name.isEmpty()) Text(stringResource(R.string.group_name), color = p.inkSecondary, fontSize = 16.sp)
                BasicTextField(name, { name = it.take(40) }, Modifier.fillMaxWidth(), singleLine = true, textStyle = TextStyle(color = p.ink, fontSize = 16.sp),
                    cursorBrush = SolidColor(ActionBlue))
            }
            Text(stringResource(R.string.group_pick), color = p.inkSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            if (people.isEmpty()) Text(stringResource(R.string.group_none), color = p.inkSecondary, fontSize = 14.sp)
            people.forEach { peer ->
                val on = peer.id in picked
                Row(Modifier.fillMaxWidth().clickable { picked = if (on) picked - peer.id else picked + peer.id }.padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Avatar(peer.name, 40.dp, online = inRange.any { it.id == peer.id } && peer.hops == 1)
                    Text(peer.name, color = p.ink, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    Checkbox(on, { picked = if (on) picked - peer.id else picked + peer.id }, colors = CheckboxDefaults.colors(checkedColor = ActionBlue))
                }
            }
            val ok = name.isNotBlank() && picked.isNotEmpty()
            Box(Modifier.alpha(if (ok) 1f else 0.4f)) {
                PrimaryButton(stringResource(R.string.group_create)) { if (ok) onCreated(store.createGroup(name, people.filter { it.id in picked })) }
            }
        }
    }
}

/** Group members and leaving. Leaving only affects this phone. */
@Composable
private fun GroupInfo(name: String, members: List<Pair<String, String>>, store: ChatStore, onClose: () -> Unit, onLeave: () -> Unit) {
    val p = LocalPalette.current
    var confirm by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)).clickable(onClick = onClose), contentAlignment = Alignment.BottomCenter) {
        Column(Modifier.fillMaxWidth().glass(24.dp).clickable(enabled = false) {}.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Avatar(name, 72.dp)
            Text(name, color = p.ink, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
            Text(stringResource(R.string.group_members, members.size), color = p.inkSecondary, fontSize = 13.sp)
            members.forEach { (id, n) ->
                val me = id == store.deviceId
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Avatar(if (me) store.nickname else n, 36.dp, online = !me && store.peers.any { it.id == id && it.hops == 1 })
                    Text(if (me) store.nickname + " (" + stringResource(R.string.lbl_you) + ")" else store.peers.firstOrNull { it.id == id }?.name ?: n,
                        color = p.ink, fontSize = 15.sp, modifier = Modifier.weight(1f))
                }
            }
            GlassButton(stringResource(R.string.group_leave), Color(0xFFD93025)) { confirm = true }
            Text(stringResource(R.string.close), color = p.link, fontSize = 15.sp, modifier = Modifier.clickable(onClick = onClose).padding(8.dp))
        }
    }
    if (confirm) AlertDialog(
        onDismissRequest = { confirm = false },
        title = { Text(stringResource(R.string.group_leave)) },
        text = { Text(stringResource(R.string.group_leave_body)) },
        confirmButton = { TextButton({ confirm = false; onLeave() }) { Text(stringResource(R.string.group_leave), color = Color(0xFFD93025)) } },
        dismissButton = { TextButton({ confirm = false }) { Text(stringResource(R.string.cancel)) } },
    )
}

private fun qrBitmap(text: String, size: Int = 600): ImageBitmap {
    val m = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, mapOf(EncodeHintType.MARGIN to 0))
    val px = IntArray(size * size) { if (m[it % size, it / size]) 0xFF1B2A4A.toInt() else 0xFFFFFFFF.toInt() }
    return Bitmap.createBitmap(px, size, size, Bitmap.Config.ARGB_8888).asImageBitmap()
}

/** Web addresses in a message become tappable links. */
private fun linkify(text: String, color: Color): AnnotatedString = buildAnnotatedString {
    append(text)
    val m = Patterns.WEB_URL.matcher(text)
    while (m.find()) {
        val url = m.group().let { if (it.contains("://")) it else "https://$it" }
        addLink(LinkAnnotation.Url(url, TextLinkStyles(SpanStyle(color = color, textDecoration = TextDecoration.Underline))), m.start(), m.end())
    }
}

// ───────────────────────── You ─────────────────────────

@Composable
fun IdentityScreen(store: ChatStore, startQr: Boolean = false) {
    val p = LocalPalette.current
    var showQr by remember { mutableStateOf(startQr) }
    var confirmWipe by remember { mutableStateOf(false) }
    var langMenu by remember { mutableStateOf(false) }
    var taps by remember { mutableIntStateOf(0) }
    var lastTap by remember { mutableLongStateOf(0L) }
    val current = AppCompatDelegate.getApplicationLocales().toLanguageTags()
    val currentName = LANGUAGES.firstOrNull { current.isNotEmpty() && current.startsWith(it.first.substringBefore('-')) }?.second
    LazyColumn(Modifier.fillMaxSize().statusBarsPadding(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            PageTitle(R.string.tab_you, Modifier.clickable {   // panic: triple-tap
                val now = System.currentTimeMillis()
                taps = if (now - lastTap < 700) taps + 1 else 1
                lastTap = now
                if (taps >= 3) { taps = 0; confirmWipe = true }
            })
        }
        item {
            Card {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Avatar(store.nickname, 88.dp)
                    BasicTextField(store.nickname, { store.updateNickname(it) }, singleLine = true,
                        textStyle = TextStyle(color = p.ink, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center),
                        cursorBrush = SolidColor(ActionBlue), keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { store.applyNickname() }), modifier = Modifier.fillMaxWidth())
                    StatusPill(stringResource(R.string.no_account))
                }
            }
        }
        item {
            Card {
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Filled.Key, null, tint = p.ink, modifier = Modifier.size(16.dp))
                        Text(stringResource(R.string.your_fp), color = p.ink, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    }
                    Text(store.myFingerprint.ifEmpty { "—" }, color = p.link, fontFamily = FontFamily.Monospace, fontSize = 15.sp)
                    Text(stringResource(R.string.your_fp_hint), color = p.inkSecondary, fontSize = 13.sp)
                    PrimaryButton(stringResource(R.string.add_verify)) { showQr = true }
                    ScanQrButton(store, secondary = true)
                }
            }
        }
        item {
            Card {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Language, null, tint = p.ink, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.language), color = p.ink, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    Box {
                        Text(currentName ?: stringResource(R.string.language_system), color = p.link, fontSize = 15.sp, modifier = Modifier.clickable { langMenu = true }.padding(8.dp))
                        DropdownMenu(langMenu, { langMenu = false }) {
                            DropdownMenuItem({ Text(stringResource(R.string.language_system)) }, { langMenu = false; AppCompatDelegate.setApplicationLocales(LocaleListCompat.getEmptyLocaleList()) })
                            LANGUAGES.forEach { (tag, name) ->
                                DropdownMenuItem({ Text(name) }, { langMenu = false; AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(tag)) })
                            }
                        }
                    }
                }
            }
        }
        item {
            Card {
                val bgLabel = stringResource(R.string.bg_title)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(bgLabel, color = p.ink, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                        Text(stringResource(R.string.bg_hint), color = p.inkSecondary, fontSize = 13.sp)
                    }
                    Spacer(Modifier.width(12.dp))
                    Switch(store.backgroundEnabled, { store.setBackground(it) }, Modifier.semantics { contentDescription = bgLabel },
                        colors = SwitchDefaults.colors(checkedTrackColor = ActionBlue, checkedThumbColor = Color.White))
                }
            }
        }
        item {
            Card {
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Filled.Lock, null, tint = p.ink, modifier = Modifier.size(16.dp))
                        Text(stringResource(R.string.privacy), color = p.ink, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    }
                    SettingSwitch(R.string.priv_relay, R.string.priv_relay_body, store.relayOthers) { store.changeRelay(it) }
                    SettingSwitch(R.string.priv_receipts, R.string.priv_receipts_body, store.receipts) { store.changeReceipts(it) }
                    SettingSwitch(R.string.priv_previews, R.string.priv_previews_body, store.hidePreviews) { store.changeHidePreviews(it) }
                    Text(stringResource(R.string.priv_autodelete), color = p.ink, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(0, 1, 7, 30).forEach { d ->
                            Chip(when (d) { 0 -> stringResource(R.string.priv_never); 1 -> stringResource(R.string.priv_1day); else -> stringResource(R.string.priv_days, d) },
                                store.autoDeleteDays == d) { store.changeAutoDelete(d) }
                        }
                    }
                }
            }
        }
        item {
            Box(Modifier.fillMaxWidth().glass(12.dp).clickable { confirmWipe = true }.padding(vertical = 14.dp), contentAlignment = Alignment.Center) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Filled.Delete, null, tint = Color(0xFFD93025), modifier = Modifier.size(16.dp))
                    Text(stringResource(R.string.erase), color = Color(0xFFD93025), fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        item {
            SkyPill(Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Filled.Construction, null, tint = Color.White, modifier = Modifier.size(16.dp))
                    Text(stringResource(R.string.project_status), color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                }
                Spacer(Modifier.height(6.dp))
                Text(stringResource(R.string.project_status_body), color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp)
            }
        }
    }
    if (showQr) AddOrVerifyDialog(store) { showQr = false }
    if (confirmWipe) AlertDialog(
        onDismissRequest = { confirmWipe = false },
        title = { Text(stringResource(R.string.erase_confirm)) },
        text = { Text(stringResource(R.string.erase_confirm_body)) },
        confirmButton = { TextButton({ confirmWipe = false; store.wipeAll() }) { Text(stringResource(R.string.erase), color = Color(0xFFD93025)) } },
        dismissButton = { TextButton({ confirmWipe = false }) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun SettingSwitch(@StringRes title: Int, @StringRes body: Int, on: Boolean, onChange: (Boolean) -> Unit) {
    val p = LocalPalette.current
    val label = stringResource(title)
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, color = p.ink, fontSize = 15.sp)
            Text(stringResource(body), color = p.inkSecondary, fontSize = 12.sp)
        }
        Spacer(Modifier.width(12.dp))
        Switch(on, onChange, Modifier.semantics { contentDescription = label },
            colors = SwitchDefaults.colors(checkedTrackColor = ActionBlue, checkedThumbColor = Color.White))
    }
}
