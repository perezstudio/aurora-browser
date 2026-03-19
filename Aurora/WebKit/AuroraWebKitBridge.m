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

        // Enable Picture-in-Picture for HTML5 video elements
        SEL pipSel = sel_registerName("setAllowsPictureInPictureMediaPlayback:");
        if ([config respondsToSelector:pipSel]) {
            typedef void (*SetBoolFn)(id, SEL, BOOL);
            ((SetBoolFn)objc_msgSend)(config, pipSel, YES);
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
// User agent
// ---------------------------------------------------------------------------

void aurora_view_set_custom_user_agent(void *wkView, const char *userAgent) {
    if (!wkView || !userAgent) return;
    id view = (__bridge id)wkView;

    SEL setUASel = sel_registerName("setCustomUserAgent:");
    if ([view respondsToSelector:setUASel]) {
        NSString *ua = [NSString stringWithUTF8String:userAgent];
        typedef void (*SetUAFn)(id, SEL, id);
        ((SetUAFn)objc_msgSend)(view, setUASel, ua);
    }
}

// ---------------------------------------------------------------------------
// Extension support — user scripts, content rules, and script message handlers
// ---------------------------------------------------------------------------

// Helper: get WKUserContentController from a live WKWebView
static id aurora_get_user_content_controller(void *wkView) {
    if (!wkView) return nil;
    id view = (__bridge id)wkView;

    SEL configSel = sel_registerName("configuration");
    if (![view respondsToSelector:configSel]) return nil;
    typedef id (*ConfigFn)(id, SEL);
    id config = ((ConfigFn)objc_msgSend)(view, configSel);
    if (!config) return nil;

    SEL uccSel = sel_registerName("userContentController");
    if (![config respondsToSelector:uccSel]) return nil;
    typedef id (*UCCFn)(id, SEL);
    return ((UCCFn)objc_msgSend)(config, uccSel);
}

void aurora_view_add_user_script(void *wkView, const char *source, int injectionTime, bool mainFrameOnly) {
    id ucc = aurora_get_user_content_controller(wkView);
    if (!ucc || !source) return;

    Class scriptClass = objc_getClass("WKUserScript");
    if (!scriptClass) return;

    SEL initSel = sel_registerName("initWithSource:injectionTime:forMainFrameOnly:");
    if (![scriptClass instancesRespondToSelector:initSel]) return;

    NSString *src = [NSString stringWithUTF8String:source];
    id script = ((id(*)(id, SEL, id, NSInteger, BOOL))objc_msgSend)(
        [scriptClass alloc], initSel, src, (NSInteger)injectionTime, (BOOL)mainFrameOnly);

    SEL addSel = sel_registerName("addUserScript:");
    if ([ucc respondsToSelector:addSel]) {
        ((void(*)(id, SEL, id))objc_msgSend)(ucc, addSel, script);
    }
}

void aurora_view_remove_all_user_scripts(void *wkView) {
    id ucc = aurora_get_user_content_controller(wkView);
    if (!ucc) return;

    SEL removeSel = sel_registerName("removeAllUserScripts");
    if ([ucc respondsToSelector:removeSel]) {
        ((void(*)(id, SEL))objc_msgSend)(ucc, removeSel);
    }
}

void aurora_view_reinject_image_compat_script(void *wkView) {
    id ucc = aurora_get_user_content_controller(wkView);
    if (!ucc) return;

    Class scriptClass = objc_getClass("WKUserScript");
    if (!scriptClass) return;

    SEL initSel = sel_registerName("initWithSource:injectionTime:forMainFrameOnly:");
    if (![scriptClass instancesRespondToSelector:initSel]) return;

    id script = ((id(*)(id, SEL, id, NSInteger, BOOL))objc_msgSend)(
        [scriptClass alloc], initSel, kImageCompatScript, 1 /* AtDocumentEnd */, NO);

    SEL addSel = sel_registerName("addUserScript:");
    if ([ucc respondsToSelector:addSel]) {
        ((void(*)(id, SEL, id))objc_msgSend)(ucc, addSel, script);
    }
}

// --- Content Rule Lists ---

void aurora_compile_content_rules(const char *identifier,
                                  const char *jsonRules,
                                  void *context,
                                  AuroraContentRuleCallback callback) {
    if (!identifier || !jsonRules || !callback) return;

    Class storeClass = objc_getClass("WKContentRuleListStore");
    if (!storeClass) {
        callback(context, NULL, "WKContentRuleListStore class not found");
        return;
    }

    SEL defaultSel = sel_registerName("defaultStore");
    if (![storeClass respondsToSelector:defaultSel]) {
        callback(context, NULL, "defaultStore not available");
        return;
    }
    typedef id (*DefaultStoreFn)(Class, SEL);
    id store = ((DefaultStoreFn)objc_msgSend)(storeClass, defaultSel);
    if (!store) {
        callback(context, NULL, "Could not get default WKContentRuleListStore");
        return;
    }

    NSString *ident = [NSString stringWithUTF8String:identifier];
    NSString *rules = [NSString stringWithUTF8String:jsonRules];

    SEL compileSel = sel_registerName("compileContentRuleListForIdentifier:encodedContentRuleList:completionHandler:");
    if (![store respondsToSelector:compileSel]) {
        callback(context, NULL, "compileContentRuleList not available");
        return;
    }

    // Completion handler — dispatch callback to main thread
    void (^completionBlock)(id, NSError *) = ^(id ruleList, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                const char *errMsg = error.localizedDescription.UTF8String;
                callback(context, NULL, errMsg);
            } else {
                void *retained = (__bridge_retained void *)ruleList;
                callback(context, retained, NULL);
            }
        });
    };

    typedef void (*CompileFn)(id, SEL, id, id, id);
    ((CompileFn)objc_msgSend)(store, compileSel, ident, rules, completionBlock);
}

void aurora_view_add_content_rule_list(void *wkView, void *ruleList) {
    id ucc = aurora_get_user_content_controller(wkView);
    if (!ucc || !ruleList) return;

    id rl = (__bridge_transfer id)ruleList;
    SEL addSel = sel_registerName("addContentRuleList:");
    if ([ucc respondsToSelector:addSel]) {
        ((void(*)(id, SEL, id))objc_msgSend)(ucc, addSel, rl);
    }
}

void aurora_view_remove_all_content_rule_lists(void *wkView) {
    id ucc = aurora_get_user_content_controller(wkView);
    if (!ucc) return;

    SEL removeSel = sel_registerName("removeAllContentRuleLists");
    if ([ucc respondsToSelector:removeSel]) {
        ((void(*)(id, SEL))objc_msgSend)(ucc, removeSel);
    }
}

// --- Script Message Handlers ---

// ObjC class that conforms to WKScriptMessageHandler and forwards to C callback.
@interface AuroraScriptMessageHandler : NSObject
@property (nonatomic, assign) void *callbackContext;
@property (nonatomic, assign) AuroraScriptMessageCallback callback;
@property (nonatomic, copy) NSString *handlerName;
@end

@implementation AuroraScriptMessageHandler

- (void)userContentController:(id)userContentController didReceiveScriptMessage:(id)message {
    if (!self.callback) return;

    // Extract message body as JSON string
    SEL bodySel = sel_registerName("body");
    typedef id (*BodyFn)(id, SEL);
    id body = ((BodyFn)objc_msgSend)(message, bodySel);

    NSString *jsonString = nil;
    if ([body isKindOfClass:[NSString class]]) {
        jsonString = body;
    } else if ([body isKindOfClass:[NSDictionary class]] || [body isKindOfClass:[NSArray class]]) {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        if (jsonData) {
            jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        }
    } else {
        jsonString = [NSString stringWithFormat:@"%@", body];
    }

    self.callback(self.callbackContext,
                  self.handlerName.UTF8String,
                  jsonString ? jsonString.UTF8String : "");
}

@end

// Dictionary to keep message handlers alive (keyed by "viewPtr_handlerName")
static NSMutableDictionary *s_messageHandlers = nil;

void aurora_view_add_script_message_handler(void *wkView,
                                             const char *name,
                                             void *context,
                                             AuroraScriptMessageCallback callback) {
    id ucc = aurora_get_user_content_controller(wkView);
    if (!ucc || !name || !callback) return;

    if (!s_messageHandlers) {
        s_messageHandlers = [NSMutableDictionary new];
    }

    NSString *handlerName = [NSString stringWithUTF8String:name];

    AuroraScriptMessageHandler *handler = [[AuroraScriptMessageHandler alloc] init];
    handler.callbackContext = context;
    handler.callback = callback;
    handler.handlerName = handlerName;

    // Keep handler alive
    NSString *key = [NSString stringWithFormat:@"%p_%@", wkView, handlerName];
    s_messageHandlers[key] = handler;

    SEL addSel = sel_registerName("addScriptMessageHandler:name:");
    if ([ucc respondsToSelector:addSel]) {
        ((void(*)(id, SEL, id, id))objc_msgSend)(ucc, addSel, handler, handlerName);
    }
}

void aurora_view_remove_script_message_handler(void *wkView, const char *name) {
    id ucc = aurora_get_user_content_controller(wkView);
    if (!ucc || !name) return;

    NSString *handlerName = [NSString stringWithUTF8String:name];

    SEL removeSel = sel_registerName("removeScriptMessageHandlerForName:");
    if ([ucc respondsToSelector:removeSel]) {
        ((void(*)(id, SEL, id))objc_msgSend)(ucc, removeSel, handlerName);
    }

    // Release handler
    if (s_messageHandlers) {
        NSString *key = [NSString stringWithFormat:@"%p_%@", wkView, handlerName];
        [s_messageHandlers removeObjectForKey:key];
    }
}

