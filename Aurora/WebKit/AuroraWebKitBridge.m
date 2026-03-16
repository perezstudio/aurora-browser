#include "AuroraWebKitBridge.h"
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <objc/runtime.h>
#include <objc/message.h>

// ---------------------------------------------------------------------------
// Dynamic symbol resolution
// ---------------------------------------------------------------------------
// WebKit2 C API symbols exist in WebKit.framework but are not in public headers.
// We load them at runtime via dlsym so the project compiles against the standard SDK.

static void *webkit_handle = NULL;

// Function pointer types matching WebKit2 C API signatures
typedef WKContextRef (*WKContextCreateFn)(void);
typedef void (*WKRetainReleaseFn)(const void *);
typedef WKPageConfigurationRef (*WKPageConfigurationCreateFn)(void);
typedef void (*WKPageConfigurationSetContextFn)(WKPageConfigurationRef, WKContextRef);
typedef WKPageGroupRef (*WKPageGroupCreateFn)(WKStringRef);
typedef void (*WKPageConfigurationSetPageGroupFn)(WKPageConfigurationRef, WKPageGroupRef);
typedef WKPreferencesRef (*WKPreferencesCreateFn)(void);
typedef void (*WKPreferencesSetBoolFn)(WKPreferencesRef, bool);
typedef void (*WKPageConfigurationSetPreferencesFn)(WKPageConfigurationRef, WKPreferencesRef);
typedef WKStringRef (*WKStringCreateFn)(const char *);
typedef size_t (*WKStringGetMaxUTF8Fn)(WKStringRef);
typedef size_t (*WKStringGetUTF8Fn)(WKStringRef, char *, size_t);
typedef WKURLRef (*WKURLCreateFn)(WKStringRef);
typedef WKStringRef (*WKURLCopyStringFn)(WKURLRef);
typedef void (*WKPageLoadURLFn)(WKPageRef, WKURLRef);
typedef void (*WKPageLoadHTMLStringFn)(WKPageRef, WKStringRef, WKURLRef);
typedef void (*WKPageGoBackFn)(WKPageRef);
typedef void (*WKPageGoForwardFn)(WKPageRef);
typedef void (*WKPageReloadFn)(WKPageRef);
typedef void (*WKPageStopLoadingFn)(WKPageRef);
typedef WKURLRef (*WKPageCopyActiveURLFn)(WKPageRef);
typedef WKStringRef (*WKPageCopyTitleFn)(WKPageRef);
typedef double (*WKPageGetEstimatedProgressFn)(WKPageRef);
typedef bool (*WKPageBoolFn)(WKPageRef);
typedef WKInspectorRef (*WKPageGetInspectorFn)(WKPageRef);
typedef void (*WKInspectorActionFn)(WKInspectorRef);
typedef bool (*WKInspectorBoolFn)(WKInspectorRef);

// Resolved function pointers
static WKContextCreateFn fn_WKContextCreate;
static WKRetainReleaseFn fn_WKRelease;

static WKPageConfigurationCreateFn fn_WKPageConfigurationCreate;
static WKPageConfigurationSetContextFn fn_WKPageConfigurationSetContext;

static WKPageGroupCreateFn fn_WKPageGroupCreateWithIdentifier;
static WKPageConfigurationSetPageGroupFn fn_WKPageConfigurationSetPageGroup;

static WKPreferencesCreateFn fn_WKPreferencesCreate;
static WKPreferencesSetBoolFn fn_WKPreferencesSetDeveloperExtrasEnabled;
static WKPageConfigurationSetPreferencesFn fn_WKPageConfigurationSetPreferences;

static WKStringCreateFn fn_WKStringCreateWithUTF8CString;
static WKStringGetMaxUTF8Fn fn_WKStringGetMaximumUTF8CStringSize;
static WKStringGetUTF8Fn fn_WKStringGetUTF8CString;

static WKURLCreateFn fn_WKURLCreateWithUTF8CString;
static WKURLCopyStringFn fn_WKURLCopyString;

static WKPageLoadURLFn fn_WKPageLoadURL;
static WKPageLoadHTMLStringFn fn_WKPageLoadHTMLString;
static WKPageGoBackFn fn_WKPageGoBack;
static WKPageGoForwardFn fn_WKPageGoForward;
static WKPageReloadFn fn_WKPageReload;
static WKPageStopLoadingFn fn_WKPageStopLoading;

static WKPageCopyActiveURLFn fn_WKPageCopyActiveURL;
static WKPageCopyTitleFn fn_WKPageCopyTitle;
static WKPageGetEstimatedProgressFn fn_WKPageGetEstimatedProgress;
static WKPageBoolFn fn_WKPageIsLoading;
static WKPageBoolFn fn_WKPageCanGoBack;
static WKPageBoolFn fn_WKPageCanGoForward;

static WKPageGetInspectorFn fn_WKPageGetInspector;
static WKInspectorActionFn fn_WKInspectorShow;
static WKInspectorActionFn fn_WKInspectorClose;
static WKInspectorActionFn fn_WKInspectorAttach;
static WKInspectorActionFn fn_WKInspectorDetach;
static WKInspectorBoolFn fn_WKInspectorIsVisible;
static WKInspectorBoolFn fn_WKInspectorIsAttached;

