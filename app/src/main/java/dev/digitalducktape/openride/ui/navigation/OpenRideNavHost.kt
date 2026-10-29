package dev.digitalducktape.openride.ui.navigation

import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import dev.digitalducktape.openride.AppContainer
import dev.digitalducktape.openride.BuildConfig
import dev.digitalducktape.openride.games.session.VisitDestination
import dev.digitalducktape.openride.viewModelFactory
import dev.digitalducktape.openride.ui.creator.CreatorRoute
import dev.digitalducktape.openride.ui.creator.CreatorViewModel
import dev.digitalducktape.openride.ui.sources.ContentSourcesRoute
import dev.digitalducktape.openride.ui.sources.ContentSourcesViewModel
import dev.digitalducktape.openride.ui.update.UpdateRoute
import dev.digitalducktape.openride.ui.update.UpdateViewModel
import dev.digitalducktape.openride.ui.main.MainScaffold
import dev.digitalducktape.openride.ui.profile.ProfileEditorRoute
import dev.digitalducktape.openride.ui.profile.ProfileEditorViewModel
import dev.digitalducktape.openride.ui.profile.ProfileSelectRoute
import dev.digitalducktape.openride.ui.profile.ProfileSelectViewModel
import dev.digitalducktape.openride.ui.profile.ControllersRoute
import dev.digitalducktape.openride.ui.profile.ControllersViewModel
import dev.digitalducktape.openride.ui.profile.HrPairingRoute
import dev.digitalducktape.openride.ui.profile.HrPairingViewModel
import dev.digitalducktape.openride.ui.ride.InRideScreen
import dev.digitalducktape.openride.ui.ride.InRideViewModel
import dev.digitalducktape.openride.ui.ride.VideoRideScreen
import dev.digitalducktape.openride.ui.ride.RideSummaryRoute
import dev.digitalducktape.openride.ui.ride.RideSummaryViewModel

/**
 * The app's single outer [androidx.navigation.NavHost] (T11). Start destination is profile
 * select (PRD P0-8: fresh launch always lands there). [Destinations.Main] hosts its own
 * nested tab graph (see [MainScaffold]) so starting/ending a ride and switching riders can
 * push/pop that whole tabbed section as one unit.
 */