// ---------------------------------------------------------------------------
// Navigation callbacks (polling-based for now)
// ---------------------------------------------------------------------------
void aurora_page_install_navigation_callbacks(WKPageRef page,
                                               void *clientInfo,
                                               AuroraNavigationCallback onStateChanged) {
    (void)page;
    (void)clientInfo;
    (void)onStateChanged;
}

// ---------------------------------------------------------------------------
// Safari Web Extension support (macOS 15.4+)
// ---------------------------------------------------------------------------
// Uses WKWebExtension, WKWebExtensionController, WKWebExtensionContext,
// and protocol-conforming ObjC classes for WKWebExtensionTab/Window.
// All accessed via objc_getClass / objc_msgSend — no WebKit import.
// ---------------------------------------------------------------------------

#pragma mark - Availability check

bool aurora_ext_is_available(void) {
    if (@available(macOS 15.4, *)) {
        Class cls = objc_getClass("WKWebExtensionController");
        return cls != nil;
    }
    return false;
}

#pragma mark - AuroraExtensionTab (WKWebExtensionTab protocol)

API_AVAILABLE(macos(15.4))
@interface AuroraExtensionTab : NSObject
@property (nonatomic, strong) NSView *webView;
@property (nonatomic, strong) NSURL *tabURL;
@property (nonatomic, copy) NSString *tabTitle;
@property (nonatomic, assign) BOOL isTabActive;
@property (nonatomic, assign) BOOL isTabPinned;
@property (nonatomic, assign) BOOL isTabLoading;
@property (nonatomic, weak) id containingWindow; // AuroraExtensionWindow
@property (nonatomic, assign) CGSize tabSize;
@end

@implementation AuroraExtensionTab

// WKWebExtensionTab protocol methods — WebKit calls these via message dispatch

- (id)mainWebView {
    return self.webView;
}

- (id)webViewForWebExtensionContext:(id)context {
    return self.webView;
}

- (NSURL *)url {
    return self.tabURL;
}

- (NSString *)title {
    return self.tabTitle ?: @"";
}

- (BOOL)isActive {
    return self.isTabActive;
}

- (BOOL)isPinned {
    return self.isTabPinned;
}

- (BOOL)isLoading {
    return self.isTabLoading;
}

- (BOOL)isMuted {
    return NO;
}

- (BOOL)isAudible {
    return NO;
}

- (BOOL)isPrivate {
    return NO;
}

- (BOOL)isSelected {
    return self.isTabActive;
}

- (CGSize)size {
    return self.tabSize;
}

- (id)containingWindowForWebExtensionContext:(id)context {
    return self.containingWindow;
}

- (void)activateForWebExtensionContext:(id)context completionHandler:(void (^)(NSError *))handler {
    self.isTabActive = YES;
    if (handler) handler(nil);
}

- (void)selectForWebExtensionContext:(id)context completionHandler:(void (^)(NSError *))handler {
    self.isTabActive = YES;
    if (handler) handler(nil);
}

- (void)deselectForWebExtensionContext:(id)context completionHandler:(void (^)(NSError *))handler {
    self.isTabActive = NO;
    if (handler) handler(nil);
}

- (void)duplicateForWebExtensionContext:(id)context withOptions:(id)options completionHandler:(void (^)(id, NSError *))handler {
    if (handler) handler(nil, nil);
}

- (void)closeForWebExtensionContext:(id)context completionHandler:(void (^)(NSError *))handler {
    if (handler) handler(nil);
}

- (void)reloadForWebExtensionContext:(id)context completionHandler:(void (^)(NSError *))handler {
    if (self.webView) {
        SEL reloadSel = sel_registerName("reload");
        if ([self.webView respondsToSelector:reloadSel]) {
            typedef void (*ReloadFn)(id, SEL);
            ((ReloadFn)objc_msgSend)(self.webView, reloadSel);
        }
    }
    if (handler) handler(nil);
}

- (void)goBackForWebExtensionContext:(id)context completionHandler:(void (^)(NSError *))handler {
    if (self.webView) {
        SEL goBackSel = sel_registerName("goBack");
        if ([self.webView respondsToSelector:goBackSel]) {
            typedef void (*GoBackFn)(id, SEL);
            ((GoBackFn)objc_msgSend)(self.webView, goBackSel);
        }
    }
    if (handler) handler(nil);
}

- (void)goForwardForWebExtensionContext:(id)context completionHandler:(void (^)(NSError *))handler {
    if (self.webView) {
        SEL goFwdSel = sel_registerName("goForward");
        if ([self.webView respondsToSelector:goFwdSel]) {
            typedef void (*GoFwdFn)(id, SEL);
            ((GoFwdFn)objc_msgSend)(self.webView, goFwdSel);
        }
    }
    if (handler) handler(nil);
}

@end

#pragma mark - AuroraExtensionWindow (WKWebExtensionWindow protocol)

API_AVAILABLE(macos(15.4))
@interface AuroraExtensionWindow : NSObject
@property (nonatomic, strong) NSMutableArray<AuroraExtensionTab *> *windowTabs;
@property (nonatomic, weak) AuroraExtensionTab *activeTab;
@property (nonatomic, assign) BOOL isWindowActive;
@property (nonatomic, assign) NSRect windowFrame;
@end

@implementation AuroraExtensionWindow

- (instancetype)init {
    self = [super init];
    if (self) {
        _windowTabs = [NSMutableArray new];
        _isWindowActive = YES;
        _windowFrame = NSMakeRect(0, 0, 1440, 900);
    }
    return self;
}

// WKWebExtensionWindow protocol methods

- (NSArray *)tabs {
    return [self.windowTabs copy];
}

- (id)activeTabForWebExtensionContext:(id)context {
    return self.activeTab;
}

- (NSInteger)windowType {
    return 0; // WKWebExtensionWindowTypeNormal
}

- (NSInteger)windowState {
    return 0; // WKWebExtensionWindowStateNormal
}

- (BOOL)isActive {
    return self.isWindowActive;
}

- (BOOL)isFocused {
    return self.isWindowActive;
}

- (BOOL)isPrivate {
    return NO;
}

- (NSRect)frame {
    return self.windowFrame;
}

- (NSRect)screenFrame {
    return self.windowFrame;
}

- (void)closeForWebExtensionContext:(id)context completionHandler:(void (^)(NSError *))handler {
    if (handler) handler(nil);
}

- (void)focusForWebExtensionContext:(id)context completionHandler:(void (^)(NSError *))handler {
    self.isWindowActive = YES;
    if (handler) handler(nil);
}

@end

#pragma mark - AuroraExtensionControllerDelegate (WKWebExtensionControllerDelegate)

API_AVAILABLE(macos(15.4))
@interface AuroraExtensionControllerDelegate : NSObject
@property (nonatomic, assign) void *swiftContext;
@property (nonatomic, assign) AuroraExtPermissionCallback permissionCallback;
@property (nonatomic, assign) AuroraExtTabActionCallback actionCallback;
@property (nonatomic, strong) NSMutableArray<AuroraExtensionWindow *> *windows;
@end

@implementation AuroraExtensionControllerDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _windows = [NSMutableArray new];
    }
    return self;
}

// Log all selectors WebKit queries on this delegate (one-time enumeration)
static NSMutableSet *s_loggedSelectors = nil;
- (BOOL)respondsToSelector:(SEL)aSelector {
    BOOL responds = [super respondsToSelector:aSelector];
    NSString *selName = NSStringFromSelector(aSelector);
    if (!s_loggedSelectors) s_loggedSelectors = [NSMutableSet new];
    if (![s_loggedSelectors containsObject:selName]) {
        [s_loggedSelectors addObject:selName];
        if ([selName containsString:@"webExtension"] || [selName containsString:@"WebExtension"]
            || [selName containsString:@"Tab"] || [selName containsString:@"tab"]
            || [selName containsString:@"Window"] || [selName containsString:@"window"]
            || [selName containsString:@"Message"] || [selName containsString:@"message"]
            || [selName containsString:@"native"] || [selName containsString:@"Native"]
            || [selName containsString:@"popup"] || [selName containsString:@"Popup"]) {
            fprintf(stderr, "[AuroraBridge] Delegate queried: %s → %s\n",
                    selName.UTF8String, responds ? "YES" : "NO");
        }
    }
    return responds;
}

// WKWebExtensionControllerDelegate — correct selectors discovered via respondsToSelector: logging

// --- Window enumeration (webExtensionController:openWindowsForExtensionContext:) ---
- (NSArray *)webExtensionController:(id)controller openWindowsForExtensionContext:(id)context {
    return [self.windows copy];
}

// --- Focused window (webExtensionController:focusedWindowForExtensionContext:) ---
- (id)webExtensionController:(id)controller focusedWindowForExtensionContext:(id)context {
    for (AuroraExtensionWindow *w in self.windows) {
        if (w.isWindowActive) return w;
    }
    return self.windows.firstObject;
}

// --- Permission prompts — auto-grant ---
- (void)webExtensionController:(id)controller
     promptForPermissions:(id)permissions
                inTab:(id)tab
         forExtensionContext:(id)context
           completionHandler:(void (^)(id, NSDate *))handler {
    if (handler) handler(permissions, [NSDate distantFuture]);
}

