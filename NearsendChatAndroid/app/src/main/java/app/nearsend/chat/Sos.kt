package app.nearsend.chat

import android.Manifest
import android.content.Intent
import android.location.Location
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.math.roundToInt

/** Tab index (You stays 2 so existing launch extras keep working). */
const val SOS_TAB = 3

val SosRed = Color(0xFFD7263D)
private val SosRedDeep = Color(0xFFA8172B)
private const val HOLD_MS = 2000

@Composable
fun SosScreen(store: ChatStore) {
    val p = LocalPalette.current
    val ctx = LocalContext.current
    DisposableEffect(Unit) { store.useLocation(true); onDispose { store.useLocation(false) } }
    var hasPermission by remember { mutableStateOf(store.hasLocationPermission()) }
    val askLocation = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        hasPermission = store.hasLocationPermission()
        store.useLocation(true); store.useLocation(false)   // re-registers GPS now that we may use it
    }
    val ask = { askLocation.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)) }
    val compass = stringResource(R.string.compass).split(",")
    val smsIntro = stringResource(R.string.sos_sms); val smsPos = stringResource(R.string.sos_my_position)

    LazyColumn(Modifier.fillMaxSize().statusBarsPadding(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        item { PageTitle(R.string.tab_sos) }
        item { SkyPill(Modifier.fillMaxWidth()) { Text(stringResource(R.string.sos_reach), color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Medium) } }
        item { SosButton(store.mySos != null) { store.startSos() } }
        if (store.mySos != null) item {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(stringResource(R.string.sos_on), color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.background(SosRed, CircleShape).padding(horizontal = 14.dp, vertical = 6.dp))
                PrimaryButton(stringResource(R.string.sos_stop)) { store.stopSos() }
            }
        }
        item {
            Card(padding = 14.dp) {
                Box {
                    if (store.sosNote.isEmpty()) Text(stringResource(R.string.sos_note), color = p.inkSecondary, fontSize = 15.sp)
                    BasicTextField(store.sosNote, { store.sosNote = it.take(120) }, Modifier.fillMaxWidth(), maxLines = 3,
                        textStyle = TextStyle(color = p.ink, fontSize = 15.sp), cursorBrush = SolidColor(SosRed))
                }
            }
        }
        item {
            Card {
                val label = stringResource(R.string.sos_loc)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Filled.Place, null, tint = SosRed)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(label, color = p.ink, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                        Text(stringResource(R.string.sos_loc_body), color = p.inkSecondary, fontSize = 13.sp)
                    }
                    Switch(store.shareLocation, { store.shareLocationOn(it); if (it && !hasPermission) ask() },
                        Modifier.semantics { contentDescription = label },
                        colors = SwitchDefaults.colors(checkedTrackColor = SosRed, checkedThumbColor = Color.White))
                }
                if (store.shareLocation) {
                    Spacer(Modifier.height(8.dp))
                    when {
                        !hasPermission -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(stringResource(R.string.sos_loc_perm), color = SosRed, fontSize = 13.sp)
                            Text(stringResource(R.string.sos_allow), color = p.link, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable { ask() })
                        }
                        store.myLocation == null -> Text(stringResource(R.string.sos_loc_search), color = p.inkSecondary, fontSize = 13.sp)
                        else -> Text(stringResource(R.string.sos_loc_found, store.myLocation!!.accuracy.roundToInt()), color = p.secure, fontSize = 13.sp)
                    }
                }
                Spacer(Modifier.height(8.dp))
                Text(stringResource(R.string.sos_public), color = p.inkSecondary, fontSize = 12.sp)
            }
        }
        item {
            if (store.alerts.isEmpty()) Card {
                Text(stringResource(R.string.sos_alarms), color = p.ink, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(8.dp))
                Text(stringResource(R.string.sos_quiet), color = p.inkSecondary, fontSize = 14.sp)
            } else Text(upper(stringResource(R.string.sos_alarms)), fontFamily = Anton, fontSize = 22.sp, color = Color.White, modifier = Modifier.fillMaxWidth())
        }
        items(store.alerts, key = { it.from + it.alarm }) { a -> AlertCard(a, distanceText(store.myLocation, a, compass)) }
        item {
            Card {
                Text(stringResource(R.string.sos_beyond), color = p.ink, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(4.dp))
                Text(stringResource(R.string.sos_beyond_body), color = p.inkSecondary, fontSize = 13.sp)
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    SosAction(stringResource(R.string.sos_call), Icons.Filled.Call, filled = true, Modifier.weight(1f)) {
                        runCatching { ctx.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:112"))) }
                    }
                    SosAction(stringResource(R.string.sos_text), Icons.Filled.Sms, filled = false, Modifier.weight(1f)) {
                        val body = buildString {
                            append(smsIntro)
                            store.sosNote.takeIf { it.isNotBlank() }?.let { append(" ").append(it) }
                            store.myLocation?.let { l ->
                                val lat = "%.5f".format(Locale.US, l.latitude); val lon = "%.5f".format(Locale.US, l.longitude)
                                append("\n").append(smsPos).append(" https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=17/$lat/$lon (±${l.accuracy.roundToInt()} m)")
                            }
                        }
                        runCatching { ctx.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:")).putExtra("sms_body", body)) }
                    }
                }
            }
        }
    }
}