// Helper: load a required symbol
static void *load_sym(const char *name) {
    void *sym = dlsym(webkit_handle, name);
    if (!sym) {
        fprintf(stderr, "[AuroraBridge] WARNING: could not resolve %s\n", name);
    }
    return sym;
}

bool aurora_bridge_init(void) {
    if (webkit_handle) return true;

    webkit_handle = dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_LAZY);
    if (!webkit_handle) {
        fprintf(stderr, "[AuroraBridge] ERROR: could not open WebKit.framework: %s\n", dlerror());
        return false;
    }

    // Context
    fn_WKContextCreate = (WKContextCreateFn)load_sym("WKContextCreate");

    // Release
    fn_WKRelease = (WKRetainReleaseFn)load_sym("WKRelease");

    // Page configuration
    fn_WKPageConfigurationCreate = (WKPageConfigurationCreateFn)load_sym("WKPageConfigurationCreate");
    fn_WKPageConfigurationSetContext = (WKPageConfigurationSetContextFn)load_sym("WKPageConfigurationSetContext");

    // Page group + preferences
    fn_WKPageGroupCreateWithIdentifier = (WKPageGroupCreateFn)load_sym("WKPageGroupCreateWithIdentifier");
    fn_WKPageConfigurationSetPageGroup = (WKPageConfigurationSetPageGroupFn)load_sym("WKPageConfigurationSetPageGroup");
    fn_WKPreferencesCreate = (WKPreferencesCreateFn)load_sym("WKPreferencesCreate");
    fn_WKPreferencesSetDeveloperExtrasEnabled = (WKPreferencesSetBoolFn)load_sym("WKPreferencesSetDeveloperExtrasEnabled");
    fn_WKPageConfigurationSetPreferences = (WKPageConfigurationSetPreferencesFn)load_sym("WKPageConfigurationSetPreferences");

    // String / URL
    fn_WKStringCreateWithUTF8CString = (WKStringCreateFn)load_sym("WKStringCreateWithUTF8CString");
    fn_WKStringGetMaximumUTF8CStringSize = (WKStringGetMaxUTF8Fn)load_sym("WKStringGetMaximumUTF8CStringSize");
    fn_WKStringGetUTF8CString = (WKStringGetUTF8Fn)load_sym("WKStringGetUTF8CString");
    fn_WKURLCreateWithUTF8CString = (WKURLCreateFn)load_sym("WKURLCreateWithUTF8CString");
    fn_WKURLCopyString = (WKURLCopyStringFn)load_sym("WKURLCopyString");

    // Navigation
    fn_WKPageLoadURL = (WKPageLoadURLFn)load_sym("WKPageLoadURL");
    fn_WKPageLoadHTMLString = (WKPageLoadHTMLStringFn)load_sym("WKPageLoadHTMLString");
    fn_WKPageGoBack = (WKPageGoBackFn)load_sym("WKPageGoBack");
    fn_WKPageGoForward = (WKPageGoForwardFn)load_sym("WKPageGoForward");
    fn_WKPageReload = (WKPageReloadFn)load_sym("WKPageReload");
    fn_WKPageStopLoading = (WKPageStopLoadingFn)load_sym("WKPageStopLoading");

    // Page state
    fn_WKPageCopyActiveURL = (WKPageCopyActiveURLFn)load_sym("WKPageCopyActiveURL");
    fn_WKPageCopyTitle = (WKPageCopyTitleFn)load_sym("WKPageCopyTitle");
    fn_WKPageGetEstimatedProgress = (WKPageGetEstimatedProgressFn)load_sym("WKPageGetEstimatedProgress");
    fn_WKPageIsLoading = (WKPageBoolFn)load_sym("WKPageIsLoading");
    fn_WKPageCanGoBack = (WKPageBoolFn)load_sym("WKPageCanGoBack");
    fn_WKPageCanGoForward = (WKPageBoolFn)load_sym("WKPageCanGoForward");

    // Inspector
    fn_WKPageGetInspector = (WKPageGetInspectorFn)load_sym("WKPageGetInspector");
    fn_WKInspectorShow = (WKInspectorActionFn)load_sym("WKInspectorShow");
    fn_WKInspectorClose = (WKInspectorActionFn)load_sym("WKInspectorClose");
    fn_WKInspectorAttach = (WKInspectorActionFn)load_sym("WKInspectorAttach");
    fn_WKInspectorDetach = (WKInspectorActionFn)load_sym("WKInspectorDetach");
    fn_WKInspectorIsVisible = (WKInspectorBoolFn)load_sym("WKInspectorIsVisible");
    fn_WKInspectorIsAttached = (WKInspectorBoolFn)load_sym("WKInspectorIsAttached");

    // Verify critical symbols
    if (!fn_WKContextCreate || !fn_WKPageConfigurationCreate || !fn_WKPageLoadURL) {
        fprintf(stderr, "[AuroraBridge] ERROR: critical WebKit2 C API symbols not found\n");
        return false;
    }

    return true;
}