- (void)webExtensionController:(id)controller
    promptForPermissionMatchPatterns:(id)patterns
                inTab:(id)tab
         forExtensionContext:(id)context
           completionHandler:(void (^)(id, NSDate *))handler {
    if (handler) handler(patterns, [NSDate distantFuture]);
}

- (void)webExtensionController:(id)controller
    promptForPermissionToAccessURLs:(id)urls
                inTab:(id)tab
         forExtensionContext:(id)context
           completionHandler:(void (^)(id, NSDate *))handler {
    if (handler) handler(urls, [NSDate distantFuture]);
}

// --- Action updated (webExtensionController:didUpdateAction:forExtensionContext:) ---
- (void)webExtensionController:(id)controller
              didUpdateAction:(id)action
          forExtensionContext:(id)context {
    fprintf(stderr, "[AuroraBridge] Delegate: didUpdateAction called\n");

    // Check if the action now presents a popup
    SEL hasPopupSel = sel_registerName("presentsPopup");
    if ([action respondsToSelector:hasPopupSel]) {
        typedef BOOL (*BoolFn)(id, SEL);
        BOOL presentsPopup = ((BoolFn)objc_msgSend)(action, hasPopupSel);
        fprintf(stderr, "[AuroraBridge] Action updated: presentsPopup = %d\n", presentsPopup);
    }
}

// --- Background web view created ---
- (void)_webExtensionController:(id)controller
     didCreateBackgroundWebView:(id)webView
          forExtensionContext:(id)context {
    fprintf(stderr, "[AuroraBridge] Delegate: background web view created\n");
}

// --- Popup presentation ---
- (void)webExtensionController:(id)controller
          presentPopupForAction:(id)action
          forExtensionContext:(id)context
            completionHandler:(void (^)(NSError *))handler {
    fprintf(stderr, "[AuroraBridge] Delegate: presentPopupForAction called!\n");

    SEL popupWVSel = sel_registerName("popupWebView");
    id popupWebView = nil;
    if ([action respondsToSelector:popupWVSel]) {
        typedef id (*WVFn)(id, SEL);
        popupWebView = ((WVFn)objc_msgSend)(action, popupWVSel);
    }

    if (popupWebView) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:@"AuroraExtensionPopupReady"
                object:nil
                userInfo:@{
                    @"webView": popupWebView,
                    @"context": context,
                    @"action": action,
                }];
        });
    }

    if (handler) handler(nil);
}

// --- Tab creation (webExtensionController:openNewTabUsingConfiguration:forExtensionContext:completionHandler:) ---
- (void)webExtensionController:(id)controller
  openNewTabUsingConfiguration:(id)configuration
          forExtensionContext:(id)context
            completionHandler:(void (^)(id tab, NSError *error))handler {
    fprintf(stderr, "[AuroraBridge] Delegate: openNewTabUsingConfiguration called\n");

    // Extract URL from configuration if available
    NSString *urlString = nil;
    SEL urlSel = sel_registerName("url");
    if (configuration && [configuration respondsToSelector:urlSel]) {
        typedef id (*URLFn)(id, SEL);
        NSURL *url = ((URLFn)objc_msgSend)(configuration, urlSel);
        urlString = url.absoluteString;
    }

    fprintf(stderr, "[AuroraBridge] New tab requested with URL: %s\n",
            urlString ? urlString.UTF8String : "(none)");

    // Post notification so Swift can create a real tab and return the extension tab object
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"AuroraExtensionOpenNewTab"
            object:nil
            userInfo:@{
                @"url": urlString ?: @"",
                @"context": context,
                @"handler": handler ?: ^(id t, NSError *e){},
            }];
    });

    // If Swift doesn't handle it, create a placeholder tab
    // The notification handler in Swift should call the handler with the real tab
}

// --- Native messaging (webExtensionController:sendMessage:toApplicationWithIdentifier:forExtensionContext:replyHandler:) ---
- (void)webExtensionController:(id)controller
                   sendMessage:(id)message
    toApplicationWithIdentifier:(NSString *)appIdentifier
          forExtensionContext:(id)context
                  replyHandler:(void (^)(id reply, NSError *error))replyHandler {

    NSString *msgName = nil;
    if ([message isKindOfClass:[NSDictionary class]]) {
        msgName = message[@"name"];
    }
    fprintf(stderr, "[AuroraBridge] Delegate: sendNativeMessage name='%s' appID='%s'\n",
            msgName ? msgName.UTF8String : "(unknown)",
            appIdentifier.length ? appIdentifier.UTF8String : "(empty)");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Handle known simple messages locally
        if ([msgName isEqualToString:@"request-os-version"]) {
            NSOperatingSystemVersion ver = [[NSProcessInfo processInfo] operatingSystemVersion];
            NSDictionary *reply = @{
                @"name": @"os-version",
                @"data": @{
                    @"major": @(ver.majorVersion),
                    @"minor": @(ver.minorVersion),
                    @"patch": @(ver.patchVersion),
                    @"build": [[NSProcessInfo processInfo] operatingSystemVersionString] ?: @""
                }
            };
            fprintf(stderr, "[AuroraBridge] Replied to request-os-version locally\n");
            if (replyHandler) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    replyHandler(reply, nil);
                });
            }
            return;
        }

        // For other messages, try to relay via the native messaging host
        // 1. Try Chrome-style native messaging host (BrowserSupport binary)
        NSString *browserSupportPath = @"/Applications/1Password.app/Contents/Library/LoginItems/"
            "1Password Browser Helper.app/Contents/MacOS/1Password-BrowserSupport";

        // Serialize message to JSON
        NSData *msgData = nil;
        if ([message isKindOfClass:[NSDictionary class]] || [message isKindOfClass:[NSArray class]]) {
            msgData = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
        } else if ([message isKindOfClass:[NSString class]]) {
            msgData = [(NSString *)message dataUsingEncoding:NSUTF8StringEncoding];
        }

        if (!msgData) {
            fprintf(stderr, "[AuroraBridge] Failed to serialize native message\n");
            if (replyHandler) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    replyHandler(nil, [NSError errorWithDomain:@"AuroraNativeMessaging"
                                                         code:2
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize message"}]);
                });
            }
            return;
        }

        // Try BrowserSupport binary with Chrome native messaging protocol
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:browserSupportPath]) {
            fprintf(stderr, "[AuroraBridge] Trying BrowserSupport host: %s\n", browserSupportPath.UTF8String);

            @try {
                NSTask *task = [[NSTask alloc] init];
                task.executableURL = [NSURL fileURLWithPath:browserSupportPath];
                // 1Password expects the browser name and extension origin
                task.arguments = @[
                    @"chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/",
                ];

                NSPipe *stdinPipe = [NSPipe pipe];
                NSPipe *stdoutPipe = [NSPipe pipe];
                task.standardInput = stdinPipe;
                task.standardOutput = stdoutPipe;
                task.standardError = [NSFileHandle fileHandleWithNullDevice];

                NSError *launchError = nil;
                [task launchAndReturnError:&launchError];

                if (launchError) {
                    fprintf(stderr, "[AuroraBridge] Failed to launch BrowserSupport: %s\n",
                            launchError.localizedDescription.UTF8String);
                } else {
                    // Chrome native messaging protocol: 4-byte length (LE) + JSON
                    uint32_t length = (uint32_t)msgData.length;
                    NSMutableData *packet = [NSMutableData dataWithBytes:&length length:4];
                    [packet appendData:msgData];
                    [stdinPipe.fileHandleForWriting writeData:packet];
                    [stdinPipe.fileHandleForWriting closeFile];

                    // Read response with timeout
                    NSData *responseData = [stdoutPipe.fileHandleForReading readDataToEndOfFile];
                    [task waitUntilExit];

                    if (responseData.length > 4) {
                        uint32_t respLen = 0;
                        [responseData getBytes:&respLen length:4];
                        if (respLen > 0 && respLen <= responseData.length - 4) {
                            NSData *jsonData = [responseData subdataWithRange:NSMakeRange(4, respLen)];
                            id reply = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];

                            fprintf(stderr, "[AuroraBridge] BrowserSupport reply (%u bytes)\n", respLen);

                            if (replyHandler) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    replyHandler(reply, nil);
                                });
                            }
                            return;
                        }
                    }
                    fprintf(stderr, "[AuroraBridge] BrowserSupport: no valid response (exit=%d, bytes=%lu)\n",
                            task.terminationStatus, (unsigned long)responseData.length);
                }
            } @catch (NSException *e) {
                fprintf(stderr, "[AuroraBridge] BrowserSupport exception: %s\n", e.reason.UTF8String);
            }
        }

        // 2. Try Unix socket in 1Password group container
        NSString *socketPath = [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Group Containers/2BUA8C4S2C.com.1password/t/s.sock"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:socketPath]) {
            fprintf(stderr, "[AuroraBridge] Found 1Password socket: %s\n", socketPath.UTF8String);
            // TODO: Implement Unix socket communication for persistent messaging
        }

        // Fallback: return empty reply (not an error — some messages are fire-and-forget)
        fprintf(stderr, "[AuroraBridge] Native messaging: returning empty reply for '%s'\n",
                msgName ? msgName.UTF8String : "(unknown)");
        if (replyHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                replyHandler(@{}, nil);
            });
        }
    });
}

// --- Persistent native messaging port ---

