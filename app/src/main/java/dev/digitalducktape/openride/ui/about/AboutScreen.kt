package dev.digitalducktape.openride.ui.about

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dev.digitalducktape.openride.R
import dev.digitalducktape.openride.ui.designsystem.BikePreview
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.OrType
import dev.digitalducktape.openride.ui.designsystem.component.OrEyebrow
import dev.digitalducktape.openride.ui.designsystem.component.OrSecondaryButton
import dev.digitalducktape.openride.ui.designsystem.component.OrTile
import dev.digitalducktape.openride.ui.designsystem.component.OrTopBar
import dev.digitalducktape.openride.ui.theme.OpenRideTheme

/** The words on the About screen and its Profile row, kept apart so tests can pin them. */
object AboutLabels {
    const val SUPPORT_URL = "https://buymeacoffee.com/digitalducktape"
    const val REPO_URL = "https://github.com/digitalducktape/openride"

    /** The version a rider knows: the bike build's `-real` suffix is ours, not theirs. */
    fun version(versionName: String): String = "Version ${versionName.substringBefore('-')}"

    /** The Profile row's second line: what's behind it, version first. */
    fun rowValue(versionName: String): String = "${version(versionName)}  •  Help fund this app"

    /** URLs shown as text, without the scheme: shorter to read and to type into a phone. */
    fun display(url: String): String = url.removePrefix("https://")
}

/**
 * About & support connected to its data: the installed version's release notes, bundled in
 * `res/raw/release_notes.txt` (written at release time, see docs/INSTALL.md) so the page works
 * with no network.
 */
@Composable
fun AboutRoute(
    versionName: String,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val notes = remember {
        context.resources.openRawResource(R.raw.release_notes).bufferedReader().use { it.readText() }.trim()
    }
    AboutScreen(versionName = versionName, releaseNotes = notes, onDone = onDone, modifier = modifier)
}

/**
 * About & support (#86): this version's release notes, where to send feedback and pull
 * requests, and a QR code for the developer's Buy Me a Coffee page. A rider scans it with their
 * phone: the bike's tablet may have no browser, so the screen links to nothing and opens nothing.
 *
 * Reached only from Profile → Device → About & support; nothing here pops up on its own, and
 * nothing of it shows during rides or games. The notes are the only part that scrolls.
 */
@Composable
fun AboutScreen(
    versionName: String,
    releaseNotes: String,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize().background(OrColors.Background)) {
        OrTopBar(
            title = "About & support",
            actions = { OrSecondaryButton(text = "Done", onClick = onDone) },
        )
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(start = OrSpacing.ScreenGutter, end = OrSpacing.ScreenGutter, top = OrSpacing.sm, bottom = OrSpacing.lg),
            horizontalArrangement = Arrangement.spacedBy(OrSpacing.lg),
        ) {
            OrTile(modifier = Modifier.weight(3f).fillMaxHeight()) {
                OrEyebrow(text = "What's new in OpenRide")
                Text(
                    text = AboutLabels.version(versionName),
                    style = OrType.Title,
                    color = OrColors.OnBackground,
                    modifier = Modifier.padding(top = OrSpacing.sm),
                )
                Text(
                    text = releaseNotes,
                    style = OrType.Body,
                    color = OrColors.OnSurfaceMuted,
                    modifier = Modifier
                        .padding(top = OrSpacing.sm)
                        .weight(1f)
                        .verticalScroll(rememberScrollState()),
                )
                HorizontalDivider(color = OrColors.Divider, modifier = Modifier.padding(vertical = OrSpacing.md))
                Text(
                    text = "Feedback, questions or ideas? Find us on GitHub. We welcome pull requests!",
                    style = OrType.Body,
                    color = OrColors.OnBackground,
                )
                Text(
                    text = AboutLabels.display(AboutLabels.REPO_URL),
                    style = OrType.Subtitle,
                    color = OrColors.OnBackground,
                    modifier = Modifier.padding(top = OrSpacing.xs),
                )
                Text(
                    text = "Free and open source under the Apache License 2.0. " +
                        "An independent project, not affiliated with Peloton Interactive, Inc.",
                    style = OrType.Caption,
                    color = OrColors.OnSurfaceMuted,
                    modifier = Modifier.padding(top = OrSpacing.sm),
                )
            }

            OrTile(modifier = Modifier.weight(2f).fillMaxHeight()) {
                OrEyebrow(text = "Help fund OpenRide")
                Text(
                    text = "Thanks for riding with OpenRide! It's free, and building it runs on AI " +
                        "tokens (and coffee). If you'd like to help keep it going, a donation of any size makes a " +
                        "real difference. Scan the code below with your phone to chip in.",
                    style = OrType.Body,
                    color = OrColors.OnBackground,
                    modifier = Modifier.padding(top = OrSpacing.sm),
                )
                Column(
                    modifier = Modifier.fillMaxWidth().weight(1f),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    // Black on its own white square, quiet zone included, so it scans on the
                    // app's dark background.
                    Image(
                        painter = painterResource(R.drawable.support_qr),
                        contentDescription = "QR code for ${AboutLabels.display(AboutLabels.SUPPORT_URL)}",
                        modifier = Modifier.size(QrSize),
                    )
                    Text(
                        text = AboutLabels.display(AboutLabels.SUPPORT_URL),
                        style = OrType.Subtitle,
                        color = OrColors.OnBackground,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = OrSpacing.md),
                    )
                }
            }
        }
    }
}

/** 37 modules (29 plus the quiet zone) at 6 dp each: big enough to scan from a phone held back. */
private val QrSize = 222.dp

@BikePreview
@Composable
private fun AboutScreenPreview() {
    OpenRideTheme {
        AboutScreen(
            versionName = "1.1.0",
            releaseNotes = "OpenRide 1.1: a music player, a home screen setting, and fixes.\n\n" +
                "Music player: see what's playing in your music app.",
            onDone = {},
        )
    }
}
