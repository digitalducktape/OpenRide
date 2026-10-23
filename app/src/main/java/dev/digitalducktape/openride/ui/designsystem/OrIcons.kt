package dev.digitalducktape.openride.ui.designsystem

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Warning
import androidx.compose.ui.graphics.vector.ImageVector

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
    val Check: ImageVector = Icons.Filled.Check
    val Info: ImageVector = Icons.Filled.Info
    val Warning: ImageVector = Icons.Filled.Warning
    val Chevron: ImageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight
}
