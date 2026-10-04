package dev.digitalducktape.openride.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.digitalducktape.openride.ui.theme.OpenRideColors
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import dev.digitalducktape.openride.AppContainer
import kotlinx.coroutines.flow.map
import dev.digitalducktape.openride.viewModelFactory
import dev.digitalducktape.openride.ui.classes.ClassesScreen
import dev.digitalducktape.openride.ui.classes.ClassesViewModel
import dev.digitalducktape.openride.ui.games.GamesScreen
import dev.digitalducktape.openride.ui.games.GamesViewModel
import dev.digitalducktape.openride.ui.history.HistoryScreen
import dev.digitalducktape.openride.ui.history.HistoryViewModel
import dev.digitalducktape.openride.ui.home.HomeScreen
import dev.digitalducktape.openride.ui.home.HomeViewModel
import dev.digitalducktape.openride.ui.navigation.Destinations
import dev.digitalducktape.openride.ui.navigation.MainTabs
import dev.digitalducktape.openride.ui.profile.ProfileTabScreen
import dev.digitalducktape.openride.ui.profile.ProfileTabViewModel

private data class TabSpec(val route: String, val label: String, val icon: ImageVector, val emoji: String? = null)

private val TABS = listOf(
    TabSpec(MainTabs.Home, "Home", Icons.Filled.Home),
    TabSpec(MainTabs.Classes, "Classes", Icons.Filled.PlayArrow),
    TabSpec(MainTabs.Games, "Games", Icons.Filled.Star, emoji = "\uD83C\uDFAE"),
    TabSpec(MainTabs.History, "History", Icons.Filled.DateRange),
    TabSpec(MainTabs.Profile, "Profile", Icons.Filled.Person),
)

/**
 * The tabbed section of the app: a bottom [NavigationBar] (Home / Classes / History /
 * Profile — the bike-app tab arrangement, PRD P0-7 / v2 redesign spec) plus a nested
 * `NavHost` for those four destinations. Starting a ride or switching riders navigates the
 * *outer* nav controller (passed in), which lives one level up in
 * [dev.digitalducktape.openride.ui.navigation.OpenRideNavHost] — those flows intentionally
 * leave this tabbed chrome behind rather than becoming a fifth tab.
 */