// ---------------------------------------------------------------------------
// Helper: WKString → C string (caller must free)
// ---------------------------------------------------------------------------
static char *wkstring_to_cstring(WKStringRef str) {
    if (!str || !fn_WKStringGetMaximumUTF8CStringSize || !fn_WKStringGetUTF8CString) {
        return NULL;
    }
    size_t maxLen = fn_WKStringGetMaximumUTF8CStringSize(str);
    if (maxLen == 0) return NULL;
    char *buf = (char *)malloc(maxLen);
    fn_WKStringGetUTF8CString(str, buf, maxLen);
    return buf;
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------
WKContextRef aurora_context_create(void) {
    if (!fn_WKContextCreate) return NULL;
    return fn_WKContextCreate();
}

void aurora_context_release(WKContextRef context) {
    if (fn_WKRelease && context) fn_WKRelease(context);
}

// ---------------------------------------------------------------------------
// Page configuration
// ---------------------------------------------------------------------------
WKPageConfigurationRef aurora_page_config_create(WKContextRef context) {
    if (!fn_WKPageConfigurationCreate || !fn_WKPageConfigurationSetContext) return NULL;

    WKPageConfigurationRef config = fn_WKPageConfigurationCreate();
    fn_WKPageConfigurationSetContext(config, context);

    // NOTE: Page group and preferences setup removed — the private API
    // function signatures may differ across macOS versions, causing crashes.
    // These will be added back once we validate the exact ABI.

    return config;
}

void aurora_page_config_release(WKPageConfigurationRef config) {
    if (fn_WKRelease && config) fn_WKRelease(config);
}

// ---------------------------------------------------------------------------
// Shared process pool cache — one pool per WKContextRef (i.e. per Profile).
// Sharing a pool across tabs in the same profile ensures cookies, sessions,
// and cached resources are visible to all tabs immediately.
// ---------------------------------------------------------------------------
static NSMutableDictionary *s_poolsByContext = nil;

// ---------------------------------------------------------------------------
// Per-profile stable UUID registry — maps WKContextRef → NSUUID (profile ID).
// Set by Swift via aurora_context_set_profile_uuid() so data stores persist
// across app launches using the same identifier.
// ---------------------------------------------------------------------------
static NSMutableDictionary *s_profileUUIDsByContext = nil;

void aurora_context_set_profile_uuid(WKContextRef context, const char *uuidString) {
    if (!context || !uuidString) return;
    if (!s_profileUUIDsByContext) {
        s_profileUUIDsByContext = [NSMutableDictionary new];
    }
    NSString *str = [NSString stringWithUTF8String:uuidString];
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:str];
    if (uuid) {
        NSValue *key = [NSValue valueWithPointer:context];
        s_profileUUIDsByContext[key] = uuid;
    }
}

// ---------------------------------------------------------------------------
// Per-profile data store cache — one WKWebsiteDataStore per WKContextRef.
// Each profile gets its own persistent data store keyed by the profile's
// stable UUID, providing full cookie/localStorage/indexedDB isolation
// that survives app restarts.
// ---------------------------------------------------------------------------
static NSMutableDictionary *s_dataStoresByContext = nil;

static id aurora_get_or_create_data_store(WKContextRef context) {
    Class dataStoreClass = objc_getClass("WKWebsiteDataStore");
    if (!dataStoreClass) return nil;

    if (!s_dataStoresByContext) {
        s_dataStoresByContext = [NSMutableDictionary new];
    }

    NSValue *key = [NSValue valueWithPointer:context];
    id store = s_dataStoresByContext[key];
    if (store) return store;

    // Look up the stable profile UUID registered by Swift
    NSUUID *profileUUID = s_profileUUIDsByContext ? s_profileUUIDsByContext[key] : nil;

    // Try to create a persistent data store with the profile UUID (macOS 14+)
    // This gives each profile its own on-disk cookie jar, localStorage, indexedDB, etc.
    SEL dataStoreForIdSel = sel_registerName("dataStoreForIdentifier:");
    if (profileUUID && [dataStoreClass respondsToSelector:dataStoreForIdSel]) {
        typedef id (*DataStoreForIdFn)(Class, SEL, id);
        store = ((DataStoreForIdFn)objc_msgSend)(dataStoreClass, dataStoreForIdSel, profileUUID);
        if (store) {
            s_dataStoresByContext[key] = store;
            return store;
        }
    }

    // Fallback: use nonPersistentDataStore for full isolation (data lost on quit,
    // but at least profiles won't leak cookies into each other)
    SEL nonPersistentSel = sel_registerName("nonPersistentDataStore");
    if ([dataStoreClass respondsToSelector:nonPersistentSel]) {
        typedef id (*NonPersistentFn)(Class, SEL);
        store = ((NonPersistentFn)objc_msgSend)(dataStoreClass, nonPersistentSel);
        if (store) {
            s_dataStoresByContext[key] = store;
            return store;
        }
    }

    return nil;
}

