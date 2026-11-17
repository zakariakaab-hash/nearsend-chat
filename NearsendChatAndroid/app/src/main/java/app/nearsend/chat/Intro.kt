package app.nearsend.chat

import androidx.annotation.StringRes
import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import kotlin.math.sin

// First-run story: what Nearsend does today, one animated idea per page, then your name.
// Only features that exist are shown (no SOS / store-and-forward-in-relays until they are built).

private class Story(@StringRes val tag: Int, @StringRes val title: Int, @StringRes val body: Int)

private val STORY = listOf(
    Story(R.string.story_tag1, R.string.story1_title, R.string.story1_body),
    Story(R.string.story_tag2, R.string.story2_title, R.string.story2_body),
    Story(R.string.story_tag3, R.string.story3_title, R.string.story3_body),
    Story(R.string.story_tag4, R.string.story4_title, R.string.story4_body),
    Story(R.string.story_tag5, R.string.story5_title, R.string.story5_body),
    Story(R.string.story_tag6, R.string.story6_title, R.string.story6_body),
)

private const val STORY_MS = 6000
private val StoryNavy = Color(0xFF0B1F4A)   // solid, deeper than SkyPillColor, so slide text never sits on see-through sky

@Composable
fun OnboardingScreen(store: ChatStore, onDone: () -> Unit) {
    val pager = rememberPagerState { STORY.size }
    val scope = rememberCoroutineScope()
    val last = pager.currentPage == STORY.size - 1
    var name by remember { mutableStateOf(if (store.nickname.startsWith("anon-")) "" else store.nickname) }
    val finish = {
        if (name.isNotBlank()) { store.updateNickname(name.trim()); store.applyNickname() }
        onDone()
    }
    // Story bars: the current one fills over STORY_MS, then the next slide comes in by itself (the last one waits for the name).
    val progress = remember { Animatable(0f) }
    LaunchedEffect(pager.currentPage) {
        progress.snapTo(0f)
        progress.animateTo(1f, tween(STORY_MS, easing = LinearEasing))
        if (pager.currentPage < STORY.size - 1) pager.animateScrollToPage(pager.currentPage + 1)
    }
    Column(Modifier.fillMaxSize().systemBarsPadding().imePadding().padding(bottom = 20.dp)) {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for (i in STORY.indices) {
                val fill = when { i < pager.currentPage -> 1f; i == pager.currentPage -> progress.value; else -> 0f }
                Box(Modifier.weight(1f).height(4.dp).background(Color.White.copy(alpha = 0.35f), CircleShape)) {
                    Box(Modifier.fillMaxWidth(fill).fillMaxHeight().background(Color.White, CircleShape))
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("NEARSEND", fontFamily = Anton, fontSize = 22.sp, color = Color.White)
            Spacer(Modifier.weight(1f))
            if (!last) Text(stringResource(R.string.story_skip), color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.clickable { scope.launch { pager.animateScrollToPage(STORY.size - 1) } }.padding(8.dp))
        }
        HorizontalPager(pager, Modifier.weight(1f)) { i ->
            val s = STORY[i]
            val art = @Composable {
                Box(Modifier.widthIn(max = 420.dp).fillMaxWidth().height(250.dp), contentAlignment = Alignment.Center) {
                    when (i) {
                        0 -> NoSignalArt()
                        5 -> NameArt(name.ifBlank { store.nickname })
                        else -> StoryCanvas(i)
                    }
                }
            }
            val text = @Composable { withArt: Boolean ->
                Column(Modifier.verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text(stringResource(s.tag), color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Medium,
                        modifier = Modifier.background(StoryNavy, CircleShape).padding(horizontal = 14.dp, vertical = 6.dp))
                    Text(upper(stringResource(s.title)), fontFamily = Anton, fontSize = 36.sp, lineHeight = 40.sp, color = Color.White, textAlign = TextAlign.Center)
                    if (withArt) art()
                    Text(stringResource(s.body), color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center,
                        modifier = Modifier.widthIn(max = 480.dp).fillMaxWidth().background(StoryNavy, RoundedCornerShape(24.dp))
                            .padding(horizontal = 20.dp, vertical = 12.dp))
                    if (i == STORY.size - 1) NameField(name, { name = it.take(24) }, onDone = finish)
                }
            }
            BoxWithConstraints(Modifier.fillMaxSize().padding(horizontal = 24.dp), contentAlignment = Alignment.Center) {
                // Wide and short (phone in landscape): art beside the text instead of above it.
                if (maxWidth > maxHeight) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { art() }
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { text(false) }
                } else text(true)
            }
        }
        Spacer(Modifier.height(12.dp))
        PrimaryButton(stringResource(if (last) R.string.ob_allow else R.string.ob_continue), Modifier.padding(horizontal = 24.dp).widthIn(max = 480.dp).align(Alignment.CenterHorizontally)) {
            if (last) finish() else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
        }
    }
}