@Composable
fun MainScaffold(
    appContainer: AppContainer,
    outerNavController: NavHostController,
    modifier: Modifier = Modifier,
) {
    val innerNavController = rememberNavController()
    val backStackEntry by innerNavController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route

    // Same options whether a tab comes from the bottom bar or an in-screen shortcut (the
    // home header's avatar chip): single top, state saved/restored per tab.
    fun navigateToTab(route: String) {
        innerNavController.navigate(route) {
            popUpTo(innerNavController.graph.findStartDestination().id) {
                saveState = true
            }
            launchSingleTop = true
            restoreState = true
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        NavHost(
            navController = innerNavController,
            startDestination = MainTabs.Home,
            modifier = Modifier.weight(1f),
        ) {
            composable(MainTabs.Home) {
                val viewModel: HomeViewModel = viewModel(
                    factory = viewModelFactory {
                        HomeViewModel(
                            appContainer.activeProfileHolder,
                            appContainer.profileRepository,
                            appContainer.rideSessionManager,
                        )
                    },
                )
                val availableUpdate by appContainer.updateAvailability.collectAsState()
                val bannerDismissed by appContainer.updateBannerDismissed.collectAsState()
                HomeScreen(
                    viewModel = viewModel,
                    onQuickStart = { outerNavController.navigate(Destinations.InRide) },
                    onOpenProfile = { navigateToTab(MainTabs.Profile) },
                    onOpenGames = { navigateToTab(MainTabs.Games) },
                    updateVersionName = availableUpdate?.versionName?.takeUnless { bannerDismissed },
                    onOpenUpdate = { outerNavController.navigate(Destinations.AppUpdate) },
                    onDismissUpdate = { appContainer.dismissUpdateBanner() },
                )
            }
            composable(MainTabs.Classes) {
                val viewModel: ClassesViewModel = viewModel(
                    factory = viewModelFactory {
                        ClassesViewModel(
                            appContainer.contentRepository,
                            appContainer.rideSessionManager,
                            appContainer.activeProfileHolder,
                            appContainer.rideRepository,
                        )
                    },
                )
                ClassesScreen(
                    viewModel = viewModel,
                    onStartVideoRide = { videoId ->
                        outerNavController.navigate(Destinations.videoRide(videoId))
                    },
                    onOpenCreator = { sourceId ->
                        outerNavController.navigate(Destinations.creator(sourceId))
                    },
                )
            }
            composable(MainTabs.Games) {
                val viewModel: GamesViewModel = viewModel(
                    factory = viewModelFactory {
                        GamesViewModel(
                            catalog = dev.digitalducktape.openride.games.session.GameCatalog.DEFAULT,
                            settingsStore = appContainer.gamesSettings,
                            activeProfileId = appContainer.activeProfileHolder.activeProfileId,
                            profileFtp = { id ->
                                appContainer.profileRepository.observeProfiles().map { list -> list.firstOrNull { it.id == id }?.ftp }
                            },
                            personalBests = { id -> appContainer.gameResultDao.observePersonalBests(id) },
                            circuitBest = { id, planId, difficulty ->
                                appContainer.gameResultDao.planBest(id, planId, difficulty.name.lowercase(), -1L)
                            },
                        )
                    },
                )
                GamesScreen(
                    viewModel = viewModel,
                    onEditProfile = { outerNavController.navigate(Destinations.ProfileEdit) },
                )
            }
            composable(MainTabs.History) {
                val viewModel: HistoryViewModel = viewModel(
                    factory = viewModelFactory {
                        HistoryViewModel(appContainer.activeProfileHolder, appContainer.rideRepository)
                    },
                )
                HistoryScreen(
                    viewModel = viewModel,
                    onRideSelected = { rideId ->
                        outerNavController.navigate(Destinations.rideSummary(rideId))
                    },
                )
            }
            composable(MainTabs.Profile) {
                val viewModel: ProfileTabViewModel = viewModel(
                    factory = viewModelFactory {
                        ProfileTabViewModel(
                            appContainer.activeProfileHolder,
                            appContainer.profileRepository,
                            appContainer.backupRepository,
                        )
                    },
                )
                ProfileTabScreen(
                    viewModel = viewModel,
                    onEditProfile = { outerNavController.navigate(Destinations.ProfileEdit) },
                    onSwitchRider = {
                        outerNavController.navigate(Destinations.ProfileSelect) {
                            popUpTo(Destinations.Main) { inclusive = true }
                        }
                    },
                    onRestoreComplete = {
                        // The active profile (and possibly its id entirely) may no longer be
                        // meaningful after a restore, so route back to profile select the same
                        // way "Switch rider" does rather than staying on a now-stale screen.
                        outerNavController.navigate(Destinations.ProfileSelect) {
                            popUpTo(Destinations.Main) { inclusive = true }
                        }
                    },
                    onManageHeartRateStrap = {
                        // Lives in the outer nav graph (see OpenRideNavHost), same reasoning as
                        // "switch rider": pairing is a full-screen flow, not a fifth tab.
                        outerNavController.navigate(Destinations.HrPairing)
                    },
                    onManageAppUpdates = { outerNavController.navigate(Destinations.AppUpdate) },
                    onManageContentSources = {
                        outerNavController.navigate(Destinations.ContentSources)
                    },
                    routeHolder = appContainer.routeHolder,
                )
            }
        }

        // Hairline above the bar — the bike app's tab bar sits on a near-black surface
        // separated from content by a faint divider rather than elevation.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(OpenRideColors.Divider),
        )
        NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
            TABS.forEach { tab ->
                NavigationBarItem(
                    selected = currentRoute == tab.route,
                    onClick = { navigateToTab(tab.route) },
                    icon = {
                        if (tab.emoji != null) Text(tab.emoji, fontSize = 24.sp) else Icon(imageVector = tab.icon, contentDescription = tab.label)
                    },
                    label = { Text(text = tab.label) },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = MaterialTheme.colorScheme.primary,
                        selectedTextColor = MaterialTheme.colorScheme.primary,
                        unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        indicatorColor = MaterialTheme.colorScheme.surfaceVariant,
                    ),
                )
            }
        }
    }
}
