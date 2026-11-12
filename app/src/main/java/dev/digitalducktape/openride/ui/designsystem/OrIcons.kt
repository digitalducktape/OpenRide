package dev.digitalducktape.openride.ui.designsystem

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Warning
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp

/**
 * The icons OpenRide uses, in one place so a screen never picks its own. All come from Material
 * Icons core (Apache-2.0), which Material 3 already brings in; `material-icons-extended` is
 * deliberately not a dependency (it adds megabytes for a handful of glyphs).
 */
object OrIcons {
    val Home: ImageVector = Icons.Filled.Home
    val Classes: ImageVector = Icons.Filled.PlayArrow
    val Games: ImageVector = Icons.Filled.Star

    /** A game's rating star; its own name so the Games tab icon can change without it. */
    val Star: ImageVector = Icons.Filled.Star
    val History: ImageVector = Icons.Filled.DateRange
    val Profile: ImageVector = Icons.Filled.Person
    val Settings: ImageVector = Icons.Filled.Settings
    val Add: ImageVector = Icons.Filled.Add
    val Info: ImageVector = Icons.Filled.Info
    val Warning: ImageVector = Icons.Filled.Warning
    /** The bin: deleting a ride from its detail screen. */
    val Delete: ImageVector = Icons.Filled.Delete
    val Chevron: ImageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight

    // Music transport (the mini player). Core has only Play, so the other three are Material's
    // own path data (Apache-2.0), copied rather than pulling in the extended set.
    val Play: ImageVector = Icons.Filled.PlayArrow
    val Pause: ImageVector = materialGlyph("Pause", "M6,19h4V5H6v14zM14,5v14h4V5h-4z")
    val SkipNext: ImageVector = materialGlyph("SkipNext", "M6,18l8.5,-6L6,6v12zM16,6v12h2V6h-2z")
    val SkipPrevious: ImageVector = materialGlyph("SkipPrevious", "M6,6h2v12H6zM9.5,12l8.5,6V6z")
    val MusicNote: ImageVector = materialGlyph(
        "MusicNote",
        "M12,3v10.55c-0.59,-0.34 -1.27,-0.55 -2,-0.55 -2.21,0 -4,1.79 -4,4s1.79,4 4,4 4,-1.79 4,-4V7h4V3h-6z",
    )
}

/** A 24 × 24 Material icon from its SVG path data. */
private fun materialGlyph(name: String, pathData: String): ImageVector =
    ImageVector.Builder(name, defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
        .addPath(addPathNodes(pathData), fill = SolidColor(Color.Black))
        .build()