// Storage for persistent BrowserSupport connections
static NSMutableDictionary *s_portTasks = nil;
static NSMutableDictionary *s_portStdinPipes = nil;
static NSMutableDictionary *s_portMessagePorts = nil;

static NSString *portKey(id port) {
    return [NSString stringWithFormat:@"%p", (__bridge void *)port];
}

static void writeNativeFrame(NSFileHandle *handle, id message) {
    NSData *jsonData = nil;
    if ([message isKindOfClass:[NSDictionary class]] || [message isKindOfClass:[NSArray class]]) {
        jsonData = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    }
    if (!jsonData) return;
    uint32_t length = (uint32_t)jsonData.length;
    NSMutableData *packet = [NSMutableData dataWithBytes:&length length:4];
    [packet appendData:jsonData];
    @try {
        [handle writeData:packet];
    } @catch (NSException *e) {
        fprintf(stderr, "[AuroraBridge] writeNativeFrame failed: %s\n", e.reason.UTF8String);
    }
}

- (void)webExtensionController:(id)controller
    connectUsingMessagePort:(id)messagePort
          forExtensionContext:(id)context
            completionHandler:(void (^)(NSError *error))handler {
    fprintf(stderr, "[AuroraBridge] Delegate: connectUsingMessagePort called\n");

    if (!s_portTasks) {
        s_portTasks = [NSMutableDictionary new];
        s_portStdinPipes = [NSMutableDictionary new];
        s_portMessagePorts = [NSMutableDictionary new];
    }

    NSString *key = portKey(messagePort);

    // Launch persistent BrowserSupport process
    NSString *bsPath = @"/Applications/1Password.app/Contents/Library/LoginItems/"
        "1Password Browser Helper.app/Contents/MacOS/1Password-BrowserSupport";

    if ([[NSFileManager defaultManager] isExecutableFileAtPath:bsPath]) {
        @try {
            NSTask *task = [[NSTask alloc] init];
            task.executableURL = [NSURL fileURLWithPath:bsPath];
            task.arguments = @[@"chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"];

            NSPipe *stdinPipe = [NSPipe pipe];
            NSPipe *stdoutPipe = [NSPipe pipe];
            task.standardInput = stdinPipe;
            task.standardOutput = stdoutPipe;
            task.standardError = [NSFileHandle fileHandleWithNullDevice];

            NSError *err = nil;
            [task launchAndReturnError:&err];

            if (err) {
                fprintf(stderr, "[AuroraBridge] BrowserSupport launch failed: %s\n",
                        err.localizedDescription.UTF8String);
            } else {
                fprintf(stderr, "[AuroraBridge] Persistent BrowserSupport PID=%d\n", task.processIdentifier);

                s_portTasks[key] = task;
                s_portStdinPipes[key] = stdinPipe;
                s_portMessagePorts[key] = messagePort;

                // Reader thread: BrowserSupport stdout → extension port
                NSFileHandle *readHandle = stdoutPipe.fileHandleForReading;
                __weak id weakPort = messagePort;

                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    while (task.isRunning) {
                        @try {
                            // Read 4-byte length
                            NSData *lenData = [readHandle readDataOfLength:4];
                            if (lenData.length < 4) {
                                fprintf(stderr, "[AuroraBridge] BrowserSupport: EOF or short read\n");
                                break;
                            }
                            uint32_t len = 0;
                            [lenData getBytes:&len length:4];
                            if (len == 0 || len > 10*1024*1024) break;

                            NSData *jsonData = [readHandle readDataOfLength:len];
                            if (jsonData.length < len) break;

                            id response = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
                            if (!response) continue;

                            fprintf(stderr, "[AuroraBridge] BrowserSupport → extension (%u bytes)\n", len);

                            // Forward to extension via message port
                            id strongPort = weakPort;
                            if (strongPort) {
                                SEL sendSel = sel_registerName("sendMessage:completionHandler:");
                                if ([strongPort respondsToSelector:sendSel]) {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        typedef void (*SendFn)(id, SEL, id, id);
                                        ((SendFn)objc_msgSend)(strongPort, sendSel, response, nil);
                                    });
                                }
                            }
                        } @catch (NSException *e) {
                            fprintf(stderr, "[AuroraBridge] BrowserSupport read error: %s\n", e.reason.UTF8String);
                            break;
                        }
                    }
                    fprintf(stderr, "[AuroraBridge] BrowserSupport reader ended\n");
                });
            }
        } @catch (NSException *e) {
            fprintf(stderr, "[AuroraBridge] BrowserSupport exception: %s\n", e.reason.UTF8String);
        }
    }

    // Message handler: extension → BrowserSupport
    SEL setHandlerSel = sel_registerName("setMessageHandler:");
    if ([messagePort respondsToSelector:setHandlerSel]) {
        NSString *capturedKey = [key copy];
        typedef void (*SetHandlerFn)(id, SEL, id);
        ((SetHandlerFn)objc_msgSend)(messagePort, setHandlerSel, ^(id msg, void (^reply)(id, NSError *)) {
            NSString *name = [msg isKindOfClass:[NSDictionary class]] ? msg[@"name"] : nil;
            fprintf(stderr, "[AuroraBridge] Extension → BrowserSupport: '%s'\n",
                    name ? name.UTF8String : "?");

            NSPipe *stdinPipe = s_portStdinPipes[capturedKey];
            if (stdinPipe) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    writeNativeFrame(stdinPipe.fileHandleForWriting, msg);
                });
            }

            // Response comes asynchronously via reader thread → sendMessage
            if (reply) reply(nil, nil);
        });
    }

    // Disconnect handler: cleanup
    SEL setDisconnectSel = sel_registerName("setDisconnectHandler:");
    if ([messagePort respondsToSelector:setDisconnectSel]) {
        NSString *capturedKey = [key copy];
        typedef void (*SetDisconnectFn)(id, SEL, id);
        ((SetDisconnectFn)objc_msgSend)(messagePort, setDisconnectSel, ^(NSError *error) {
            fprintf(stderr, "[AuroraBridge] Port disconnected\n");
            NSTask *task = s_portTasks[capturedKey];
            if (task.isRunning) [task terminate];
            [s_portTasks removeObjectForKey:capturedKey];
            [s_portStdinPipes removeObjectForKey:capturedKey];
            [s_portMessagePorts removeObjectForKey:capturedKey];
        });
    }

    if (handler) handler(nil);
}

@end

#pragma mark - Static storage for extension objects

// Keep delegate and window objects alive (keyed by controller pointer)
static NSMutableDictionary *s_extDelegates = nil; // controller ptr string → delegate
static NSMutableDictionary *s_extTabs = nil;      // tab ptr string → AuroraExtensionTab
static NSMutableDictionary *s_extWindows = nil;   // window ptr string → AuroraExtensionWindow

static NSString *ptrKey(void *ptr) {
    return [NSString stringWithFormat:@"%p", ptr];
}

#pragma mark - Helper: create WKWebExtension from appex path

static id aurora_create_web_extension(const char *appexPath) API_AVAILABLE(macos(15.4)) {
    if (!appexPath) return nil;

    Class WKWebExtensionClass = objc_getClass("WKWebExtension");
    if (!WKWebExtensionClass) return nil;

    NSString *path = [NSString stringWithUTF8String:appexPath];
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    if (!bundle) {
        fprintf(stderr, "[AuroraBridge] Extension bundle not found at: %s\n", appexPath);
        return nil;
    }

    // Wrap all attempts in @try/@catch — some .appex bundles trigger internal
    // assertions inside WebKit when they aren't loadable by our process.
    @try {
        // Try instance initializer: -[WKWebExtension initWithAppExtensionBundle:error:]
        SEL initSel = sel_registerName("initWithAppExtensionBundle:error:");
        if ([WKWebExtensionClass instancesRespondToSelector:initSel]) {
            id ext = [WKWebExtensionClass alloc];
            NSError *error = nil;
            typedef id (*ExtInitFn)(id, SEL, id, NSError **);
            ext = ((ExtInitFn)objc_msgSend)(ext, initSel, bundle, &error);
            if (error) {
                fprintf(stderr, "[AuroraBridge] Error creating WKWebExtension: %s\n",
                        error.localizedDescription.UTF8String);
                return nil;
            }
            if (ext) return ext;
        }

        // Fallback: class factory +[WKWebExtension extensionWithAppExtensionBundle:error:]
        SEL factorySel = sel_registerName("extensionWithAppExtensionBundle:error:");
        if ([WKWebExtensionClass respondsToSelector:factorySel]) {
            NSError *error = nil;
            typedef id (*ExtCreateFn)(Class, SEL, id, NSError **);
            id ext = ((ExtCreateFn)objc_msgSend)(WKWebExtensionClass, factorySel, bundle, &error);
            if (error) {
                fprintf(stderr, "[AuroraBridge] Error creating WKWebExtension: %s\n",
                        error.localizedDescription.UTF8String);
                return nil;
            }
            if (ext) return ext;
        }

        // Try URL-based initializer: -[WKWebExtension initWithResourceBaseURL:error:]
        SEL urlInitSel = sel_registerName("initWithResourceBaseURL:error:");
        if ([WKWebExtensionClass instancesRespondToSelector:urlInitSel]) {
            NSURL *bundleURL = [NSURL fileURLWithPath:path];
            id ext = [WKWebExtensionClass alloc];
            NSError *error = nil;
            typedef id (*ExtURLInitFn)(id, SEL, id, NSError **);
            ext = ((ExtURLInitFn)objc_msgSend)(ext, urlInitSel, bundleURL, &error);
            if (error) {
                fprintf(stderr, "[AuroraBridge] Error creating WKWebExtension from URL: %s\n",
                        error.localizedDescription.UTF8String);
                return nil;
            }
            if (ext) return ext;
        }
    } @catch (NSException *exception) {
        fprintf(stderr, "[AuroraBridge] Exception creating WKWebExtension from %s: %s\n",
                appexPath, exception.reason.UTF8String);
        return nil;
    }

    fprintf(stderr, "[AuroraBridge] WKWebExtension has no recognized initializer\n");
    return nil;
}

