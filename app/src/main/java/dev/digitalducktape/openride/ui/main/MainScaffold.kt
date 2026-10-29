package dev.digitalducktape.openride.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import dev.digitalducktape.openride.ui.designsystem.component.OrSecondaryButton
import dev.digitalducktape.openride.ui.designsystem.component.OrAccentButton
import dev.digitalducktape.openride.ui.common.ExportShare
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import dev.digitalducktape.openride.AppContainer
import dev.digitalducktape.openride.viewModelFactory
import dev.digitalducktape.openride.ui.classes.ClassesRoute
import dev.digitalducktape.openride.core.music.MusicApps
import dev.digitalducktape.openride.ui.music.MiniPlayer
import dev.digitalducktape.openride.ui.music.openMusicAccessSettings
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.component.OrNavBar
import dev.digitalducktape.openride.ui.designsystem.component.OrNavBarItem
import dev.digitalducktape.openride.ui.designsystem.component.OrTopBar
import dev.digitalducktape.openride.ui.classes.ClassesViewModel
import dev.digitalducktape.openride.ui.games.GamesLauncherScreen
import dev.digitalducktape.openride.ui.games.launchGames
import dev.digitalducktape.openride.ui.history.HistoryRoute
import dev.digitalducktape.openride.ui.history.HistoryViewModel
import dev.digitalducktape.openride.ui.home.HomeRoute
import dev.digitalducktape.openride.ui.home.HomeViewModel
import dev.digitalducktape.openride.ui.navigation.Destinations
import dev.digitalducktape.openride.ui.navigation.MainTabs
import dev.digitalducktape.openride.ui.profile.ProfileTabScreen
import dev.digitalducktape.openride.ui.profile.ProfileTabViewModel

