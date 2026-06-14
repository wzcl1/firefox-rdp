FROM debian:bookworm-slim

# Security note: The entrypoint process (xrdp/xrdp-sesman) must run as root
# because Debian's xrdp packages require root to:
#   - Create and manage virtual X11 displays (:10, :11, ...) via Xvnc/Xorgxrdp
#   - Spawn session processes as the authenticated RDP_USER
#   - Write to /var/run/xrdp/ for PID and socket files
# Session processes (Firefox, Openbox) run as the unprivileged RDP_USER.
# The docker-compose.yml applies defense-in-depth: cap_drop ALL,
# and only restores the minimum capabilities xrdp requires.

ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    RDP_USER=browser \
    FIREFOX_START_URL=about:blank \
    FIREFOX_ARGS="" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Layer 1: system packages (rarely changes)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        dbus-x11 \
        fonts-dejavu \
        fonts-liberation \
        libasound2 \
        libdbus-glib-1-2 \
        libgtk-3-0 \
        libpulse0 \
        libxt6 \
        iproute2 \
        openbox \
        procps \
        pulseaudio-utils \
        tini \
        wget \
        x11-xserver-utils \
        xauth \
        xdg-utils \
        x11-utils \
        xz-utils \
        xorgxrdp \
        xrdp \
    && rm -rf /var/lib/apt/lists/*

# Layer 2: Firefox + uBlock (rarely changes, ~250MB cached)
RUN if [ "$TARGETARCH" = "arm64" ]; then FIREFOX_ARCH="linux64-aarch64"; else FIREFOX_ARCH="linux64"; fi \
    && wget -O /tmp/firefox.tar.xz "https://download.mozilla.org/?product=firefox-latest-ssl&os=${FIREFOX_ARCH}&lang=en-US" \
    && tar -xJf /tmp/firefox.tar.xz -C /opt \
    && ln -s /opt/firefox/firefox /usr/local/bin/firefox \
    && rm -f /tmp/firefox.tar.xz \
    && mkdir -p /opt/firefox/distribution/extensions \
    && UBLOCK_URL=$(wget -qO- https://api.github.com/repos/gorhill/uBlock/releases/latest \
         | grep "browser_download_url.*firefox.signed.xpi" \
         | head -1 | cut -d'"' -f4) \
     && if [ -z "$UBLOCK_URL" ]; then echo "ERROR: failed to resolve uBlock Origin download URL" >&2; exit 1; fi \
     && wget -O "/opt/firefox/distribution/extensions/uBlock0@raymondhill.net.xpi" "$UBLOCK_URL" \
     && printf '%s\n' '{"policies":{"DisableTelemetry":true,"DisableFirefoxStudies":true,"DisableFeedbackCommands":true,"DisableFirefoxAccounts":true,"NetworkPrediction":false,"NoDefaultBookmarks":true,"PasswordManagerEnabled":false,"OfferToSaveLogins":false,"RequestedLocales":["en-US"],"SkipTermsOfUse":true,"DontCheckDefaultBrowser":true,"HardwareAcceleration":false,"BackgroundAppUpdate":false,"AppAutoUpdate":false,"ExtensionUpdate":false,"DisableSystemAddonUpdate":true,"DisableDeveloperTools":true,"DisableSetDesktopBackground":true,"DisableBuiltinPDFViewer":false,"DisableFormHistory":true,"OverrideFirstRunPage":"","OverridePostUpdatePage":"","FirefoxHome":{"Search":false,"TopSites":false,"SponsoredTopSites":false,"Highlights":false,"Pocket":false,"SponsoredPocket":false,"Snippets":false,"Locked":true},"UserMessaging":{"ExtensionRecommendations":false,"FeatureRecommendations":false,"UrlbarInterventions":false,"SkipOnboarding":true,"MoreFromMozilla":false,"FirefoxLabs":false,"Locked":true},"Homepage":{"URL":"about:blank","Locked":true,"StartPage":"homepage"},"ExtensionSettings":{"uBlock0@raymondhill.net":{"installation_mode":"force_installed","install_url":"file:///opt/firefox/distribution/extensions/uBlock0@raymondhill.net.xpi"}},"VisualSearchEnabled":false,"TranslateEnabled":false,"PictureInPicture":{"Enabled":false,"Locked":true},"PrintingEnabled":false,"XSLTEnabled":false,"SearchSuggestEnabled":false,"FirefoxSuggest":{"WebSuggestions":false,"SponsoredSuggestions":false,"ImproveSuggest":false,"Locked":true},"GoToIntranetSiteForSingleWordEntryInAddressBar":false,"IPProtectionAvailable":false,"PostQuantumKeyAgreementEnabled":false,"DisableEncryptedClientHello":false,"DNSOverHTTPS":{"Enabled":true,"Locked":true},"EnableTrackingProtection":{"Value":false,"Locked":true}}}' > /opt/firefox/distribution/policies.json \
    && mkdir -p /opt/firefox/defaults/pref \
    && printf 'pref("security.sandbox.warn_for_disabled_sandbox", false); pref("security.sandbox.content.level", 1);\n' > /opt/firefox/defaults/pref/sandbox-prefs.js \
    && rm -rf /opt/firefox/crashreporter /opt/firefox/crashhelper /opt/firefox/pingsender /opt/firefox/updater /opt/firefox/updater.ini /opt/firefox/update-settings.ini /opt/firefox/vaapitest /opt/firefox/glxtest \
    && apt-get purge -y --auto-remove wget xz-utils \
    && rm -rf /tmp/* /var/tmp/*

# Layer 3: user creation (rarely changes)
# chmod 733 allows container UID 0 to write in rootless Docker where
# UID 0 ≠ real root and can't bypass file permissions on named volumes.
RUN adduser xrdp ssl-cert \
    && addgroup --gid 1000 browser \
    && adduser --disabled-password --gecos "" --uid 1000 --ingroup browser --shell /bin/bash browser \
    && mkdir -p /home/browser/.config/openbox \
    && chmod 733 /home/browser /home/browser/.config /home/browser/.config/openbox

# Layer 4: scripts + xrdp config (changes most often — only this layer rebuilds)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY rdp-session.sh /usr/local/bin/rdp-session.sh
COPY rdp-watchdog.sh /usr/local/bin/rdp-watchdog.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/rdp-session.sh /usr/local/bin/rdp-watchdog.sh \
    && sed -i 's/\r$//' /usr/local/bin/rdp-session.sh \
    && printf '#!/bin/sh\nexec /usr/local/bin/rdp-session.sh\n' > /etc/xrdp/startwm.sh \
    && chmod +x /etc/xrdp/startwm.sh \
    && sed -i 's/^port=3389/port=tcp:\/\/:3389/' /etc/xrdp/xrdp.ini

EXPOSE 3389

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ss -tln state listening sport :3389 >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