static id aurora_get_or_create_pool(WKContextRef context) {
    Class poolClass = objc_getClass("WKProcessPool");
    if (!poolClass) return nil;

    if (!s_poolsByContext) {
        s_poolsByContext = [NSMutableDictionary new];
    }

    NSValue *key = [NSValue valueWithPointer:context];
    id pool = s_poolsByContext[key];
    if (pool) return pool;

    // Try _WKProcessPoolConfiguration for additional control
    Class poolConfigClass = objc_getClass("_WKProcessPoolConfiguration");
    if (poolConfigClass) {
        id poolConfig = [[poolConfigClass alloc] init];

        // processSwapsOnNavigation = NO — keep same process for all navigations
        // within a tab (avoids re-triggering sandbox init on every navigation)
        SEL setPSONSel = sel_registerName("setProcessSwapsOnNavigation:");
        if ([poolConfig respondsToSelector:setPSONSel]) {
            typedef void (*SetBoolFn)(id, SEL, BOOL);
            ((SetBoolFn)objc_msgSend)(poolConfig, setPSONSel, NO);
        }

        // prewarmsProcessesAutomatically = YES — warm up WebContent process early
        SEL setPrewarmSel = sel_registerName("setPrewarmsProcessesAutomatically:");
        if ([poolConfig respondsToSelector:setPrewarmSel]) {
            typedef void (*SetBoolFn)(id, SEL, BOOL);
            ((SetBoolFn)objc_msgSend)(poolConfig, setPrewarmSel, YES);
        }

        // Create pool with configuration
        SEL initWithConfigSel = sel_registerName("_initWithConfiguration:");
        if ([poolClass instancesRespondToSelector:initWithConfigSel]) {
            pool = ((id(*)(id, SEL, id))objc_msgSend)([poolClass alloc], initWithConfigSel, poolConfig);
            // Pool created with _WKProcessPoolConfiguration
        }
    }

    if (!pool) {
        pool = [[poolClass alloc] init];
        // Pool created (default)
    }

    s_poolsByContext[key] = pool;
    return pool;
}

// ---------------------------------------------------------------------------
// User script: strip <source> elements for AVIF/WEBP from <picture> tags.
// The WebContent process sandbox prevents these codecs from decoding,
// so we force the browser to use PNG/JPEG/SVG fallbacks instead.
// ---------------------------------------------------------------------------
static NSString *const kImageCompatScript = @
    "(function(){"
    "  'use strict';"
    "  var unsupported = {'image/avif':1, 'image/webp':1};"
    "  function strip(root){"
    "    if(!root || !root.querySelectorAll) return;"
    "    var ss = root.querySelectorAll('picture > source');"
    "    for(var i=0;i<ss.length;i++){"
    "      if(unsupported[ss[i].getAttribute('type')]) ss[i].remove();"
    "    }"
    "  }"
    "  strip(document);"
    "  new MutationObserver(function(ms){"
    "    for(var i=0;i<ms.length;i++){"
    "      var added=ms[i].addedNodes;"
    "      for(var j=0;j<added.length;j++){"
    "        var n=added[j];"
    "        if(n.nodeType!==1) continue;"
    "        if(n.nodeName==='SOURCE' && n.parentNode && n.parentNode.nodeName==='PICTURE'){"
    "          if(unsupported[n.getAttribute('type')]) n.remove();"
    "        } else { strip(n); }"
    "      }"
    "    }"
    "  }).observe(document.documentElement||document,{childList:true,subtree:true});"
    "})();";

static void aurora_inject_user_scripts(id config) {
    SEL uccSel = sel_registerName("userContentController");
    if (![config respondsToSelector:uccSel]) return;
    id ucc = ((id(*)(id, SEL))objc_msgSend)(config, uccSel);
    if (!ucc) return;

    Class scriptClass = objc_getClass("WKUserScript");
    if (!scriptClass) return;

    // WKUserScriptInjectionTimeAtDocumentEnd = 1 (need DOM to exist)
    SEL initSel = sel_registerName("initWithSource:injectionTime:forMainFrameOnly:");
    if (![scriptClass instancesRespondToSelector:initSel]) return;

    id script = ((id(*)(id, SEL, id, NSInteger, BOOL))objc_msgSend)(
        [scriptClass alloc], initSel, kImageCompatScript, 1 /* AtDocumentEnd */, NO);

    SEL addScriptSel = sel_registerName("addUserScript:");
    if ([ucc respondsToSelector:addScriptSel]) {
        ((void(*)(id, SEL, id))objc_msgSend)(ucc, addScriptSel, script);
    }
}

// ---------------------------------------------------------------------------
// View creation — uses WKWebView via ObjC runtime (no import WebKit).
// WKView is broken on macOS 26+, so we use WKWebView and extract the
// internal WKPageRef via private SPI for C API page operations.
// Per-Space process isolation uses one shared WKProcessPool per context.
// ---------------------------------------------------------------------------