#pragma mark - Extension Controller

void *aurora_ext_controller_create(void) {
    if (@available(macOS 15.4, *)) {
        Class controllerClass = objc_getClass("WKWebExtensionController");
        if (!controllerClass) {
            fprintf(stderr, "[AuroraBridge] WKWebExtensionController class not found\n");
            return NULL;
        }

        id controller = [[controllerClass alloc] init];
        if (!controller) return NULL;

        // Enumerate WKWebExtensionControllerDelegate protocol methods (one-time diagnostic)
        static BOOL didLogDelegateMethods = NO;
        if (!didLogDelegateMethods) {
            didLogDelegateMethods = YES;
            Protocol *delegateProto = objc_getProtocol("WKWebExtensionControllerDelegate");
            if (delegateProto) {
                fprintf(stderr, "[AuroraBridge] WKWebExtensionControllerDelegate protocol methods:\n");
                // Required + optional, instance methods
                for (int isRequired = 0; isRequired <= 1; isRequired++) {
                    unsigned int count = 0;
                    struct objc_method_description *methods =
                        protocol_copyMethodDescriptionList(delegateProto,
                                                          (BOOL)isRequired, YES, &count);
                    for (unsigned int i = 0; i < count; i++) {
                        fprintf(stderr, "  %s[%s] %s\n",
                                isRequired ? "REQ " : "OPT ",
                                methods[i].types ?: "?",
                                sel_getName(methods[i].name));
                    }
                    free(methods);
                }
            } else {
                fprintf(stderr, "[AuroraBridge] WKWebExtensionControllerDelegate protocol not found via objc_getProtocol\n");
                // Try via _WKWebExtensionControllerDelegate
                Protocol *underscoreProto = objc_getProtocol("_WKWebExtensionControllerDelegate");
                if (underscoreProto) {
                    fprintf(stderr, "[AuroraBridge] Found _WKWebExtensionControllerDelegate:\n");
                    for (int isRequired = 0; isRequired <= 1; isRequired++) {
                        unsigned int count = 0;
                        struct objc_method_description *methods =
                            protocol_copyMethodDescriptionList(underscoreProto,
                                                              (BOOL)isRequired, YES, &count);
                        for (unsigned int i = 0; i < count; i++) {
                            fprintf(stderr, "  %s %s\n",
                                    isRequired ? "REQ" : "OPT",
                                    sel_getName(methods[i].name));
                        }
                        free(methods);
                    }
                } else {
                    fprintf(stderr, "[AuroraBridge] No delegate protocol found. Enumerating conforming protocols on controller class...\n");
                    // List all protocols on the controller class
                    unsigned int protoCount = 0;
                    Protocol * __unsafe_unretained *protos = class_copyProtocolList(controllerClass, &protoCount);
                    for (unsigned int i = 0; i < protoCount; i++) {
                        fprintf(stderr, "  Controller protocol: %s\n", protocol_getName(protos[i]));
                    }
                    free(protos);
                }
            }
        }

        // Create and set delegate
        AuroraExtensionControllerDelegate *delegate = [[AuroraExtensionControllerDelegate alloc] init];

        SEL setDelegateSel = sel_registerName("setDelegate:");
        if ([controller respondsToSelector:setDelegateSel]) {
            typedef void (*SetDelFn)(id, SEL, id);
            ((SetDelFn)objc_msgSend)(controller, setDelegateSel, delegate);
        }

        // Store delegate to keep alive
        if (!s_extDelegates) s_extDelegates = [NSMutableDictionary new];
        void *retained = (__bridge_retained void *)controller;
        s_extDelegates[ptrKey(retained)] = delegate;

        return retained;
    }
    return NULL;
}

void aurora_ext_controller_release(void *controller) {
    if (!controller) return;
    if (s_extDelegates) {
        [s_extDelegates removeObjectForKey:ptrKey(controller)];
    }
    id obj = (__bridge_transfer id)controller;
    (void)obj; // Release
}

void *aurora_ext_load_extension(void *controller, const char *appexPath) {
    if (@available(macOS 15.4, *)) {
        if (!controller || !appexPath) return NULL;

        id ctrl = (__bridge id)controller;
        id extension = aurora_create_web_extension(appexPath);
        if (!extension) return NULL;

        // Create context: WKWebExtensionContext contextForExtension:
        Class ctxClass = objc_getClass("WKWebExtensionContext");
        if (!ctxClass) return NULL;

        SEL ctxSel = sel_registerName("contextForExtension:");
        if (![ctxClass respondsToSelector:ctxSel]) return NULL;

        typedef id (*CtxCreateFn)(Class, SEL, id);
        id context = ((CtxCreateFn)objc_msgSend)(ctxClass, ctxSel, extension);
        if (!context) return NULL;

        // Make extension inspectable for debugging
        SEL setInspectSel = sel_registerName("setInspectable:");
        if ([context respondsToSelector:setInspectSel]) {
            typedef void (*SetBoolFn)(id, SEL, BOOL);
            ((SetBoolFn)objc_msgSend)(context, setInspectSel, YES);
        }

        // Load context into controller
        SEL loadSel = sel_registerName("loadExtensionContext:error:");
        if (![ctrl respondsToSelector:loadSel]) return NULL;

        NSError *error = nil;
        typedef BOOL (*LoadFn)(id, SEL, id, NSError **);
        BOOL success = ((LoadFn)objc_msgSend)(ctrl, loadSel, context, &error);

        if (!success || error) {
            fprintf(stderr, "[AuroraBridge] Failed to load extension context: %s\n",
                    error ? error.localizedDescription.UTF8String : "unknown");
            return NULL;
        }

        // Grant all permissions and match patterns from the manifest
        {
            // Grant requested permissions
            SEL reqPermsSel = sel_registerName("requestedPermissions");
            if ([extension respondsToSelector:reqPermsSel]) {
                typedef id (*PermsFn)(id, SEL);
                NSSet *perms = ((PermsFn)objc_msgSend)(extension, reqPermsSel);
                SEL grantSel = sel_registerName("setPermissionStatus:forPermission:expirationDate:");
                if ([context respondsToSelector:grantSel]) {
                    typedef void (*GrantFn)(id, SEL, NSInteger, id, id);
                    for (NSString *perm in perms) {
                        ((GrantFn)objc_msgSend)(context, grantSel, 3, perm, [NSDate distantFuture]);
                        fprintf(stderr, "[AuroraBridge] Granted permission: %s\n", perm.UTF8String);
                    }
                }
            }

            // Grant optional permissions
            SEL optPermsSel = sel_registerName("optionalPermissions");
            if ([extension respondsToSelector:optPermsSel]) {
                typedef id (*PermsFn)(id, SEL);
                NSSet *optPerms = ((PermsFn)objc_msgSend)(extension, optPermsSel);
                SEL grantSel = sel_registerName("setPermissionStatus:forPermission:expirationDate:");
                if ([context respondsToSelector:grantSel] && optPerms) {
                    typedef void (*GrantFn)(id, SEL, NSInteger, id, id);
                    for (NSString *perm in optPerms) {
                        ((GrantFn)objc_msgSend)(context, grantSel, 3, perm, [NSDate distantFuture]);
                        fprintf(stderr, "[AuroraBridge] Granted optional permission: %s\n", perm.UTF8String);
                    }
                }
            }

            // Grant requested match patterns (URL access)
            SEL reqPatternsSel = sel_registerName("requestedPermissionMatchPatterns");
            if ([extension respondsToSelector:reqPatternsSel]) {
                typedef id (*PatFn)(id, SEL);
                NSSet *patterns = ((PatFn)objc_msgSend)(extension, reqPatternsSel);
                SEL grantPatSel = sel_registerName("setPermissionStatus:forMatchPattern:expirationDate:");
                if ([context respondsToSelector:grantPatSel] && patterns) {
                    typedef void (*GrantPatFn)(id, SEL, NSInteger, id, id);
                    for (id pattern in patterns) {
                        ((GrantPatFn)objc_msgSend)(context, grantPatSel, 3, pattern, [NSDate distantFuture]);
                        fprintf(stderr, "[AuroraBridge] Granted match pattern: %s\n", [pattern description].UTF8String);
                    }
                }
            }

            // Grant all-URLs access
            SEL setAllURLsSel = sel_registerName("setHasAccessToAllURLs:");
            if ([context respondsToSelector:setAllURLsSel]) {
                typedef void (*SetBoolFn)(id, SEL, BOOL);
                ((SetBoolFn)objc_msgSend)(context, setAllURLsSel, YES);
            }
        }

        // Load the background content (service worker / background page)
        // This is essential — the background script sets up popups, content scripts, etc.
        SEL loadBGSel = sel_registerName("loadBackgroundContentWithCompletionHandler:");
        if ([context respondsToSelector:loadBGSel]) {
            fprintf(stderr, "[AuroraBridge] Loading background content for extension...\n");
            typedef void (*LoadBGFn)(id, SEL, id);
            ((LoadBGFn)objc_msgSend)(context, loadBGSel, ^(NSError *bgError) {
                if (bgError) {
                    fprintf(stderr, "[AuroraBridge] Background content load error: %s\n",
                            bgError.localizedDescription.UTF8String);
                } else {
                    fprintf(stderr, "[AuroraBridge] Background content loaded successfully\n");
                }
            });
        } else {
            fprintf(stderr, "[AuroraBridge] No loadBackgroundContentWithCompletionHandler: available\n");
        }

        return (__bridge_retained void *)context;
    }
    return NULL;
}