/** Press and hold: a ring fills over [HOLD_MS]; letting go early cancels. While SOS is on it pulses. */
@Composable
private fun SosButton(active: Boolean, onTrigger: () -> Unit) {
    val progress = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val pulse by rememberInfiniteTransition(label = "sos").animateFloat(0f, 1f, infiniteRepeatable(tween(1400, easing = LinearEasing)), label = "p")
    val desc = stringResource(R.string.sos_hold_desc)
    LaunchedEffect(active) { progress.snapTo(0f) }   // the press handler restarts when SOS turns on, before it can reset
    Box(Modifier.size(230.dp).semantics { contentDescription = desc }.pointerInput(active) {
        detectTapGestures(onPress = {
            if (active) return@detectTapGestures
            val fill = scope.launch { progress.animateTo(1f, tween(HOLD_MS, easing = LinearEasing)); onTrigger() }
            tryAwaitRelease()
            fill.cancel(); scope.launch { progress.snapTo(0f) }
        })
    }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val r = size.minDimension / 2
            if (active) drawCircle(SosRed.copy(alpha = 0.35f * (1 - pulse)), r * (0.78f + 0.22f * pulse))
            drawCircle(Color.White.copy(alpha = 0.35f), r * 0.86f)
            if (progress.value > 0f) drawArc(Color.White, -90f, 360f * progress.value, false, Offset(r * 0.1f, r * 0.1f), Size(r * 1.8f, r * 1.8f),
                style = Stroke(8.dp.toPx(), cap = StrokeCap.Round))
            drawCircle(if (active) SosRedDeep else SosRed, r * 0.74f)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("SOS", fontFamily = Anton, fontSize = 52.sp, color = Color.White)
            if (!active) Text(stringResource(R.string.sos_hold), color = Color.White.copy(alpha = 0.9f), fontSize = 14.sp)
        }
    }
}

@Composable
private fun AlertCard(a: SosAlert, distance: String?) {
    val p = LocalPalette.current
    val ctx = LocalContext.current
    Card(padding = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(12.dp).background(if (a.active) SosRed else p.inkSecondary, CircleShape))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("${a.name} · ${stringResource(R.string.sos_needs_help)}", color = p.ink, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                a.note?.let { Text(it, color = p.ink, fontSize = 14.sp) }
                val meta = listOfNotNull(
                    distance?.let { d -> a.accuracy?.let { "$d · ±$it m" } ?: d },
                    if (a.hops == 1) null else stringResource(R.string.n_hops_relay, a.hops),
                    if (a.active) java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date(a.timeMs)) else stringResource(R.string.sos_ended),
                ).joinToString(" · ")
                Text(meta, color = if (a.active) SosRed else p.inkSecondary, fontSize = 13.sp, fontWeight = FontWeight.Medium)
            }
            if (a.lat != null && a.lon != null) {
                val mapLabel = stringResource(R.string.sos_map)
                Icon(Icons.Filled.Map, mapLabel, tint = p.link, modifier = Modifier.size(40.dp).clickable {
                    runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("geo:${a.lat},${a.lon}?q=${a.lat},${a.lon}(${Uri.encode(a.name)})"))) }
                }.padding(8.dp))
            }
        }
    }
}

@Composable
private fun SosAction(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, filled: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val p = LocalPalette.current
    val shape = RoundedCornerShape(12.dp)
    Row(modifier.height(48.dp).then(if (filled) Modifier.background(SosRed, shape) else Modifier.glass(12.dp)).clickable(onClick = onClick).padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
        Icon(icon, null, tint = if (filled) Color.White else SosRed, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(6.dp))
        Text(title, color = if (filled) Color.White else p.ink, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, maxLines = 2)
    }
}

/** "350 m NE" from our position to theirs (north-up compass point, not where the phone is facing). */
private fun distanceText(me: Location?, a: SosAlert, compass: List<String>): String? {
    if (me == null || a.lat == null || a.lon == null || compass.size != 8) return null
    val r = FloatArray(2)
    Location.distanceBetween(me.latitude, me.longitude, a.lat, a.lon, r)
    val dir = compass[(((r[1] + 360f + 22.5f) % 360f) / 45f).toInt() % 8]
    val dist = if (r[0] < 1000) "${r[0].roundToInt()} m" else "%.1f km".format(r[0] / 1000)
    return "$dist $dir"
}