@Composable
private fun NameField(value: String, onChange: (String) -> Unit, onDone: () -> Unit) {
    val p = LocalPalette.current
    Box(Modifier.widthIn(max = 480.dp).fillMaxWidth().glass(14.dp).padding(horizontal = 16.dp, vertical = 14.dp)) {
        if (value.isEmpty()) Text(stringResource(R.string.story_name_hint), color = p.inkSecondary, fontSize = 17.sp)
        BasicTextField(value, onChange, singleLine = true, textStyle = TextStyle(color = p.ink, fontSize = 17.sp),
            cursorBrush = SolidColor(ActionBlue), keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { onDone() }), modifier = Modifier.fillMaxWidth())
    }
}

/** Page 1: our own phone pinging into silence: pulsing rings around a "no signal" badge. */
@Composable
private fun NoSignalArt() {
    val t by rememberInfiniteTransition(label = "ping").animateFloat(0f, 1f, infiniteRepeatable(tween(2600, easing = LinearEasing)), label = "t")
    Box(contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(240.dp)) {
            for (k in 0 until 3) {
                val f = (t + k / 3f) % 1f
                drawCircle(Color.White.copy(alpha = (1 - f) * 0.7f), size.minDimension / 2 * (0.35f + 0.65f * f), style = Stroke(1.5.dp.toPx()))
            }
        }
        Box(Modifier.size(96.dp).glass(48.dp), contentAlignment = Alignment.Center) {
            // Four rising bars like the signal icon in the status bar, struck through: no cell signal needed.
            Canvas(Modifier.size(46.dp)) {
                val bw = size.width * 0.16f; val gap = (size.width - 4 * bw) / 3
                for (k in 0 until 4) {
                    val h = size.height * (0.30f + 0.23f * k)
                    drawRoundRect(ActionBlue, Offset(k * (bw + gap), size.height - h), Size(bw, h), CornerRadius(bw / 3))
                }
                val from = Offset(size.width * 0.04f, size.height * 0.04f); val to = Offset(size.width * 0.96f, size.height * 0.96f)
                drawLine(Color.White, from, to, 8.dp.toPx(), StrokeCap.Round)      // a light edge so the slash reads over the bars
                drawLine(ActionBlue, from, to, 4.dp.toPx(), StrokeCap.Round)
            }
        }
    }
}

/** Last page: the original Nearsend radar, with your name on the centre dot. */
@Composable
private fun NameArt(name: String) {
    // Stays round when a short landscape screen gives it less than 240 dp of height.
    Box(Modifier.widthIn(max = 240.dp).aspectRatio(1f, matchHeightConstraintsFirst = true).glass(120.dp), contentAlignment = Alignment.Center) {
        Radar(emptyList(), Modifier.fillMaxSize().padding(10.dp))
        Text(name, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1,
            modifier = Modifier.offset(y = 30.dp).background(ActionBlue, CircleShape).padding(horizontal = 12.dp, vertical = 4.dp))
    }
}

