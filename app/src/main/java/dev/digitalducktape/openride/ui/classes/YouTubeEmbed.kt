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
 * - `openrideSetMuted(true|false)` silences or restores the class's own audio (#72), so a rider
 *   can listen to their own music instead. Muting rebuilds the player at the same second with
 *   `mute: 1`, rather than calling `mute()`: Android gives the sound to one app at a time, and
 *   the WebView only stays out of that when its video has been silent from its first frame. A
 *   video muted part-way keeps its claim, so the rider's music app starting would pause the
 *   class (bike test, 2026-11-11). Unmuting is `unMute()`, which takes the sound back from the
 *   music app, as starting any class does.
 * - When the player reaches ENDED, the page notifies the app through the injected
 *   `OpenRideBridge` JavaScript interface so the workout can finish automatically.
 *
 * The bike tablet can't keep up with YouTube's default pick (#73), so [H264_PREFERENCE_SCRIPT]
 * has the page report the codecs it decodes badly as unsupported, the way a browser without
 * them would. YouTube then chooses the stream itself, as it always does, and its own quality
 * menu (the player's gear) still works for a rider who wants to pick by hand.
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

              // Whether the player on screen was built silent, the only kind of silence
              // that lets the rider's music play alongside.
              var builtMuted = false;

              function buildPlayer(startSec) {
                builtMuted = wantMuted;
                player = new YT.Player('player', {
                  host: '$BASE_URL',
                  videoId: '$videoId',
                  playerVars: {
                    "autoplay": 1, "playsinline": 1, "controls": 1, "rel": 0, "modestbranding": 1,
                    "mute": wantMuted ? 1 : 0, "start": Math.floor(startSec)
                  },
                  events: {
                    onReady: function (e) {
                      // Muted while this player was still loading: start over, silent.
                      if (wantMuted && !builtMuted) { rebuildPlayer(); return; }
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

              function rebuildPlayer() {
                var at = player.getCurrentTime ? player.getCurrentTime() : 0;
                player.destroy();
                buildPlayer(at);
              }

              function onYouTubeIframeAPIReady() { buildPlayer(0); }

              function openridePause() {
                wantPaused = true;
                if (player && player.pauseVideo) { player.pauseVideo(); }
              }

              function openrideSetMuted(muted) {
                if (muted === wantMuted) { return; }
                wantMuted = muted;
                // A player still loading picks the choice up in onReady.
                if (!player || !player.getCurrentTime) { return; }
                if (muted) { rebuildPlayer(); } else { player.unMute(); }
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

    /**
     * Where [H264_PREFERENCE_SCRIPT] runs: the host page and the player's iframe (both on
     * [BASE_URL]), and `youtube.com` should the player ever be served from there.
     */
    val PLAYER_ORIGINS: Set<String> = setOf(BASE_URL, "https://www.youtube.com")

    /**
     * Makes YouTube send H.264 (#73). Run at document start in the player's frame, before
     * YouTube's player asks what the device can play, it answers "no" for VP8, VP9 and AV1
     * through the three ways a page can ask: `MediaSource.isTypeSupported`,
     * `HTMLMediaElement.canPlayType` and `navigator.mediaCapabilities.decodingInfo`.
     *
     * Why: measured on a Gen 2 bike (MT8173, 2026-11-11) with a 1080p60 scenic ride and 30-70
     * Mbps to spare. Left alone, YouTube picked VP9 1080p60, the tablet dropped about 40% of its
     * frames, and the player stepped down to 720p and then 480p30 within 45 seconds. With this
     * script it played H.264 at 720p60 dropping about 2%. The original Bike has no hardware VP9
     * decoder at all (the issue's report). H.264 tops out at 1080p, which is the screen.
     */
    val H264_PREFERENCE_SCRIPT: String = """
        (function () {
          if (window.__openrideH264) { return; }
          window.__openrideH264 = true;
          var avoid = /vp0?9|vp8|av01/i;
          var ms = window.MediaSource;
          if (ms && ms.isTypeSupported) {
            var isTypeSupported = ms.isTypeSupported.bind(ms);
            ms.isTypeSupported = function (type) { return !avoid.test(String(type)) && isTypeSupported(type); };
          }
          var canPlayType = HTMLMediaElement.prototype.canPlayType;
          HTMLMediaElement.prototype.canPlayType = function (type) {
            return avoid.test(String(type)) ? '' : canPlayType.call(this, type);
          };
          var mc = navigator.mediaCapabilities;
          if (mc && mc.decodingInfo) {
            var decodingInfo = mc.decodingInfo.bind(mc);
            mc.decodingInfo = function (config) {
              if (config && config.video && avoid.test(String(config.video.contentType))) {
                return Promise.resolve({ supported: false, smooth: false, powerEfficient: false });
              }
              return decodingInfo(config);
            };
          }
        })();
    """.trimIndent()
}
