package dev.digitalducktape.openride.ui.classes

/**
 * Builds the host page for the in-app class player (superseding the earlier intent-based
 * handoff): a full-viewport YouTube embed on the privacy-enhanced
 * `youtube-nocookie.com` domain, driven through YouTube's official IFrame Player API so the
 * app can keep the video in step with the ride:
 *
 * - `openridePause()` / `openrideResume()` (called from the WebView via `evaluateJavascript`)
 *   pause/resume playback when the *ride* pauses — whether from the Pause button or the
 *   freewheel auto-pause.
 * - `openrideSetMuted(true|false)` silences or restores the class's own audio (#72) through the
 *   player's `mute()` / `unMute()`, so a rider can listen to their own music instead. The
 *   picture, the ride's pause/resume and the end-of-class finish are untouched.
 * - When the player reaches ENDED, the page notifies the app through the injected
 *   `OpenRideBridge` JavaScript interface so the workout can finish automatically.
 *
 * ToS constraints (PRD Non-Goal #5) still shape the parameters: YouTube's own player chrome
 * stays enabled (`"controls": 1`), playback control goes through the official player API
 * only, and nothing is ever downloaded or cached — the WebView streams from YouTube's player
 * exactly like a browser would.
 */
object YouTubeEmbed {

    /** Base URL handed to `WebView.loadDataWithBaseURL` so the embed runs in a real
     *  https origin (required for YouTube's player to allow playback). */
    const val BASE_URL = "https://www.youtube-nocookie.com"

    /** Name of the JavaScript interface the hosting WebView injects (see VideoRideScreen);
     *  the page calls `OpenRideBridge.onVideoEnded()` when playback completes. */
    const val BRIDGE_NAME = "OpenRideBridge"

    /** YouTube video ids are URL-safe by construction; anything else is rejected outright
     *  rather than escaped, since a non-matching id can only be a bug or an injection. */
    private val VIDEO_ID = Regex("^[A-Za-z0-9_-]{5,20}$")

    fun html(videoId: String): String {
        require(VIDEO_ID.matches(videoId)) { "Not a YouTube video id: $videoId" }
        return """
            <!doctype html>
            <html>
            <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
              html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
              #player { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
            </style>
            </head>
            <body>
            <div id="player"></div>
            <script>
              var player = null;
              // The ride can pause before the player finishes bootstrapping; remember the
              // latest requested state and apply it in onReady.
              var wantPaused = false;
              // Likewise the rider's mute choice (#72).
              var wantMuted = false;

              function onYouTubeIframeAPIReady() {
                player = new YT.Player('player', {
                  host: '$BASE_URL',
                  videoId: '$videoId',
                  playerVars: { "autoplay": 1, "playsinline": 1, "controls": 1, "rel": 0, "modestbranding": 1 },
                  events: {
                    onReady: function (e) {
                      if (wantMuted) { e.target.mute(); }
                      if (wantPaused) { e.target.pauseVideo(); } else { e.target.playVideo(); }
                    },
                    onStateChange: function (e) {
                      if (e.data === YT.PlayerState.ENDED && window.$BRIDGE_NAME) {
                        window.$BRIDGE_NAME.onVideoEnded();
                      }
                    }
                  }
                });
              }

              function openridePause() {
                wantPaused = true;
                if (player && player.pauseVideo) { player.pauseVideo(); }
              }

              function openrideSetMuted(muted) {
                wantMuted = muted;
                if (player && player.mute) { if (muted) { player.mute(); } else { player.unMute(); } }
              }

              function openrideResume() {
                wantPaused = false;
                if (player && player.playVideo) { player.playVideo(); }
              }

              var tag = document.createElement('script');
              tag.src = 'https://www.youtube.com/iframe_api';
              document.body.appendChild(tag);
            </script>
            </body>
            </html>
        """.trimIndent()
    }

    /** The call that mutes or unmutes the class's audio (#72), for `WebView.evaluateJavascript`. */
    fun muteScript(muted: Boolean): String = "openrideSetMuted($muted)"

    /** The mute button's label: what a tap does next. */
    fun muteLabel(muted: Boolean): String = if (muted) "Unmute class" else "Mute class"
}