void *aurora_view_create_with_context(WKContextRef context) {
    Class WKWebViewClass = objc_getClass("WKWebView");
    Class configClass = objc_getClass("WKWebViewConfiguration");

    if (!WKWebViewClass || !configClass) {
        fprintf(stderr, "[AuroraBridge] ERROR: WKWebView or WKWebViewConfiguration class not found\n");
        return NULL;
    }

    @try {
        id config = [[configClass alloc] init];

        // Share process pool per Profile (context) for cookie/session sharing
        id pool = aurora_get_or_create_pool(context);
        if (pool) {
            SEL setPoolSel = sel_registerName("setProcessPool:");
            if ([config respondsToSelector:setPoolSel]) {
                typedef void (*SetPoolFn)(id, SEL, id);
                ((SetPoolFn)objc_msgSend)(config, setPoolSel, pool);
            }
        }

        // Set per-profile data store for full cookie/storage isolation
        id dataStore = aurora_get_or_create_data_store(context);
        if (dataStore) {
            SEL setDataStoreSel = sel_registerName("setWebsiteDataStore:");
            if ([config respondsToSelector:setDataStoreSel]) {
                typedef void (*SetStoreFn)(id, SEL, id);
                ((SetStoreFn)objc_msgSend)(config, setDataStoreSel, dataStore);
                // Per-profile data store set
            }
        }

        // Enable JavaScript and media playback on the preferences
        SEL prefsSel = sel_registerName("preferences");
        if ([config respondsToSelector:prefsSel]) {
            typedef id (*PrefsFn)(id, SEL);
            id prefs = ((PrefsFn)objc_msgSend)(config, prefsSel);
            if (prefs) {
                // Enable JavaScript
                SEL jsEnabledSel = sel_registerName("setJavaScriptEnabled:");
                if ([prefs respondsToSelector:jsEnabledSel]) {
                    typedef void (*SetBoolFn)(id, SEL, BOOL);
                    ((SetBoolFn)objc_msgSend)(prefs, jsEnabledSel, YES);
                }
                // Enable JavaScript markup (for inline event handlers etc.)
                SEL jsMarkupSel = sel_registerName("_setJavaScriptMarkupEnabled:");
                if ([prefs respondsToSelector:jsMarkupSel]) {
                    typedef void (*SetBoolFn)(id, SEL, BOOL);
                    ((SetBoolFn)objc_msgSend)(prefs, jsMarkupSel, YES);
                }
            }
        }

        // Set default webpage preferences to allow JavaScript
        SEL defaultPrefsSel = sel_registerName("setDefaultWebpagePreferences:");
        Class wpPrefsClass = objc_getClass("WKWebpagePreferences");
        if (wpPrefsClass && [config respondsToSelector:defaultPrefsSel]) {
            id wpPrefs = [[wpPrefsClass alloc] init];
            SEL allowJSSel = sel_registerName("setAllowsContentJavaScript:");
            if ([wpPrefs respondsToSelector:allowJSSel]) {
                typedef void (*SetBoolFn)(id, SEL, BOOL);
                ((SetBoolFn)objc_msgSend)(wpPrefs, allowJSSel, YES);
            }
            typedef void (*SetPrefsFn)(id, SEL, id);
            ((SetPrefsFn)objc_msgSend)(config, defaultPrefsSel, wpPrefs);
        }

        // Allow media playback without user gesture (for video/audio on pages)
        SEL mediaPlaybackSel = sel_registerName("setMediaTypesRequiringUserActionForPlayback:");
        if ([config respondsToSelector:mediaPlaybackSel]) {
            typedef void (*SetMediaFn)(id, SEL, NSUInteger);
            ((SetMediaFn)objc_msgSend)(config, mediaPlaybackSel, 0); // WKAudiovisualMediaTypeNone
        }

        // Inject user scripts for image format compatibility
        aurora_inject_user_scripts(config);

        id allocated = [WKWebViewClass alloc];
        SEL sel = sel_registerName("initWithFrame:configuration:");
        NSRect frame = NSMakeRect(0, 0, 800, 600);
        typedef id (*InitFn)(id, SEL, NSRect, id);
        id wkWebView = ((InitFn)objc_msgSend)(allocated, sel, frame, config);

        if (wkWebView) {
            // Set custom user agent to match Safari
            SEL setUASel = sel_registerName("setCustomUserAgent:");
            if ([wkWebView respondsToSelector:setUASel]) {
                NSString *safariUA = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15";
                typedef void (*SetUAFn)(id, SEL, id);
                ((SetUAFn)objc_msgSend)(wkWebView, setUASel, safariUA);
            }
            // Enable Web Inspector (macOS 13.3+)
            SEL inspectableSel = sel_registerName("setInspectable:");
            if ([wkWebView respondsToSelector:inspectableSel]) {
                typedef void (*SetInspectableFn)(id, SEL, BOOL);
                ((SetInspectableFn)objc_msgSend)(wkWebView, inspectableSel, YES);
            }

            // Also try _setDeveloperExtrasEnabled: on preferences
            SEL prefsSel = sel_registerName("configuration");
            if ([wkWebView respondsToSelector:prefsSel]) {
                typedef id (*ConfigFn)(id, SEL);
                id wkConfig = ((ConfigFn)objc_msgSend)(wkWebView, prefsSel);
                if (wkConfig) {
                    SEL getPrefs = sel_registerName("preferences");
                    if ([wkConfig respondsToSelector:getPrefs]) {
                        typedef id (*PrefsFn)(id, SEL);
                        id prefs = ((PrefsFn)objc_msgSend)(wkConfig, getPrefs);
                        if (prefs) {
                            SEL devExtrasSel = sel_registerName("_setDeveloperExtrasEnabled:");
                            if ([prefs respondsToSelector:devExtrasSel]) {
                                typedef void (*SetDevFn)(id, SEL, BOOL);
                                ((SetDevFn)objc_msgSend)(prefs, devExtrasSel, YES);
                            }
                        }
                    }
                }
            }

            // WKWebView created successfully
            return (__bridge_retained void *)wkWebView;
        }
        fprintf(stderr, "[AuroraBridge] ERROR: WKWebView init returned nil\n");
    } @catch (NSException *e) {
        fprintf(stderr, "[AuroraBridge] EXCEPTION creating WKWebView: %s — %s\n",
                e.name.UTF8String, e.reason.UTF8String);
    }

    return NULL;
}

