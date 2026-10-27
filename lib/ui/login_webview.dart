import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../domain/auth.dart';

InAppWebViewSettings webSettings({
  String? userAgent,
  bool desktopMode = true,
  bool isPopup = false,
}) => InAppWebViewSettings(
  javaScriptEnabled: true,
  domStorageEnabled: true,
  allowFileAccess: false,
  allowContentAccess: false,
  useShouldOverrideUrlLoading: true,
  userAgent:
      userAgent ??
      (desktopMode
          ? WebLoginTarget.desktopUserAgent
          : WebLoginTarget.mobileUserAgent),
  preferredContentMode: desktopMode
      ? UserPreferredContentMode.DESKTOP
      : UserPreferredContentMode.MOBILE,
  useWideViewPort: true,
  loadWithOverviewMode: desktopMode,
  mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
  thirdPartyCookiesEnabled: true,
  // WebView2 requires authorization windows to share the opener's InPrivate
  // profile. Android popups must avoid clearing the shared cookie jar again.
  incognito: !isPopup || defaultTargetPlatform == TargetPlatform.windows,
  cacheEnabled: false,
  saveFormData: false,
  supportZoom: true,
  builtInZoomControls: true,
  displayZoomControls: false,
  ignoresViewportScaleLimits: true,
);

// A desktop UA alone does not override a site's mobile viewport. Keep the main
// document wide and zoomable, including when an SPA replaces its viewport tag.
// Nested login/captcha frames keep the dimensions chosen by their parent page.
const desktopLoginViewportScript = r'''(() => {
  if (window.top !== window || location.protocol !== 'https:' ||
      window.__asterDesktopViewport) return;
  window.__asterDesktopViewport = true;
  const apply = () => {
    if (!document.head) return;
    const content = 'width=1280,minimum-scale=0.1,maximum-scale=8,user-scalable=yes';
    let tags = [...document.head.querySelectorAll('meta[name="viewport"]')];
    if (!tags.length) {
      const tag = document.createElement('meta');
      tag.name = 'viewport';
      document.head.appendChild(tag);
      tags = [tag];
    }
    for (const tag of tags) {
      if (tag.content !== content) tag.content = content;
    }
  };
  const install = () => {
    if (!document.head) return;
    apply();
    new MutationObserver(apply).observe(document.head, {
      childList: true, subtree: true, attributes: true,
      attributeFilter: ['name', 'content']
    });
  };
  if (document.head) install();
  else document.addEventListener('DOMContentLoaded', install, {once: true});
  window.addEventListener('hashchange', apply);
  window.addEventListener('popstate', apply);
})();''';

UserScript desktopLoginUserScript() => UserScript(
  source: desktopLoginViewportScript,
  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  forMainFrameOnly: true,
);
