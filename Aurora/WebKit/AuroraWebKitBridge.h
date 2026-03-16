#ifndef AuroraWebKitBridge_h
#define AuroraWebKitBridge_h

#include <stdbool.h>
#include <stdint.h>

// Opaque WebKit2 C API types — these exist in WebKit.framework but are not
// exposed in public SDK headers. We declare them as opaque pointers and
// resolve the actual functions at runtime via dlsym.
typedef const void *WKContextRef;
typedef const void *WKPageConfigurationRef;
typedef const void *WKPageRef;
typedef const void *WKViewRef;
typedef const void *WKURLRef;
typedef const void *WKStringRef;
typedef const void *WKInspectorRef;
typedef const void *WKPageGroupRef;
typedef const void *WKPreferencesRef;
typedef const void *WKPageNavigationClientV3;

// Navigation callback types
typedef void (*AuroraNavigationCallback)(const void *clientInfo,
                                         const char *url,
                                         const char *title,
                                         double progress,
                                         bool isLoading,
                                         bool canGoBack,
                                         bool canGoForward);

// Initialize the bridge — must be called once before any other function.
// Returns true on success, false if required symbols could not be loaded.
bool aurora_bridge_init(void);

// Context (process pool) management
WKContextRef aurora_context_create(void);
void aurora_context_release(WKContextRef context);

// Associate a stable profile UUID with a context for persistent data store creation.
// Must be called after aurora_context_create and before the first view is created.
void aurora_context_set_profile_uuid(WKContextRef context, const char *uuidString);

// Page configuration
WKPageConfigurationRef aurora_page_config_create(WKContextRef context);
void aurora_page_config_release(WKPageConfigurationRef config);

// View creation — returns a WKWebView* (NSView subclass) via ObjC runtime.
// Each call creates a separate WKProcessPool for per-Space isolation.
void *aurora_view_create_with_context(WKContextRef context);

// Page reference — extract WKPageRef from a WKWebView via private SPI
WKPageRef aurora_view_get_page(void *wkView);

// C API page operations (require valid WKPageRef)
void aurora_page_load_url(WKPageRef page, const char *url);
void aurora_page_load_html(WKPageRef page, const char *html, const char *baseURL);
void aurora_page_go_back(WKPageRef page);
void aurora_page_go_forward(WKPageRef page);
void aurora_page_reload(WKPageRef page);
void aurora_page_stop_loading(WKPageRef page);
const char *aurora_page_get_url(WKPageRef page);
const char *aurora_page_get_title(WKPageRef page);
double aurora_page_get_estimated_progress(WKPageRef page);
bool aurora_page_is_loading(WKPageRef page);
bool aurora_page_can_go_back(WKPageRef page);
bool aurora_page_can_go_forward(WKPageRef page);

// ObjC-based view operations — direct WKWebView method calls.
// Use these when C API page operations are unavailable.
void aurora_view_load_url(void *wkView, const char *url);
void aurora_view_load_html_string(void *wkView, const char *html, const char *baseURL);
void aurora_view_go_back(void *wkView);
void aurora_view_go_forward(void *wkView);
void aurora_view_reload(void *wkView);
void aurora_view_stop_loading(void *wkView);
const char *aurora_view_get_url(void *wkView);
const char *aurora_view_get_title(void *wkView);
double aurora_view_get_estimated_progress(void *wkView);
bool aurora_view_is_loading(void *wkView);
bool aurora_view_can_go_back(void *wkView);
bool aurora_view_can_go_forward(void *wkView);

// C API Web Inspector (require valid WKPageRef)
void aurora_inspector_show(WKPageRef page);
void aurora_inspector_close(WKPageRef page);
void aurora_inspector_attach(WKPageRef page);
void aurora_inspector_detach(WKPageRef page);
bool aurora_inspector_is_visible(WKPageRef page);
bool aurora_inspector_is_attached(WKPageRef page);

// ObjC-based Web Inspector — via WKWebView _inspector SPI
void aurora_view_inspector_show(void *wkView);
void aurora_view_inspector_close(void *wkView);
void aurora_view_inspector_attach(void *wkView);
void aurora_view_inspector_detach(void *wkView);
bool aurora_view_inspector_is_visible(void *wkView);

// Navigation delegate — installs callbacks that fire on navigation events.
// clientInfo is passed back to the callback (typically a pointer to your Swift object).
void aurora_page_install_navigation_callbacks(WKPageRef page,
                                               void *clientInfo,
                                               AuroraNavigationCallback onStateChanged);

#endif /* AuroraWebKitBridge_h */
