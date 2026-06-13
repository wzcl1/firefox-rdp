FROM debian:bookworm-slim

ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    RDP_USER=browser \
    FIREFOX_START_URL=about:blank \
    FIREFOX_ARGS="" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

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
    && if [ "$TARGETARCH" = "arm64" ]; then FIREFOX_ARCH="linux64-aarch64"; else FIREFOX_ARCH="linux64"; fi \
    && wget -O /tmp/firefox.tar.xz "https://download.mozilla.org/?product=firefox-latest-ssl&os=${FIREFOX_ARCH}&lang=en-US" \
    && tar -xJf /tmp/firefox.tar.xz -C /opt \
    && ln -s /opt/firefox/firefox /usr/local/bin/firefox \
    && rm -f /tmp/firefox.tar.xz \
     && printf '%s\n' '{"policies":{"DisableTelemetry":true,"DisableFirefoxStudies":true,"DisableFeedbackCommands":true,"DisableFirefoxAccounts":true,"NetworkPrediction":false,"NoDefaultBookmarks":true,"PasswordManagerEnabled":false,"OfferToSaveLogins":false,"RequestedLocales":["en-US"],"SkipTermsOfUse":true,"DontCheckDefaultBrowser":true,"HardwareAcceleration":false,"BackgroundAppUpdate":false,"AppAutoUpdate":false,"ExtensionUpdate":false,"DisableSystemAddonUpdate":true,"DisableDeveloperTools":true,"DisableSetDesktopBackground":true,"DisableBuiltinPDFViewer":false,"DisableFormHistory":true,"OverrideFirstRunPage":"","OverridePostUpdatePage":"","FirefoxHome":{"Search":false,"TopSites":false,"SponsoredTopSites":false,"Highlights":false,"Pocket":false,"SponsoredPocket":false,"Snippets":false,"Locked":true},"UserMessaging":{"ExtensionRecommendations":false,"FeatureRecommendations":false,"UrlbarInterventions":false,"SkipOnboarding":true,"MoreFromMozilla":false,"FirefoxLabs":false,"Locked":true},"Homepage":{"URL":"about:blank","Locked":true,"StartPage":"homepage"},"ExtensionSettings":{"uBlock0@raymondhill.net":{"installation_mode":"force_installed","install_url":"https://addons.mozilla.org/firefox/downloads/latest/uBlock0@raymondhill.net.xpi"}},"VisualSearchEnabled":false,"TranslateEnabled":false,"PictureInPicture":{"Enabled":false,"Locked":true},"PrintingEnabled":false,"XSLTEnabled":false,"SearchSuggestEnabled":false,"FirefoxSuggest":{"WebSuggestions":false,"SponsoredSuggestions":false,"ImproveSuggest":false,"Locked":true},"GoToIntranetSiteForSingleWordEntryInAddressBar":false,"IPProtectionAvailable":false,"PostQuantumKeyAgreementEnabled":false,"DisableEncryptedClientHello":true,"DNSOverHTTPS":{"Enabled":false,"Locked":true},"EnableTrackingProtection":{"Value":false,"Locked":true}}}' > /opt/firefox/distribution/policies.json \
    && rm -rf /opt/firefox/crashreporter /opt/firefox/crashhelper /opt/firefox/pingsender /opt/firefox/updater /opt/firefox/updater.ini /opt/firefox/update-settings.ini /opt/firefox/vaapitest /opt/firefox/glxtest \
    && apt-get purge -y --auto-remove wget xz-utils \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc /usr/share/man /usr/share/info /usr/share/locale /usr/share/icons/Adwaita /usr/share/poppler /usr/share/ghostscript \
    && adduser xrdp ssl-cert

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY rdp-session.sh /usr/local/bin/rdp-session.sh
COPY rdp-watchdog.sh /usr/local/bin/rdp-watchdog.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/rdp-session.sh /usr/local/bin/rdp-watchdog.sh \
    && printf '#!/bin/sh\nexec /usr/local/bin/rdp-session.sh\n' > /etc/xrdp/startwm.sh \
    && chmod +x /etc/xrdp/startwm.sh \
    && sed -i 's/^port=3389/port=tcp:\/\/:3389/' /etc/xrdp/xrdp.ini

EXPOSE 3389

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