void aurora_ext_unload_extension(void *controller, void *contextPtr) {
    if (@available(macOS 15.4, *)) {
        if (!controller || !contextPtr) return;

        id ctrl = (__bridge id)controller;
        id context = (__bridge id)contextPtr;

        SEL unloadSel = sel_registerName("unloadExtensionContext:error:");
        if ([ctrl respondsToSelector:unloadSel]) {
            NSError *error = nil;
            typedef BOOL (*UnloadFn)(id, SEL, id, NSError **);
            ((UnloadFn)objc_msgSend)(ctrl, unloadSel, context, &error);
        }

        // Release the context
        id released = (__bridge_transfer id)contextPtr;
        (void)released;
    }
}

#pragma mark - Extension Metadata Queries

const char *aurora_ext_get_display_name(const char *appexPath) {
    if (@available(macOS 15.4, *)) {
        id extension = aurora_create_web_extension(appexPath);
        if (!extension) return NULL;

        SEL nameSel = sel_registerName("displayName");
        if (![extension respondsToSelector:nameSel]) return NULL;

        typedef id (*NameFn)(id, SEL);
        NSString *name = ((NameFn)objc_msgSend)(extension, nameSel);
        return name ? strdup([name UTF8String]) : NULL;
    }
    return NULL;
}

const char *aurora_ext_get_version(const char *appexPath) {
    if (@available(macOS 15.4, *)) {
        id extension = aurora_create_web_extension(appexPath);
        if (!extension) return NULL;

        SEL verSel = sel_registerName("version");
        if (![extension respondsToSelector:verSel]) return NULL;

        typedef id (*VerFn)(id, SEL);
        NSString *ver = ((VerFn)objc_msgSend)(extension, verSel);
        return ver ? strdup([ver UTF8String]) : NULL;
    }
    return NULL;
}

void *aurora_ext_get_icon(const char *appexPath, int size) {
    if (@available(macOS 15.4, *)) {
        id extension = aurora_create_web_extension(appexPath);
        if (!extension) return NULL;

        SEL iconSel = sel_registerName("iconForSize:");
        if (![extension respondsToSelector:iconSel]) return NULL;

        typedef id (*IconFn)(id, SEL, CGSize);
        id icon = ((IconFn)objc_msgSend)(extension, iconSel, CGSizeMake(size, size));
        if (!icon) return NULL;

        return (__bridge_retained void *)icon;
    }
    return NULL;
}

const char *aurora_ext_get_permissions(const char *appexPath) {
    if (@available(macOS 15.4, *)) {
        id extension = aurora_create_web_extension(appexPath);
        if (!extension) return NULL;

        SEL permsSel = sel_registerName("requestedPermissions");
        if (![extension respondsToSelector:permsSel]) return NULL;

        typedef id (*PermsFn)(id, SEL);
        NSSet *perms = ((PermsFn)objc_msgSend)(extension, permsSel);
        if (!perms) return strdup("[]");

        NSArray *arr = [perms allObjects];
        NSData *json = [NSJSONSerialization dataWithJSONObject:arr options:0 error:nil];
        if (!json) return strdup("[]");

        NSString *str = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        return str ? strdup([str UTF8String]) : strdup("[]");
    }
    return NULL;
}

const char *aurora_ext_get_description(const char *appexPath) {
    if (@available(macOS 15.4, *)) {
        id extension = aurora_create_web_extension(appexPath);
        if (!extension) return NULL;

        SEL descSel = sel_registerName("displayDescription");
        if (![extension respondsToSelector:descSel]) return NULL;

        typedef id (*DescFn)(id, SEL);
        NSString *desc = ((DescFn)objc_msgSend)(extension, descSel);
        return desc ? strdup([desc UTF8String]) : NULL;
    }
    return NULL;
}

#pragma mark - Permission Management

void aurora_ext_grant_permissions(void *contextPtr, const char *permissionsJSON) {
    if (@available(macOS 15.4, *)) {
        if (!contextPtr || !permissionsJSON) return;

        id context = (__bridge id)contextPtr;
        NSData *data = [NSData dataWithBytes:permissionsJSON length:strlen(permissionsJSON)];
        NSArray *permsArray = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (!permsArray) return;

        // Grant each permission individually — the API uses singular "forPermission:"
        SEL grantSel = sel_registerName("setPermissionStatus:forPermission:expirationDate:");
        if ([context respondsToSelector:grantSel]) {
            typedef void (*GrantFn)(id, SEL, NSInteger, id, id);
            for (NSString *perm in permsArray) {
                // 3 = WKWebExtensionContextPermissionStatusGrantedExplicitly
                ((GrantFn)objc_msgSend)(context, grantSel, 3, perm, [NSDate distantFuture]);
                fprintf(stderr, "[AuroraBridge] Granted permission: %s\n", perm.UTF8String);
            }
        }
    }
}

// Grant all permissions and match patterns on a context. Call after loadExtensionContext:error:.
static void aurora_ext_grant_all_permissions(id context, id extension) API_AVAILABLE(macos(15.4)) {
    // Grant requested permissions
    SEL reqPermsSel = sel_registerName("requestedPermissions");
    if ([extension respondsToSelector:reqPermsSel]) {
        typedef id (*PermsFn)(id, SEL);
        NSSet *perms = ((PermsFn)objc_msgSend)(extension, reqPermsSel);

        SEL grantSel = sel_registerName("setPermissionStatus:forPermission:expirationDate:");
        if ([context respondsToSelector:grantSel]) {
            typedef void (*GrantFn)(id, SEL, NSInteger, id, id);
            for (NSString *perm in perms) {
                ((GrantFn)objc_msgSend)(context, grantSel, 3, perm, [NSDate distantFuture]);
                fprintf(stderr, "[AuroraBridge] Granted permission: %s\n", perm.UTF8String);
            }
        }
    }

    // Grant optional permissions too
    SEL optPermsSel = sel_registerName("optionalPermissions");
    if ([extension respondsToSelector:optPermsSel]) {
        typedef id (*PermsFn)(id, SEL);
        NSSet *optPerms = ((PermsFn)objc_msgSend)(extension, optPermsSel);

        SEL grantSel = sel_registerName("setPermissionStatus:forPermission:expirationDate:");
        if ([context respondsToSelector:grantSel] && optPerms) {
            typedef void (*GrantFn)(id, SEL, NSInteger, id, id);
            for (NSString *perm in optPerms) {
                ((GrantFn)objc_msgSend)(context, grantSel, 3, perm, [NSDate distantFuture]);
                fprintf(stderr, "[AuroraBridge] Granted optional permission: %s\n", perm.UTF8String);
            }
        }
    }

    // Grant requested match patterns (URL access)
    SEL reqPatternsSel = sel_registerName("requestedPermissionMatchPatterns");
    if ([extension respondsToSelector:reqPatternsSel]) {
        typedef id (*PatFn)(id, SEL);
        NSSet *patterns = ((PatFn)objc_msgSend)(extension, reqPatternsSel);

        SEL grantPatSel = sel_registerName("setPermissionStatus:forMatchPattern:expirationDate:");
        if ([context respondsToSelector:grantPatSel] && patterns) {
            typedef void (*GrantPatFn)(id, SEL, NSInteger, id, id);
            for (id pattern in patterns) {
                ((GrantPatFn)objc_msgSend)(context, grantPatSel, 3, pattern, [NSDate distantFuture]);
                fprintf(stderr, "[AuroraBridge] Granted match pattern: %s\n", [pattern description].UTF8String);
            }
        }
    }

    // Also grant all-URLs and all-hosts access
    SEL setAllURLsSel = sel_registerName("setHasAccessToAllURLs:");
    if ([context respondsToSelector:setAllURLsSel]) {
        typedef void (*SetBoolFn)(id, SEL, BOOL);
        ((SetBoolFn)objc_msgSend)(context, setAllURLsSel, YES);
    }

    SEL setAllHostsSel = sel_registerName("setHasAccessToAllHosts:");
    if ([context respondsToSelector:setAllHostsSel]) {
        typedef void (*SetBoolFn)(id, SEL, BOOL);
        ((SetBoolFn)objc_msgSend)(context, setAllHostsSel, YES);
    }
}

#pragma mark - Extension Action

