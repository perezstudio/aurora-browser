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

// Set a custom user agent on a live WKWebView.
void aurora_view_set_custom_user_agent(void *wkView, const char *userAgent);

// ---------------------------------------------------------------------------
// Extension support — user scripts, content rules, and script message handlers
// ---------------------------------------------------------------------------

// Add a WKUserScript to a live view's WKUserContentController.
// injectionTime: 0 = WKUserScriptInjectionTimeAtDocumentStart,
//                1 = WKUserScriptInjectionTimeAtDocumentEnd
void aurora_view_add_user_script(void *wkView, const char *source, int injectionTime, bool mainFrameOnly);

// Remove all user scripts from the view's content controller.
// NOTE: WKUserContentController does not support removing individual scripts.
// After calling this, re-add the image compat script and any extension scripts.
void aurora_view_remove_all_user_scripts(void *wkView);

// Re-inject the built-in image compatibility script onto a view.
// Call after aurora_view_remove_all_user_scripts to restore base functionality.
void aurora_view_reinject_image_compat_script(void *wkView);

// Compile a WKContentRuleList from a JSON string (async).
// The callback fires on the main thread with the compiled rule list pointer
// (or NULL on failure) and an error message (or NULL on success).
typedef void (*AuroraContentRuleCallback)(void *context, void *ruleList, const char *error);
void aurora_compile_content_rules(const char *identifier,
                                  const char *jsonRules,
                                  void *context,
                                  AuroraContentRuleCallback callback);

// Add a compiled WKContentRuleList to a view's content controller.
void aurora_view_add_content_rule_list(void *wkView, void *ruleList);

// Remove all content rule lists from a view's content controller.
void aurora_view_remove_all_content_rule_lists(void *wkView);

// Script message handler callback — called when JS posts a message.
// messageName is the handler name, messageBody is the JSON-serialized message.
typedef void (*AuroraScriptMessageCallback)(void *context, const char *messageName, const char *messageBody);

// Register a named script message handler on the view's content controller.
// JS calls: window.webkit.messageHandlers.<name>.postMessage(...)
void aurora_view_add_script_message_handler(void *wkView,
                                             const char *name,
                                             void *context,
                                             AuroraScriptMessageCallback callback);

// Remove a named script message handler from the view's content controller.
void aurora_view_remove_script_message_handler(void *wkView, const char *name);

// ---------------------------------------------------------------------------
// Safari Web Extension support (macOS 15.4+)
// ---------------------------------------------------------------------------

// Extension controller — manages loaded extensions for a profile.
// Returns a WKWebExtensionController* (retained) or NULL if unavailable.
void *aurora_ext_controller_create(void);
void aurora_ext_controller_release(void *controller);

// Load extension from .appex bundle path into a controller.
// Returns a WKWebExtensionContext* (retained) or NULL on error.
void *aurora_ext_load_extension(void *controller, const char *appexPath);

// Unload an extension context from its controller.
void aurora_ext_unload_extension(void *controller, void *contextPtr);

// Query extension metadata from .appex path (creates temporary WKWebExtension).
// Returned strings are malloc'd — caller must free().
const char *aurora_ext_get_display_name(const char *appexPath);
const char *aurora_ext_get_version(const char *appexPath);
// Returns NSImage* (retained) or NULL.
void *aurora_ext_get_icon(const char *appexPath, int size);
// Returns JSON array string of requested permissions. Caller must free().
const char *aurora_ext_get_permissions(const char *appexPath);
// Returns the extension description. Caller must free().
const char *aurora_ext_get_description(const char *appexPath);

// Grant permissions on a loaded extension context.
// permissionsJSON is a JSON array of permission strings.
void aurora_ext_grant_permissions(void *contextPtr, const char *permissionsJSON);

// View creation with extension controller on config.
// The controller's presence on the WKWebViewConfiguration enables extension features.
void *aurora_view_create_with_context_and_extensions(WKContextRef context, void *extController);

// --- Extension Tab (conforms to WKWebExtensionTab) ---
void *aurora_ext_tab_create(void *wkWebView);
void aurora_ext_tab_release(void *tab);
void aurora_ext_tab_set_url(void *tab, const char *url);
void aurora_ext_tab_set_title(void *tab, const char *title);
void aurora_ext_tab_set_active(void *tab, bool active);
void aurora_ext_tab_set_pinned(void *tab, bool pinned);
void aurora_ext_tab_set_loading(void *tab, bool loading);
void aurora_ext_tab_set_window(void *tab, void *window);
void aurora_ext_tab_set_size(void *tab, double width, double height);

// --- Extension Window (conforms to WKWebExtensionWindow) ---
void *aurora_ext_window_create(void);
void aurora_ext_window_release(void *window);
void aurora_ext_window_add_tab(void *window, void *tab);
void aurora_ext_window_remove_tab(void *window, void *tab);
void aurora_ext_window_set_active_tab(void *window, void *tab);
void aurora_ext_window_set_active(void *window, bool active);
void aurora_ext_window_set_frame(void *window, double x, double y, double w, double h);

// --- Controller event notifications ---
void aurora_ext_controller_did_open_tab(void *controller, void *tab);
void aurora_ext_controller_did_close_tab(void *controller, void *tab);
void aurora_ext_controller_did_activate_tab(void *controller, void *tab);
void aurora_ext_controller_did_open_window(void *controller, void *window);
void aurora_ext_controller_did_close_window(void *controller, void *window);
void aurora_ext_controller_did_focus_window(void *controller, void *window);

// --- Controller delegate callbacks ---
typedef void (*AuroraExtPermissionCallback)(void *ctx, const char *extDisplayName, const char *permsJSON);
typedef void (*AuroraExtTabActionCallback)(void *ctx, void *extContext, void *tabRef);

void aurora_ext_controller_set_callbacks(void *controller, void *swiftCtx,
    AuroraExtPermissionCallback onPermPrompt,
    AuroraExtTabActionCallback onAction);

// Perform the extension's browser action (popup or background action) for a tab.
void aurora_ext_perform_action(void *contextPtr, void *tabPtr);
// Get the popup page URL for the extension's action (returns malloc'd or NULL).
const char *aurora_ext_get_action_popup_url(void *contextPtr);

// Check if the Safari Web Extension APIs are available at runtime.
bool aurora_ext_is_available(void);

#endif /* AuroraWebKitBridge_h */