/** Pages 2-5 are drawn on one canvas with a looping clock `t` (0..1). */
@Composable
private fun StoryCanvas(page: Int) {
    val t by rememberInfiniteTransition(label = "story").animateFloat(0f, 1f, infiniteRepeatable(tween(3600, easing = LinearEasing)), label = "t")
    val tm = rememberTextMeasurer()
    val you = stringResource(R.string.lbl_you); val friend = stringResource(R.string.lbl_friend); val waiting = stringResource(R.string.lbl_waiting)
    Canvas(Modifier.fillMaxSize()) {
        fun at(x: Float, y: Float) = Offset(size.width * x, size.height * y)
        when (page) {
            1 -> {   // hops: a message travels You → three phones → Friend
                for (k in 0 until 26) drawCircle(Color.White.copy(alpha = 0.35f), 2.dp.toPx(),
                    at(frac(sin(k * 12.9898f) * 43758.547f), frac(sin(k * 78.233f) * 12543.123f)))
                val path = listOf(at(.12f, .84f), at(.34f, .58f), at(.56f, .72f), at(.70f, .36f), at(.88f, .14f))
                val travel = (t * 1.25f).coerceAtMost(1f)
                polyline(path, Color.White.copy(alpha = 0.35f), 1f)
                polyline(path, Color.White, travel)
                path.forEachIndexed { k, pt -> node(pt, filled = k == 0 || (k == path.lastIndex && travel >= 1f)) }
                drawCircle(Color.White.copy(alpha = 0.35f), 14.dp.toPx(), pointOn(path, travel))
                drawCircle(Color.White, 6.dp.toPx(), pointOn(path, travel))
                label(tm, you, path.first() + Offset(0f, 14.dp.toPx()))
                label(tm, friend, path.last() + Offset(0f, 14.dp.toPx()))
            }
            2 -> {   // waits: the friend is away, the envelope sits on your phone, then goes when they show up
                val a = at(.22f, .55f); val b = at(.78f, .55f)
                val arrive = ((t - .5f) / .15f).coerceIn(0f, 1f)
                val move = ((t - .62f) / .25f).coerceIn(0f, 1f)
                drawLine(Color.White.copy(alpha = 0.35f + 0.5f * arrive), a, b, 1.5.dp.toPx(),
                    pathEffect = if (arrive < 1f) PathEffect.dashPathEffect(floatArrayOf(10f, 10f)) else null)
                node(a, filled = true)
                if (arrive > 0f) node(b, filled = move >= 1f, alpha = arrive)
                else drawCircle(Color.White.copy(alpha = 0.3f), 9.dp.toPx(), b, style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f))))
                val bob = if (move == 0f) sin(t * 20f) * 3.dp.toPx() else 0f
                envelope(Offset(a.x + (b.x - a.x) * move, a.y - 34.dp.toPx() + bob))
                if (move == 0f) label(tm, waiting, a + Offset(0f, -64.dp.toPx()), boxed = true)
                label(tm, you, a + Offset(0f, 14.dp.toPx()))
                label(tm, friend, b + Offset(0f, 14.dp.toPx()), alpha = arrive.coerceAtLeast(0.4f))
            }
            3 -> {   // sealed: relays carry it but show a lock
                val xs = listOf(.1f, .37f, .63f, .9f).map { at(it, .62f) }
                drawLine(Color.White.copy(alpha = 0.6f), xs.first(), xs.last(), 1.5.dp.toPx())
                xs.forEachIndexed { k, pt -> node(pt, filled = k == 0 || k == 3); if (k in 1..2) padlock(pt + Offset(0f, -36.dp.toPx())) }
                envelope(pointOn(xs, t) + Offset(0f, -14.dp.toPx()))
                label(tm, you, xs.first() + Offset(0f, 14.dp.toPx()))
                label(tm, friend, xs.last() + Offset(0f, 14.dp.toPx()))
            }
            4 -> {   // verify: a QR on one phone, a scan line, then a tick on both
                val w = size.width * .2f; val h = w * 1.8f
                val l = at(.3f, .5f) - Offset(w / 2, h / 2); val r = at(.7f, .5f) - Offset(w / 2, h / 2)
                // Left: an iPhone (rounder corners, pill-shaped Dynamic Island). Right: an Android phone (squarer, punch-hole camera).
                drawRoundRect(Color.White, l, Size(w, h), CornerRadius(16.dp.toPx()), style = Stroke(2.dp.toPx()))
                drawRoundRect(Color.White, r, Size(w, h), CornerRadius(10.dp.toPx()), style = Stroke(2.dp.toPx()))
                drawRoundRect(Color.White, l + Offset(w * .34f, 8.dp.toPx()), Size(w * .32f, 6.dp.toPx()), CornerRadius(3.dp.toPx()))
                drawCircle(Color.White, 3.dp.toPx(), r + Offset(w / 2, 11.dp.toPx()))
                val q = w * .7f; val qo = l + Offset((w - q) / 2, (h - q) / 2); val cell = q / 7
                for (k in 0 until 49) if (k in QR_DOTS) drawRect(Color.White, qo + Offset(k % 7 * cell, k / 7 * cell), Size(cell * .9f, cell * .9f))
                val done = t > .66f
                if (!done) {
                    val y = qo.y + q * ((t / .66f) % 1f)
                    drawLine(ActionBlue, Offset(qo.x - 6.dp.toPx(), y), Offset(qo.x + q + 6.dp.toPx(), y), 3.dp.toPx())
                    drawLine(Color.White.copy(alpha = 0.5f), Offset(r.x, r.y + h / 2), Offset(l.x + w, y), 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 8f)))
                } else for (o in listOf(l, r)) tick(o + Offset(w / 2, -18.dp.toPx()))
            }
        }
    }
}