/**
 * The tabbed section of the app (docs/MAIN_UI_REFRESH.md §3, "Shell"): the shared [OrTopBar]
 * (the tab's title, the screen's own actions, the rider), a nested `NavHost` for the tabs, and
 * the [OrNavBar] along the bottom (Home / Classes / Games / History / Profile, see
 * [TopLevelDestination]), as on the stock bike software. Starting a ride or switching riders navigates the
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

    // Single top, state saved/restored per tab.
    fun navigateToTab(route: String) {
        innerNavController.navigate(route) {
            popUpTo(innerNavController.graph.findStartDestination().id) {
                saveState = true
            }
            launchSingleTop = true
            restoreState = true
        }
    }

    val activeProfile by appContainer.activeProfile.collectAsState()

    // Every tab's view model, made here when the tabs first show rather than when each tab is
    // first opened, so their data is already loaded and a tab draws whole on its first frame
    // (rider bike test, 2026-10-21: History and Profile filled in piece by piece).
    val homeViewModel: HomeViewModel = viewModel(
        factory = viewModelFactory {
            HomeViewModel(appContainer.activeProfileHolder, appContainer.profileRepository, appContainer.rideSessionManager)
        },
    )
    val classesViewModel: ClassesViewModel = viewModel(
        factory = viewModelFactory {
            ClassesViewModel(
                appContainer.contentRepository,
                appContainer.rideSessionManager,
                appContainer.activeProfileHolder,
                appContainer.rideRepository,
            )
        },
    )
    val historyViewModel: HistoryViewModel = viewModel(
        factory = viewModelFactory { HistoryViewModel(appContainer.activeProfileHolder, appContainer.rideRepository) },
    )
    val profileViewModel: ProfileTabViewModel = viewModel(
        factory = viewModelFactory {
            ProfileTabViewModel(appContainer.activeProfileHolder, appContainer.profileRepository, appContainer.backupRepository)
        },
    )
    val classRows by classesViewModel.rows.collectAsState()
    val classGrid by classesViewModel.gridVideos.collectAsState()
    val history by historyViewModel.uiState.collectAsState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    // null until the shared rule first answers: the dot stays neutral rather than claiming "connected".
    val sensorsOffline by appContainer.sensorsOffline.collectAsState()
    val heartRateState by appContainer.heartRateManager.connectionState.collectAsState()
    val heartRateBpm by appContainer.heartRateManager.bpm.collectAsState()
    val controllerStatuses by appContainer.controllerManager.statuses.collectAsState()
    val bikeSource by appContainer.bikeSourceStore.source.collectAsState()
    val availableUpdate by appContainer.updateAvailability.collectAsState()
    val updateBannerDismissed by appContainer.updateBannerDismissed.collectAsState()
    val currentTab = TopLevelDestination.fromRoute(currentRoute) ?: TopLevelDestination.Start
    // Re-checked on every resume by the top bar's player, which is on every tab.
    val musicControlsOn by appContainer.nowPlaying.hasAccess.collectAsState()
    val defaultMusicApp by appContainer.nowPlaying.defaultApp.collectAsState()

    Column(modifier = modifier.fillMaxSize().background(OrColors.Background)) {
        OrTopBar(
            title = currentTab.label,
            // Each tab's own buttons, drawn with the bar in the same frame as the tab.
            actions = {
                when (currentTab) {
                    TopLevelDestination.Classes -> OrAccentButton(
                        text = "Random ride",
                        enabled = classGrid?.isNotEmpty() ?: classRows.any { it.videos.isNotEmpty() },
                        onClick = {
                            classesViewModel.startRandomRide()?.let { outerNavController.navigate(Destinations.videoRide(it)) }
                        },
                    )
                    TopLevelDestination.History -> if (history?.rows?.isNotEmpty() == true) {
                        OrSecondaryButton(text = "Export CSV", onClick = {
                            scope.launch {
                                val csv = historyViewModel.historyCsvContent()
                                ExportShare.share(context, "ride_history.csv", csv, "text/csv")
                            }
                        })
                    }
                    else -> {}
                }
            },
            trailing = {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(OrSpacing.lg),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    MiniPlayer()
                    SensorStatus(offline = sensorsOffline)
                    HeartRateStatus(
                        paired = activeProfile?.pairedHrDeviceAddress != null,
                        state = heartRateState,
                        bpm = heartRateBpm,
                    )
                    // The rider's own name switches rider (rider's ask, 2026-10-21): straight to the
                    // picker, which leaves the tabs; picking anyone, them included, comes back.
                    RiderChip(profile = activeProfile, onClick = {
                        profileViewModel.switchRider()
                        outerNavController.navigate(Destinations.ProfileSelect) {
                            popUpTo(Destinations.Main) { inclusive = true }
                        }
                    })
                }
            },
        )
        AppNotices(
            sensorsOffline = sensorsOffline == true,
            updateVersionName = availableUpdate?.versionName?.takeUnless { updateBannerDismissed },
            onOpenUpdate = { outerNavController.navigate(Destinations.AppUpdate) },
            onDismissUpdate = { appContainer.dismissUpdateBanner() },
        )
        NavHost(
            navController = innerNavController,
            startDestination = TopLevelDestination.Start.route,
            modifier = Modifier.weight(1f).fillMaxWidth(),
            // No transitions (rider, 2026-10-21): the default cross-fade left the old tab's
            // top-bar actions showing mid-fade and felt inconsistent.
            enterTransition = { EnterTransition.None },
            exitTransition = { ExitTransition.None },
            popEnterTransition = { EnterTransition.None },
            popExitTransition = { ExitTransition.None },
        ) {
            composable(MainTabs.Home) {
                HomeRoute(
                    viewModel = homeViewModel,
                    onQuickStart = { outerNavController.navigate(Destinations.InRide) },
                    onOpenGames = { launchGames(context) },
                )
            }
            composable(MainTabs.Classes) {
                ClassesRoute(
                    viewModel = classesViewModel,
                    onStartVideoRide = { videoId ->
                        outerNavController.navigate(Destinations.videoRide(videoId))
                    },
                    onOpenCreator = { sourceId ->
                        outerNavController.navigate(Destinations.creator(sourceId))
                    },
                )
            }
            composable(MainTabs.Games) {
                // A launcher: the Games hub inside Godot holds the picker, circuits and settings.
                val saving by appContainer.gameVisitManager.saving.collectAsState()
                GamesLauncherScreen(saving = saving, onEnter = { launchGames(context) })
            }
            composable(MainTabs.History) {
                HistoryRoute(
                    viewModel = historyViewModel,
                    onRideSelected = { rideId ->
                        outerNavController.navigate(Destinations.rideSummary(rideId))
                    },
                )
            }
            composable(MainTabs.Profile) {
                ProfileTabScreen(
                    viewModel = profileViewModel,
                    activeProfile = activeProfile,
                    onEditProfile = { outerNavController.navigate(Destinations.ProfileEdit) },
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
                    onManageControllers = { outerNavController.navigate(Destinations.Controllers) },
                    bikeSource = bikeSource,
                    onManageBikeSource = { outerNavController.navigate(Destinations.BikeSource) },
                    controllers = controllerStatuses,
                    onManageAppUpdates = { outerNavController.navigate(Destinations.AppUpdate) },
                    onManageContentSources = {
                        outerNavController.navigate(Destinations.ContentSources)
                    },
                    routeHolder = appContainer.routeHolder,
                    musicApp = remember(defaultMusicApp) { defaultMusicApp?.let { MusicApps.find(context, it) } },
                    onMusicAppChosen = { appContainer.nowPlaying.setDefaultApp(it.packageName) },
                    musicControlsOn = musicControlsOn,
                    onManageMusicControls = {
                        openMusicAccessSettings(context, appContainer.nowPlaying.listenerComponent)
                    },
                )
            }
        }
        OrNavBar {
            TopLevelDestination.entries.forEach { destination ->
                OrNavBarItem(
                    label = destination.label,
                    icon = destination.icon,
                    emoji = destination.emoji,
                    selected = currentRoute == destination.route,
                    onClick = { navigateToTab(destination.route) },
                )
            }
        }
    }
}