void aurora_ext_perform_action(void *contextPtr, void *tabPtr) {
    if (@available(macOS 15.4, *)) {
        if (!contextPtr) return;

        id context = (__bridge id)contextPtr;
        id tab = tabPtr ? (__bridge id)tabPtr : nil;

        // Get the action for this tab
        SEL actionForTabSel = sel_registerName("actionForTab:");
        if (![context respondsToSelector:actionForTabSel]) {
            fprintf(stderr, "[AuroraBridge] No actionForTab: on context\n");
            return;
        }

        typedef id (*ActionForTabFn)(id, SEL, id);
        id action = ((ActionForTabFn)objc_msgSend)(context, actionForTabSel, tab);
        if (!action) {
            fprintf(stderr, "[AuroraBridge] actionForTab: returned nil\n");
            return;
        }

        // Log all methods on the action object (first time only)
        static BOOL didLogActionMethods = NO;
        if (!didLogActionMethods) {
            didLogActionMethods = YES;
            unsigned int count = 0;
            Method *methods = class_copyMethodList([action class], &count);
            fprintf(stderr, "[AuroraBridge] WKWebExtensionAction (%s) has %u methods:\n",
                    NSStringFromClass([action class]).UTF8String, count);
            for (unsigned int i = 0; i < count; i++) {
                fprintf(stderr, "  - %s\n", sel_getName(method_getName(methods[i])));
            }
            free(methods);
        }

        // Check if the action has a popup
        SEL hasPopupSel = sel_registerName("presentsPopup");
        if ([action respondsToSelector:hasPopupSel]) {
            typedef BOOL (*BoolFn)(id, SEL);
            BOOL presentsPopup = ((BoolFn)objc_msgSend)(action, hasPopupSel);
            fprintf(stderr, "[AuroraBridge] presentsPopup = %d\n", presentsPopup);
        }

        // Try to get the popup web view
        SEL popupWebViewSel = sel_registerName("popupWebView");
        if ([action respondsToSelector:popupWebViewSel]) {
            typedef id (*WebViewFn)(id, SEL);
            id popupWV = ((WebViewFn)objc_msgSend)(action, popupWebViewSel);
            fprintf(stderr, "[AuroraBridge] popupWebView = %s (class: %s)\n",
                    popupWV ? "exists" : "nil",
                    popupWV ? NSStringFromClass([popupWV class]).UTF8String : "n/a");

            if (popupWV) {
                // Store the popup web view in a callback or present it
                // For now, fire a notification that Swift can observe
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:@"AuroraExtensionPopupReady"
                        object:nil
                        userInfo:@{
                            @"webView": popupWV,
                            @"context": context
                        }];
                });
                return;
            }
        }

        // Check extension errors
        SEL errorsSel = sel_registerName("errors");
        if ([context respondsToSelector:errorsSel]) {
            typedef id (*ErrFn)(id, SEL);
            NSArray *errors = ((ErrFn)objc_msgSend)(context, errorsSel);
            if (errors.count > 0) {
                fprintf(stderr, "[AuroraBridge] Extension has %lu errors:\n", (unsigned long)errors.count);
                for (id err in errors) {
                    fprintf(stderr, "  - %s\n", [err description].UTF8String);
                }
            }
        }

        // Check unsupported APIs
        SEL unsupportedSel = sel_registerName("unsupportedAPIs");
        if ([context respondsToSelector:unsupportedSel]) {
            typedef id (*UnsupFn)(id, SEL);
            id unsupported = ((UnsupFn)objc_msgSend)(context, unsupportedSel);
            if (unsupported && [unsupported count] > 0) {
                fprintf(stderr, "[AuroraBridge] Unsupported APIs: %s\n",
                        [unsupported description].UTF8String);
            }
        }

        // Check granted permissions
        SEL grantedSel = sel_registerName("currentPermissions");
        if ([context respondsToSelector:grantedSel]) {
            typedef id (*PermFn)(id, SEL);
            id perms = ((PermFn)objc_msgSend)(context, grantedSel);
            fprintf(stderr, "[AuroraBridge] Current permissions: %s\n",
                    perms ? [perms description].UTF8String : "nil");
        }

        // Check background content URL
        SEL bgURLSel = sel_registerName("_backgroundContentURL");
        if ([context respondsToSelector:bgURLSel]) {
            typedef id (*URLFn)(id, SEL);
            NSURL *bgURL = ((URLFn)objc_msgSend)(context, bgURLSel);
            fprintf(stderr, "[AuroraBridge] Background content URL: %s\n",
                    bgURL ? bgURL.absoluteString.UTF8String : "nil");
        }

        // Check baseURL
        SEL baseURLSel = sel_registerName("baseURL");
        if ([context respondsToSelector:baseURLSel]) {
            typedef id (*URLFn)(id, SEL);
            NSURL *baseURL = ((URLFn)objc_msgSend)(context, baseURLSel);
            fprintf(stderr, "[AuroraBridge] Base URL: %s\n",
                    baseURL ? baseURL.absoluteString.UTF8String : "nil");
        }

        // Try performActionForTab:
        SEL performSel = sel_registerName("performActionForTab:");
        if ([context respondsToSelector:performSel]) {
            typedef void (*PerformFn)(id, SEL, id);
            ((PerformFn)objc_msgSend)(context, performSel, tab);
        }
    }
}

// Get the extension popup page URL for the browser action (returns malloc'd string or NULL)
const char *aurora_ext_get_action_popup_url(void *contextPtr) {
    if (@available(macOS 15.4, *)) {
        if (!contextPtr) return NULL;

        id context = (__bridge id)contextPtr;

        // Try to get action → popupWebViewForTab: or popupPageURL
        SEL actionSel = sel_registerName("action");
        if ([context respondsToSelector:actionSel]) {
            typedef id (*GetActionFn)(id, SEL);
            id action = ((GetActionFn)objc_msgSend)(context, actionSel);
            if (action) {
                // Check for popupURL or popupPageURL
                SEL popupURLSel = sel_registerName("popupPageURL");
                if ([action respondsToSelector:popupURLSel]) {
                    typedef id (*URLFn)(id, SEL);
                    NSURL *url = ((URLFn)objc_msgSend)(action, popupURLSel);
                    if (url) return strdup(url.absoluteString.UTF8String);
                }
                SEL popupURLSel2 = sel_registerName("popupURL");
                if ([action respondsToSelector:popupURLSel2]) {
                    typedef id (*URLFn)(id, SEL);
                    NSURL *url = ((URLFn)objc_msgSend)(action, popupURLSel2);
                    if (url) return strdup(url.absoluteString.UTF8String);
                }
            }
        }
    }
    return NULL;
}

#pragma mark - View Creation with Extension Controller

void *aurora_view_create_with_context_and_extensions(WKContextRef context, void *extController) {
    if (@available(macOS 15.4, *)) {
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
                }
            }

            // Enable JavaScript and media playback on the preferences
            SEL prefsSel = sel_registerName("preferences");
            if ([config respondsToSelector:prefsSel]) {
                typedef id (*PrefsFn)(id, SEL);
                id prefs = ((PrefsFn)objc_msgSend)(config, prefsSel);
                if (prefs) {
                    SEL jsEnabledSel = sel_registerName("setJavaScriptEnabled:");
                    if ([prefs respondsToSelector:jsEnabledSel]) {
                        typedef void (*SetBoolFn)(id, SEL, BOOL);
                        ((SetBoolFn)objc_msgSend)(prefs, jsEnabledSel, YES);
                    }
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

            // Allow media playback without user gesture
            SEL mediaPlaybackSel = sel_registerName("setMediaTypesRequiringUserActionForPlayback:");
            if ([config respondsToSelector:mediaPlaybackSel]) {
                typedef void (*SetMediaFn)(id, SEL, NSUInteger);
                ((SetMediaFn)objc_msgSend)(config, mediaPlaybackSel, 0);
            }

            // Enable Picture-in-Picture
            SEL pipSel = sel_registerName("setAllowsPictureInPictureMediaPlayback:");
            if ([config respondsToSelector:pipSel]) {
                typedef void (*SetBoolFn)(id, SEL, BOOL);
                ((SetBoolFn)objc_msgSend)(config, pipSel, YES);
            }

            // --- Set the WKWebExtensionController on the config ---
            if (extController) {
                id ctrl = (__bridge id)extController;
                SEL setExtCtrlSel = sel_registerName("setWebExtensionController:");
                if ([config respondsToSelector:setExtCtrlSel]) {
                    typedef void (*SetExtFn)(id, SEL, id);
                    ((SetExtFn)objc_msgSend)(config, setExtCtrlSel, ctrl);
                } else {
                    fprintf(stderr, "[AuroraBridge] WARNING: WKWebViewConfiguration does not respond to setWebExtensionController:\n");
                }
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
                // Enable Web Inspector
                SEL inspectableSel = sel_registerName("setInspectable:");
                if ([wkWebView respondsToSelector:inspectableSel]) {
                    typedef void (*SetInspectableFn)(id, SEL, BOOL);
                    ((SetInspectableFn)objc_msgSend)(wkWebView, inspectableSel, YES);
                }

                // Also try _setDeveloperExtrasEnabled: on preferences
                SEL configSel = sel_registerName("configuration");
                if ([wkWebView respondsToSelector:configSel]) {
                    typedef id (*ConfigFn)(id, SEL);
                    id wkConfig = ((ConfigFn)objc_msgSend)(wkWebView, configSel);
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

                return (__bridge_retained void *)wkWebView;
            }
            fprintf(stderr, "[AuroraBridge] ERROR: WKWebView init returned nil\n");
        } @catch (NSException *e) {
            fprintf(stderr, "[AuroraBridge] EXCEPTION creating WKWebView with extensions: %s — %s\n",
                    e.name.UTF8String, e.reason.UTF8String);
        }
    }
    return NULL;
}

#pragma mark - Extension Tab Bridge Functions