private val QR_DOTS = setOf(0, 1, 2, 4, 5, 6, 7, 9, 11, 13, 14, 15, 16, 18, 19, 20, 22, 24, 26, 28, 29, 30, 31, 33, 35, 37, 39, 42, 43, 44, 46, 48)

private fun frac(v: Float) = v - kotlin.math.floor(v)

private fun DrawScope.node(c: Offset, filled: Boolean, alpha: Float = 1f) {
    drawCircle(Color.White.copy(alpha = 0.25f * alpha), 15.dp.toPx(), c)
    drawCircle(if (filled) Color.White.copy(alpha = alpha) else SkyPillColor.copy(alpha = alpha), 9.dp.toPx(), c)
    drawCircle(Color.White.copy(alpha = alpha), 9.dp.toPx(), c, style = Stroke(2.dp.toPx()))
}

private fun DrawScope.polyline(pts: List<Offset>, color: Color, upTo: Float) {
    val segs = pts.zipWithNext(); val total = segs.sumOf { (a, b) -> (b - a).getDistance().toDouble() }.toFloat()
    var left = total * upTo
    for ((a, b) in segs) {
        val len = (b - a).getDistance()
        if (left <= 0f) break
        val f = (left / len).coerceAtMost(1f)
        drawLine(color, a, a + (b - a) * f, 2.dp.toPx())
        left -= len
    }
}

private fun pointOn(pts: List<Offset>, f: Float): Offset {
    val segs = pts.zipWithNext(); val total = segs.sumOf { (a, b) -> (b - a).getDistance().toDouble() }.toFloat()
    var left = total * f.coerceIn(0f, 1f)
    for ((a, b) in segs) {
        val len = (b - a).getDistance()
        if (left <= len) return a + (b - a) * (left / len)
        left -= len
    }
    return pts.last()
}

private fun DrawScope.envelope(c: Offset) {
    val w = 26.dp.toPx(); val h = 18.dp.toPx(); val o = c - Offset(w / 2, h / 2)
    drawRoundRect(Color.White, o, Size(w, h), CornerRadius(3.dp.toPx()))
    drawLine(ActionBlue, o, Offset(c.x, c.y + 1.dp.toPx()), 1.5.dp.toPx())
    drawLine(ActionBlue, Offset(o.x + w, o.y), Offset(c.x, c.y + 1.dp.toPx()), 1.5.dp.toPx())
}

private fun DrawScope.padlock(c: Offset) {
    val w = 18.dp.toPx(); val h = 14.dp.toPx()
    drawArc(Color.White, 180f, 180f, false, Offset(c.x - w * .32f, c.y - h * .95f), Size(w * .64f, h * .9f), style = Stroke(2.5.dp.toPx()))
    drawRoundRect(Color.White, Offset(c.x - w / 2, c.y - h / 2), Size(w, h), CornerRadius(3.dp.toPx()))
}

private fun DrawScope.tick(c: Offset) {
    drawCircle(PairedGreen, 16.dp.toPx(), c)
    val s = 6.dp.toPx()
    drawLine(Color.White, c + Offset(-s, 0f), c + Offset(-s / 3, s * .7f), 3.dp.toPx())
    drawLine(Color.White, c + Offset(-s / 3, s * .7f), c + Offset(s, -s * .6f), 3.dp.toPx())
}

private fun DrawScope.label(tm: TextMeasurer, text: String, top: Offset, boxed: Boolean = false, alpha: Float = 1f) {
    val m = tm.measure(text, TextStyle(color = Color.White.copy(alpha = alpha), fontSize = 13.sp, fontWeight = FontWeight.SemiBold))
    val o = Offset(top.x - m.size.width / 2f, top.y)
    if (boxed) drawRoundRect(SkyPillColor, o - Offset(10.dp.toPx(), 4.dp.toPx()),
        Size(m.size.width + 20.dp.toPx(), m.size.height + 8.dp.toPx()), CornerRadius(50.dp.toPx()))
    drawText(m, topLeft = o)
}