// ---------------------------------------------------------------------------
// Page reference — extract WKPageRef from WKWebView via private SPI
// ---------------------------------------------------------------------------
WKPageRef aurora_view_get_page(void *wkView) {
    if (!wkView) return NULL;
    id view = (__bridge id)wkView;

    // Try _pageRefForTransitionToWKWebView (returns WKPageRef)
    SEL sel = sel_registerName("_pageRefForTransitionToWKWebView");
    if ([view respondsToSelector:sel]) {
        typedef WKPageRef (*PageRefFn)(id, SEL);
        WKPageRef page = ((PageRefFn)objc_msgSend)(view, sel);
        if (page) return page;
    }

    // Fallback: try pageRef (WKView)
    SEL sel2 = sel_registerName("pageRef");
    if ([view respondsToSelector:sel2]) {
        typedef WKPageRef (*PageRefFn)(id, SEL);
        return ((PageRefFn)objc_msgSend)(view, sel2);
    }

    fprintf(stderr, "[AuroraBridge] WARNING: could not extract WKPageRef from view\n");
    return NULL;
}

// ---------------------------------------------------------------------------
// ObjC-based navigation — direct WKWebView method calls as fallback
// when C API page operations don't work with WKWebView's internal page.
// ---------------------------------------------------------------------------
void aurora_view_load_url(void *wkView, const char *url) {
    if (!wkView || !url) return;
    id view = (__bridge id)wkView;

    Class NSURLClass = objc_getClass("NSURL");
    Class NSURLRequestClass = objc_getClass("NSURLRequest");

    SEL urlSel = sel_registerName("URLWithString:");
    typedef id (*URLWithStringFn)(Class, SEL, id);
    NSString *urlStr = [NSString stringWithUTF8String:url];
    id nsurl = ((URLWithStringFn)objc_msgSend)(NSURLClass, urlSel, urlStr);
    if (!nsurl) return;

    SEL reqSel = sel_registerName("requestWithURL:");
    typedef id (*RequestFn)(Class, SEL, id);
    id request = ((RequestFn)objc_msgSend)(NSURLRequestClass, reqSel, nsurl);

    SEL loadSel = sel_registerName("loadRequest:");
    if ([view respondsToSelector:loadSel]) {
        typedef id (*LoadFn)(id, SEL, id);
        ((LoadFn)objc_msgSend)(view, loadSel, request);
    }
}

void aurora_view_load_html_string(void *wkView, const char *html, const char *baseURL) {
    if (!wkView || !html) return;
    id view = (__bridge id)wkView;

    NSString *htmlStr = [NSString stringWithUTF8String:html];
    id nsurl = nil;
    if (baseURL) {
        Class NSURLClass = objc_getClass("NSURL");
        SEL urlSel = sel_registerName("URLWithString:");
        typedef id (*URLWithStringFn)(Class, SEL, id);
        nsurl = ((URLWithStringFn)objc_msgSend)(NSURLClass, urlSel,
                    [NSString stringWithUTF8String:baseURL]);
    }

    SEL sel = sel_registerName("loadHTMLString:baseURL:");
    if ([view respondsToSelector:sel]) {
        typedef id (*LoadHTMLFn)(id, SEL, id, id);
        ((LoadHTMLFn)objc_msgSend)(view, sel, htmlStr, nsurl);
    }
}

void aurora_view_go_back(void *wkView) {
    if (!wkView) return;
    id view = (__bridge id)wkView;
    SEL sel = sel_registerName("goBack");
    if ([view respondsToSelector:sel]) {
        typedef id (*GoBackFn)(id, SEL);
        ((GoBackFn)objc_msgSend)(view, sel);
    }
}

void aurora_view_go_forward(void *wkView) {
    if (!wkView) return;
    id view = (__bridge id)wkView;
    SEL sel = sel_registerName("goForward");
    if ([view respondsToSelector:sel]) {
        typedef id (*GoForwardFn)(id, SEL);
        ((GoForwardFn)objc_msgSend)(view, sel);
    }
}

void aurora_view_reload(void *wkView) {
    if (!wkView) return;
    id view = (__bridge id)wkView;
    SEL sel = sel_registerName("reload");
    if ([view respondsToSelector:sel]) {
        typedef id (*ReloadFn)(id, SEL);
        ((ReloadFn)objc_msgSend)(view, sel);
    }
}

void aurora_view_stop_loading(void *wkView) {
    if (!wkView) return;
    id view = (__bridge id)wkView;
    SEL sel = sel_registerName("stopLoading");
    if ([view respondsToSelector:sel]) {
        typedef id (*StopFn)(id, SEL);
        ((StopFn)objc_msgSend)(view, sel);
    }
}

const char *aurora_view_get_url(void *wkView) {
    if (!wkView) return NULL;
    id view = (__bridge id)wkView;
    SEL sel = sel_registerName("URL");
    if (![view respondsToSelector:sel]) return NULL;
    typedef id (*URLFn)(id, SEL);
    id nsurl = ((URLFn)objc_msgSend)(view, sel);
    if (!nsurl) return NULL;
    SEL absSel = sel_registerName("absoluteString");
    typedef id (*AbsFn)(id, SEL);
    NSString *str = ((AbsFn)objc_msgSend)(nsurl, absSel);
    return str ? strdup([str UTF8String]) : NULL;
}