void *aurora_ext_tab_create(void *wkWebView) {
    if (@available(macOS 15.4, *)) {
        if (!wkWebView) return NULL;

        AuroraExtensionTab *tab = [[AuroraExtensionTab alloc] init];
        tab.webView = (__bridge NSView *)wkWebView;
        tab.tabSize = CGSizeMake(800, 600);

        if (!s_extTabs) s_extTabs = [NSMutableDictionary new];
        void *retained = (__bridge_retained void *)tab;
        s_extTabs[ptrKey(retained)] = tab;

        return retained;
    }
    return NULL;
}

void aurora_ext_tab_release(void *tab) {
    if (!tab) return;
    if (s_extTabs) [s_extTabs removeObjectForKey:ptrKey(tab)];
    id obj = (__bridge_transfer id)tab;
    (void)obj;
}

void aurora_ext_tab_set_url(void *tab, const char *url) {
    if (@available(macOS 15.4, *)) {
        if (!tab) return;
        AuroraExtensionTab *t = (__bridge AuroraExtensionTab *)tab;
        t.tabURL = url ? [NSURL URLWithString:[NSString stringWithUTF8String:url]] : nil;
    }
}

void aurora_ext_tab_set_title(void *tab, const char *title) {
    if (@available(macOS 15.4, *)) {
        if (!tab) return;
        AuroraExtensionTab *t = (__bridge AuroraExtensionTab *)tab;
        t.tabTitle = title ? [NSString stringWithUTF8String:title] : nil;
    }
}

void aurora_ext_tab_set_active(void *tab, bool active) {
    if (@available(macOS 15.4, *)) {
        if (!tab) return;
        AuroraExtensionTab *t = (__bridge AuroraExtensionTab *)tab;
        t.isTabActive = active;
    }
}

void aurora_ext_tab_set_pinned(void *tab, bool pinned) {
    if (@available(macOS 15.4, *)) {
        if (!tab) return;
        AuroraExtensionTab *t = (__bridge AuroraExtensionTab *)tab;
        t.isTabPinned = pinned;
    }
}

void aurora_ext_tab_set_loading(void *tab, bool loading) {
    if (@available(macOS 15.4, *)) {
        if (!tab) return;
        AuroraExtensionTab *t = (__bridge AuroraExtensionTab *)tab;
        t.isTabLoading = loading;
    }
}

void aurora_ext_tab_set_window(void *tab, void *window) {
    if (@available(macOS 15.4, *)) {
        if (!tab) return;
        AuroraExtensionTab *t = (__bridge AuroraExtensionTab *)tab;
        t.containingWindow = window ? (__bridge AuroraExtensionWindow *)window : nil;
    }
}

void aurora_ext_tab_set_size(void *tab, double width, double height) {
    if (@available(macOS 15.4, *)) {
        if (!tab) return;
        AuroraExtensionTab *t = (__bridge AuroraExtensionTab *)tab;
        t.tabSize = CGSizeMake(width, height);
    }
}

#pragma mark - Extension Window Bridge Functions

void *aurora_ext_window_create(void) {
    if (@available(macOS 15.4, *)) {
        AuroraExtensionWindow *window = [[AuroraExtensionWindow alloc] init];

        if (!s_extWindows) s_extWindows = [NSMutableDictionary new];
        void *retained = (__bridge_retained void *)window;
        s_extWindows[ptrKey(retained)] = window;

        return retained;
    }
    return NULL;
}

void aurora_ext_window_release(void *window) {
    if (!window) return;
    if (s_extWindows) [s_extWindows removeObjectForKey:ptrKey(window)];
    id obj = (__bridge_transfer id)window;
    (void)obj;
}

void aurora_ext_window_add_tab(void *window, void *tab) {
    if (@available(macOS 15.4, *)) {
        if (!window || !tab) return;
        AuroraExtensionWindow *w = (__bridge AuroraExtensionWindow *)window;
        AuroraExtensionTab *t = (__bridge AuroraExtensionTab *)tab;
        if (![w.windowTabs containsObject:t]) {
            [w.windowTabs addObject:t];
        }
        t.containingWindow = w;
    }
}

void aurora_ext_window_remove_tab(void *window, void *tab) {
    if (@available(macOS 15.4, *)) {
        if (!window || !tab) return;
        AuroraExtensionWindow *w = (__bridge AuroraExtensionWindow *)window;
        AuroraExtensionTab *t = (__bridge AuroraExtensionTab *)tab;
        [w.windowTabs removeObject:t];
        if (w.activeTab == t) w.activeTab = nil;
        t.containingWindow = nil;
    }
}

void aurora_ext_window_set_active_tab(void *window, void *tab) {
    if (@available(macOS 15.4, *)) {
        if (!window) return;
        AuroraExtensionWindow *w = (__bridge AuroraExtensionWindow *)window;
        w.activeTab = tab ? (__bridge AuroraExtensionTab *)tab : nil;
    }
}

void aurora_ext_window_set_active(void *window, bool active) {
    if (@available(macOS 15.4, *)) {
        if (!window) return;
        AuroraExtensionWindow *w = (__bridge AuroraExtensionWindow *)window;
        w.isWindowActive = active;
    }
}

void aurora_ext_window_set_frame(void *window, double x, double y, double w, double h) {
    if (@available(macOS 15.4, *)) {
        if (!window) return;
        AuroraExtensionWindow *win = (__bridge AuroraExtensionWindow *)window;
        win.windowFrame = NSMakeRect(x, y, w, h);
    }
}

#pragma mark - Controller Event Notifications

void aurora_ext_controller_did_open_tab(void *controller, void *tab) {
    if (@available(macOS 15.4, *)) {
        if (!controller || !tab) return;
        id ctrl = (__bridge id)controller;
        id t = (__bridge id)tab;
        SEL sel = sel_registerName("didOpenTab:");
        if ([ctrl respondsToSelector:sel]) {
            typedef void (*DidOpenFn)(id, SEL, id);
            ((DidOpenFn)objc_msgSend)(ctrl, sel, t);
        }
    }
}

void aurora_ext_controller_did_close_tab(void *controller, void *tab) {
    if (@available(macOS 15.4, *)) {
        if (!controller || !tab) return;
        id ctrl = (__bridge id)controller;
        id t = (__bridge id)tab;
        SEL sel = sel_registerName("didCloseTab:");
        if ([ctrl respondsToSelector:sel]) {
            typedef void (*DidCloseFn)(id, SEL, id);
            ((DidCloseFn)objc_msgSend)(ctrl, sel, t);
        }
    }
}

void aurora_ext_controller_did_activate_tab(void *controller, void *tab) {
    if (@available(macOS 15.4, *)) {
        if (!controller || !tab) return;
        id ctrl = (__bridge id)controller;
        id t = (__bridge id)tab;
        SEL sel = sel_registerName("didActivateTab:");
        if ([ctrl respondsToSelector:sel]) {
            typedef void (*DidActivateFn)(id, SEL, id);
            ((DidActivateFn)objc_msgSend)(ctrl, sel, t);
        }
    }
}

void aurora_ext_controller_did_open_window(void *controller, void *window) {
    if (@available(macOS 15.4, *)) {
        if (!controller || !window) return;
        id ctrl = (__bridge id)controller;
        id w = (__bridge id)window;

        // Also register window with the delegate
        AuroraExtensionControllerDelegate *delegate = s_extDelegates[ptrKey(controller)];
        if (delegate && ![delegate.windows containsObject:w]) {
            [delegate.windows addObject:w];
        }

        SEL sel = sel_registerName("didOpenWindow:");
        if ([ctrl respondsToSelector:sel]) {
            typedef void (*DidOpenFn)(id, SEL, id);
            ((DidOpenFn)objc_msgSend)(ctrl, sel, w);
        }
    }
}

void aurora_ext_controller_did_close_window(void *controller, void *window) {
    if (@available(macOS 15.4, *)) {
        if (!controller || !window) return;
        id ctrl = (__bridge id)controller;
        id w = (__bridge id)window;

        AuroraExtensionControllerDelegate *delegate = s_extDelegates[ptrKey(controller)];
        if (delegate) {
            [delegate.windows removeObject:w];
        }

        SEL sel = sel_registerName("didCloseWindow:");
        if ([ctrl respondsToSelector:sel]) {
            typedef void (*DidCloseFn)(id, SEL, id);
            ((DidCloseFn)objc_msgSend)(ctrl, sel, w);
        }
    }
}

void aurora_ext_controller_did_focus_window(void *controller, void *window) {
    if (@available(macOS 15.4, *)) {
        if (!controller || !window) return;
        id ctrl = (__bridge id)controller;
        id w = (__bridge id)window;
        SEL sel = sel_registerName("didFocusWindow:");
        if ([ctrl respondsToSelector:sel]) {
            typedef void (*DidFocusFn)(id, SEL, id);
            ((DidFocusFn)objc_msgSend)(ctrl, sel, w);
        }
    }
}

#pragma mark - Controller Delegate Callbacks

void aurora_ext_controller_set_callbacks(void *controller, void *swiftCtx,
    AuroraExtPermissionCallback onPermPrompt,
    AuroraExtTabActionCallback onAction) {
    if (@available(macOS 15.4, *)) {
        if (!controller) return;
        AuroraExtensionControllerDelegate *delegate = s_extDelegates[ptrKey(controller)];
        if (delegate) {
            delegate.swiftContext = swiftCtx;
            delegate.permissionCallback = onPermPrompt;
            delegate.actionCallback = onAction;
        }
    }
}