@Composable
fun OpenRideNavHost(appContainer: AppContainer) {
    val navController = rememberNavController()

    // After a games visit (consume once): its ride summary, or the profile editor for the FTP nudge.
    val visitDestination by appContainer.visitNavigator.pending.collectAsState()
    LaunchedEffect(visitDestination) {
        val destination = visitDestination ?: return@LaunchedEffect
        when (destination) {
            is VisitDestination.RideSummary -> navController.navigate(Destinations.rideSummary(destination.rideId))
            VisitDestination.EditProfile -> navController.navigate(Destinations.ProfileEdit)
        }
        appContainer.visitNavigator.consume(destination)
    }

    NavHost(
        navController = navController,
        startDestination = Destinations.ProfileSelect,
        // No transitions anywhere, as in the tabs (MainScaffold).
        enterTransition = { EnterTransition.None },
        exitTransition = { ExitTransition.None },
        popEnterTransition = { EnterTransition.None },
        popExitTransition = { ExitTransition.None },
    ) {
        composable(Destinations.ProfileSelect) {
            val viewModel: ProfileSelectViewModel = viewModel(
                factory = viewModelFactory {
                    ProfileSelectViewModel(appContainer.profileRepository, appContainer.activeProfileHolder)
                },
            )
            ProfileSelectRoute(
                viewModel = viewModel,
                onProfileSelected = {
                    navController.navigate(Destinations.Main) {
                        popUpTo(Destinations.ProfileSelect) { inclusive = true }
                    }
                },
                onAddRider = { navController.navigate(Destinations.ProfileCreate) },
            )
        }

        composable(Destinations.ProfileCreate) {
            val viewModel: ProfileEditorViewModel = viewModel(
                factory = viewModelFactory {
                    ProfileEditorViewModel(appContainer.profileRepository, appContainer.activeProfileHolder)
                },
            )
            ProfileEditorRoute(
                viewModel = viewModel,
                avatarPhotoStore = appContainer.avatarPhotoStore,
                title = "Add rider",
                onSaved = {
                    navController.navigate(Destinations.Main) {
                        popUpTo(Destinations.ProfileSelect) { inclusive = true }
                    }
                },
                onCancel = { navController.popBackStack() },
            )
        }

        composable(Destinations.ProfileEdit) {
            val viewModel: ProfileEditorViewModel = viewModel(
                factory = viewModelFactory {
                    ProfileEditorViewModel(
                        appContainer.profileRepository,
                        appContainer.activeProfileHolder,
                        editActiveProfile = true,
                    )
                },
            )
            ProfileEditorRoute(
                viewModel = viewModel,
                avatarPhotoStore = appContainer.avatarPhotoStore,
                title = "Edit profile",
                onSaved = { navController.popBackStack() },
                onCancel = { navController.popBackStack() },
            )
        }

        composable(Destinations.Main) {
            MainScaffold(appContainer = appContainer, outerNavController = navController)
        }

        composable(Destinations.HrPairing) {
            val viewModel: HrPairingViewModel = viewModel(
                factory = viewModelFactory {
                    HrPairingViewModel(
                        appContainer.bleScanner,
                        appContainer.profileRepository,
                        appContainer.activeProfileHolder,
                        appContainer.heartRateManager,
                    )
                },
            )
            HrPairingRoute(
                viewModel = viewModel,
                onDone = { navController.popBackStack() },
            )
        }

        composable(Destinations.Controllers) {
            val viewModel: ControllersViewModel = viewModel(
                factory = viewModelFactory {
                    ControllersViewModel(
                        appContainer.controllerScanner,
                        appContainer.controllerStore,
                        appContainer.controllerManager.statuses,
                        appContainer.controllerManager.lastPress,
                    )
                },
            )
            ControllersRoute(
                viewModel = viewModel,
                onDone = { navController.popBackStack() },
            )
        }

        composable(Destinations.AppUpdate) {
            val viewModel: UpdateViewModel = viewModel(
                factory = viewModelFactory {
                    UpdateViewModel(
                        appContainer.updateRepository,
                        currentVersionCode = BuildConfig.VERSION_CODE,
                        currentVersionName = BuildConfig.VERSION_NAME,
                        assetInfix = BuildConfig.UPDATE_APK_ASSET_INFIX,
                    )
                },
            )
            UpdateRoute(
                viewModel = viewModel,
                onDone = { navController.popBackStack() },
            )
        }

        composable(Destinations.ContentSources) {
            val viewModel: ContentSourcesViewModel = viewModel(
                factory = viewModelFactory {
                    ContentSourcesViewModel(
                        appContainer.contentSourceRepository,
                        appContainer.channelHandleResolver,
                    )
                },
            )
            ContentSourcesRoute(
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
            )
        }

        composable(Destinations.InRide) {
            val viewModel: InRideViewModel = viewModel(
                factory = viewModelFactory {
                    InRideViewModel(
                        appContainer.rideSessionManager,
                        appContainer.bikeDataSource,
                        appContainer.profileRepository,
                        appContainer.activeProfileHolder,
                        appContainer.heartRateManager,
                        appContainer.routeHolder,
                        sensorsOffline = appContainer.sensorsOffline,
                    )
                },
            )
            InRideScreen(
                viewModel = viewModel,
                onRideEnded = { rideId ->
                    navController.navigate(Destinations.rideSummary(rideId)) {
                        popUpTo(Destinations.Main) { inclusive = false }
                        launchSingleTop = true
                    }
                },
            )
        }

        composable(
            route = Destinations.VideoRide,
            arguments = listOf(navArgument(Destinations.VideoIdArg) { type = NavType.StringType }),
        ) { backStackEntry ->
            val videoId = backStackEntry.arguments?.getString(Destinations.VideoIdArg).orEmpty()
            val viewModel: InRideViewModel = viewModel(
                factory = viewModelFactory {
                    InRideViewModel(
                        appContainer.rideSessionManager,
                        appContainer.bikeDataSource,
                        appContainer.profileRepository,
                        appContainer.activeProfileHolder,
                        appContainer.heartRateManager,
                        appContainer.routeHolder,
                        sensorsOffline = appContainer.sensorsOffline,
                    )
                },
            )
            VideoRideScreen(
                viewModel = viewModel,
                videoId = videoId,
                onRideEnded = { rideId ->
                    navController.navigate(Destinations.rideSummary(rideId)) {
                        popUpTo(Destinations.Main) { inclusive = false }
                        launchSingleTop = true
                    }
                },
            )
        }

        composable(
            route = Destinations.Creator,
            arguments = listOf(navArgument(Destinations.SourceIdArg) { type = NavType.LongType }),
        ) { backStackEntry ->
            val sourceId = backStackEntry.arguments?.getLong(Destinations.SourceIdArg) ?: 0L
            val viewModel: CreatorViewModel = viewModel(
                key = "creator_$sourceId",
                factory = viewModelFactory {
                    CreatorViewModel(
                        appContainer.contentRepository,
                        appContainer.rideSessionManager,
                        appContainer.activeProfileHolder,
                        appContainer.rideRepository,
                        sourceId,
                    )
                },
            )
            CreatorRoute(
                viewModel = viewModel,
                onStartVideoRide = { videoId ->
                    navController.navigate(Destinations.videoRide(videoId))
                },
                onBack = { navController.popBackStack() },
            )
        }

        composable(
            route = Destinations.RideSummary,
            arguments = listOf(navArgument(Destinations.RideIdArg) { type = NavType.LongType }),
        ) { backStackEntry ->
            val rideId = backStackEntry.arguments?.getLong(Destinations.RideIdArg) ?: 0L
            val viewModel: RideSummaryViewModel = viewModel(
                key = "ride_summary_$rideId",
                factory = viewModelFactory {
                    RideSummaryViewModel(
                        appContainer.rideRepository,
                        appContainer.profileRepository,
                        appContainer.rideSessionManager,
                        rideId,
                    )
                },
            )
            RideSummaryRoute(
                viewModel = viewModel,
                onDismiss = { navController.popBackStack() },
            )
        }
    }
}