const char *aurora_view_get_title(void *wkView) {
    if (!wkView) return NULL;
    id view = (__bridge id)wkView;
    SEL sel = sel_registerName("title");
    if (![view respondsToSelector:sel]) return NULL;
    typedef id (*TitleFn)(id, SEL);
    NSString *title = ((TitleFn)objc_msgSend)(view, sel);
    return title ? strdup([title UTF8String]) : NULL;
}

double aurora_view_get_estimated_progress(void *wkView) {
    if (!wkView) return 0.0;
    id view = (__bridge id)wkView;
    SEL sel = sel_registerName("estimatedProgress");
    if (![view respondsToSelector:sel]) return 0.0;
    typedef double (*ProgressFn)(id, SEL);
    return ((ProgressFn)objc_msgSend)(view, sel);
}

bool aurora_view_is_loading(void *wkView) {
    if (!wkView) return false;
    id view = (__bridge id)wkView;
    SEL sel = sel_registerName("isLoading");
    if (![view respondsToSelector:sel]) return false;
    typedef BOOL (*IsLoadingFn)(id, SEL);
    return ((IsLoadingFn)objc_msgSend)(view, sel);
}

bool aurora_view_can_go_back(void *wkView) {
    if (!wkView) return false;
    id view = (__bridge id)wkView;
    SEL sel = sel_registerName("canGoBack");
    if (![view respondsToSelector:sel]) return false;
    typedef BOOL (*CanGoBackFn)(id, SEL);
    return ((CanGoBackFn)objc_msgSend)(view, sel);
}

bool aurora_view_can_go_forward(void *wkView) {
    if (!wkView) return false;
    id view = (__bridge id)wkView;
    SEL sel = sel_registerName("canGoForward");
    if (![view respondsToSelector:sel]) return false;
    typedef BOOL (*CanGoForwardFn)(id, SEL);
    return ((CanGoForwardFn)objc_msgSend)(view, sel);
}

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------
void aurora_page_load_url(WKPageRef page, const char *url) {
    if (!page || !url || !fn_WKPageLoadURL || !fn_WKURLCreateWithUTF8CString) return;

    WKURLRef wkURL = fn_WKURLCreateWithUTF8CString(url);
    fn_WKPageLoadURL(page, wkURL);
    if (fn_WKRelease) fn_WKRelease(wkURL);
}

void aurora_page_load_html(WKPageRef page, const char *html, const char *baseURL) {
    if (!page || !html || !fn_WKPageLoadHTMLString || !fn_WKStringCreateWithUTF8CString) return;

    WKStringRef wkHTML = fn_WKStringCreateWithUTF8CString(html);
    WKURLRef wkBase = NULL;
    if (baseURL && fn_WKURLCreateWithUTF8CString) {
        wkBase = fn_WKURLCreateWithUTF8CString(baseURL);
    }
    fn_WKPageLoadHTMLString(page, wkHTML, wkBase);
    if (fn_WKRelease) {
        fn_WKRelease(wkHTML);
        if (wkBase) fn_WKRelease(wkBase);
    }
}

void aurora_page_go_back(WKPageRef page) {
    if (fn_WKPageGoBack && page) fn_WKPageGoBack(page);
}

void aurora_page_go_forward(WKPageRef page) {
    if (fn_WKPageGoForward && page) fn_WKPageGoForward(page);
}

void aurora_page_reload(WKPageRef page) {
    if (fn_WKPageReload && page) fn_WKPageReload(page);
}

void aurora_page_stop_loading(WKPageRef page) {
    if (fn_WKPageStopLoading && page) fn_WKPageStopLoading(page);
}

// ---------------------------------------------------------------------------
// Page state
// ---------------------------------------------------------------------------
const char *aurora_page_get_url(WKPageRef page) {
    if (!page || !fn_WKPageCopyActiveURL || !fn_WKURLCopyString) return NULL;

    WKURLRef urlRef = fn_WKPageCopyActiveURL(page);
    if (!urlRef) return NULL;

    WKStringRef strRef = fn_WKURLCopyString(urlRef);
    char *result = wkstring_to_cstring(strRef);

    if (fn_WKRelease) {
        fn_WKRelease(strRef);
        fn_WKRelease(urlRef);
    }
    return result;
}

const char *aurora_page_get_title(WKPageRef page) {
    if (!page || !fn_WKPageCopyTitle) return NULL;

    WKStringRef titleRef = fn_WKPageCopyTitle(page);
    char *result = wkstring_to_cstring(titleRef);
    if (fn_WKRelease && titleRef) fn_WKRelease(titleRef);
    return result;
}

double aurora_page_get_estimated_progress(WKPageRef page) {
    if (!page || !fn_WKPageGetEstimatedProgress) return 0.0;
    return fn_WKPageGetEstimatedProgress(page);
}

bool aurora_page_is_loading(WKPageRef page) {
    if (!page || !fn_WKPageIsLoading) return false;
    return fn_WKPageIsLoading(page);
}

bool aurora_page_can_go_back(WKPageRef page) {
    if (!page || !fn_WKPageCanGoBack) return false;
    return fn_WKPageCanGoBack(page);
}

bool aurora_page_can_go_forward(WKPageRef page) {
    if (!page || !fn_WKPageCanGoForward) return false;
    return fn_WKPageCanGoForward(page);
}

// ---------------------------------------------------------------------------
// Web Inspector
// ---------------------------------------------------------------------------
void aurora_inspector_show(WKPageRef page) {
    if (!page || !fn_WKPageGetInspector || !fn_WKInspectorShow) return;
    WKInspectorRef inspector = fn_WKPageGetInspector(page);
    if (inspector) fn_WKInspectorShow(inspector);
}

void aurora_inspector_close(WKPageRef page) {
    if (!page || !fn_WKPageGetInspector || !fn_WKInspectorClose) return;
    WKInspectorRef inspector = fn_WKPageGetInspector(page);
    if (inspector) fn_WKInspectorClose(inspector);
}

void aurora_inspector_attach(WKPageRef page) {
    if (!page || !fn_WKPageGetInspector || !fn_WKInspectorAttach) return;
    WKInspectorRef inspector = fn_WKPageGetInspector(page);
    if (inspector) fn_WKInspectorAttach(inspector);
}

void aurora_inspector_detach(WKPageRef page) {
    if (!page || !fn_WKPageGetInspector || !fn_WKInspectorDetach) return;
    WKInspectorRef inspector = fn_WKPageGetInspector(page);
    if (inspector) fn_WKInspectorDetach(inspector);
}

bool aurora_inspector_is_visible(WKPageRef page) {
    if (!page || !fn_WKPageGetInspector || !fn_WKInspectorIsVisible) return false;
    WKInspectorRef inspector = fn_WKPageGetInspector(page);
    return inspector ? fn_WKInspectorIsVisible(inspector) : false;
}

bool aurora_inspector_is_attached(WKPageRef page) {
    if (!page || !fn_WKPageGetInspector || !fn_WKInspectorIsAttached) return false;
    WKInspectorRef inspector = fn_WKPageGetInspector(page);
    return inspector ? fn_WKInspectorIsAttached(inspector) : false;
}

// ---------------------------------------------------------------------------
// ObjC-based Web Inspector — via WKWebView's _inspector SPI
// ---------------------------------------------------------------------------
static id aurora_get_wk_inspector(void *wkView) {
    if (!wkView) return nil;
    id view = (__bridge id)wkView;
    SEL sel = sel_registerName("_inspector");
    if (![view respondsToSelector:sel]) return nil;
    typedef id (*InspectorFn)(id, SEL);
    return ((InspectorFn)objc_msgSend)(view, sel);
}

void aurora_view_inspector_show(void *wkView) {
    id inspector = aurora_get_wk_inspector(wkView);
    if (!inspector) return;
    SEL sel = sel_registerName("show");
    if ([inspector respondsToSelector:sel]) {
        typedef void (*ShowFn)(id, SEL);
        ((ShowFn)objc_msgSend)(inspector, sel);
    }
}

void aurora_view_inspector_close(void *wkView) {
    id inspector = aurora_get_wk_inspector(wkView);
    if (!inspector) return;
    SEL sel = sel_registerName("close");
    if ([inspector respondsToSelector:sel]) {
        typedef void (*CloseFn)(id, SEL);
        ((CloseFn)objc_msgSend)(inspector, sel);
    }
}

void aurora_view_inspector_attach(void *wkView) {
    id inspector = aurora_get_wk_inspector(wkView);
    if (!inspector) return;
    SEL sel = sel_registerName("attach");
    if ([inspector respondsToSelector:sel]) {
        typedef void (*AttachFn)(id, SEL);
        ((AttachFn)objc_msgSend)(inspector, sel);
    }
}

void aurora_view_inspector_detach(void *wkView) {
    id inspector = aurora_get_wk_inspector(wkView);
    if (!inspector) return;
    SEL sel = sel_registerName("detach");
    if ([inspector respondsToSelector:sel]) {
        typedef void (*DetachFn)(id, SEL);
        ((DetachFn)objc_msgSend)(inspector, sel);
    }
}

bool aurora_view_inspector_is_visible(void *wkView) {
    id inspector = aurora_get_wk_inspector(wkView);
    if (!inspector) return false;
    SEL sel = sel_registerName("isVisible");
    if (![inspector respondsToSelector:sel]) return false;
    typedef BOOL (*VisibleFn)(id, SEL);
    return ((VisibleFn)objc_msgSend)(inspector, sel);
}

// ---------------------------------------------------------------------------
// Navigation callbacks (polling-based for now)
// ---------------------------------------------------------------------------
void aurora_page_install_navigation_callbacks(WKPageRef page,
                                               void *clientInfo,
                                               AuroraNavigationCallback onStateChanged) {
    // The WebKit2 C API navigation client uses a struct of function pointers
    // (WKPageNavigationClientV3). Installing it requires precise struct layout
    // matching. For the initial skeleton, we expose a polling-based approach
    // where Swift calls the state getters on a timer. The full callback
    // installation will be added in a follow-up when we match the exact
    // struct layout for the current macOS WebKit version.
    (void)page;
    (void)clientInfo;
    (void)onStateChanged;
}
