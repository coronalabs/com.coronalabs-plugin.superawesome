//----------------------------------------------------------------------------
// SuperAwesomeLibrary.mm
//
// Copyright (c) 2016 Corona Labs. All rights reserved.
//----------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "CoronaRuntime.h"
#import "CoronaAssert.h"
#import "CoronaEvent.h"
#import "CoronaLua.h"
#import "CoronaLuaIOS.h"
#import "CoronaLibrary.h"

#import "SuperAwesomeLibrary.h"
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <SuperAwesome/SuperAwesome.h>
#import <SuperAwesome/SuperAwesome-Swift.h>


// some macros to make life easier, and code more readable
#define UTF8StringWithFormat(format, ...) [[NSString stringWithFormat:format, ##__VA_ARGS__] UTF8String]
#define MsgFormat(format, ...) [NSString stringWithFormat:format, ##__VA_ARGS__]
#define UTF8IsEqual(utf8str1, utf8str2) (strcmp(utf8str1, utf8str2) == 0)

// ----------------------------------------------------------------------------
// Plugin Constants
// ----------------------------------------------------------------------------

#define PLUGIN_NAME        "plugin.superawesome"
#define PLUGIN_VERSION     "2.0.8"
#define PLUGIN_SDK_VERSION "8.3.6" // no API to get SDK version (yet)

static const char EVENT_NAME[]    = "adsRequest";
static const char PROVIDER_NAME[] = "superawesome";

// ad types
static const char TYPE_BANNER[]       = "banner";
static const char TYPE_INTERSTITIAL[] = "interstitial";
static const char TYPE_VIDEO[]        = "video";
// App Wall isn't implemented as Google Play resticts usage for child-directed apps

// valid ad types
static const NSArray *validAdTypes = @[
  @(TYPE_BANNER),
  @(TYPE_INTERSTITIAL),
  @(TYPE_VIDEO)
];

// banner sizes
static const char BANNER_50[]  = "BANNER_50";
static const char BANNER_90[]  = "BANNER_90";
static const char BANNER_250[] = "BANNER_250";

// banner alignment
static const char BANNER_ALIGN_TOP[]    = "top";
static const char BANNER_ALIGN_CENTER[] = "center";
static const char BANNER_ALIGN_BOTTOM[] = "bottom";

// valid ad types
static const NSArray *validBannerPositions = @[
  @(BANNER_ALIGN_TOP),
  @(BANNER_ALIGN_CENTER),
  @(BANNER_ALIGN_BOTTOM)
];

// ad orientations
static const char LOCK_PORTRAIT[]  = "portrait";
static const char LOCK_LANDSCAPE[] = "landscape";

// event keys
static const char CORONA_EVENT_PLACEMENTID_KEY[] = "placementId";

// event phases
static NSString * const PHASE_INIT           = @"init";
static NSString * const PHASE_LOADED         = @"loaded";
static NSString * const PHASE_DISPLAYED      = @"displayed";
static NSString * const PHASE_REFRESHED      = @"refreshed";
static NSString * const PHASE_PLAYBACK_ENDED = @"playbackEnded";
static NSString * const PHASE_FAILED         = @"failed";
static NSString * const PHASE_CLOSED         = @"closed";
static NSString * const PHASE_HIDDEN         = @"hidden";
static NSString * const PHASE_CLICKED        = @"clicked";

// response codes
static NSString * const RESPONSE_LOADFAILED     = @"failedToLoad";
static NSString * const RESPONSE_SHOWFAILED     = @"failedToShow";
static NSString * const RESPONSE_ALREADY_LOADED = @"alreadyLoaded";
static NSString * const RESPONSE_NOADS          = @"noAdsAvailable";

// message constants
static NSString * const ERROR_MSG   = @"ERROR: ";
static NSString * const WARNING_MSG = @"WARNING: ";

// saved objects (apiKey, ad state, etc)
static NSMutableDictionary *superAwesomeObjects;

// ad dictionary keys
static NSString * const Y_RATIO_KEY  = @"yRatio";                // used to calculate Corona -> UIKit coordinate ratio
static NSString * const TESTMODE_KEY = @"testMode";

// ----------------------------------------------------------------------------
// plugin class and delegate definitions
// ----------------------------------------------------------------------------

@interface CoronaSuperAwesomeAdInstance: NSObject

@property (nonatomic, strong) NSObject *adInstance;
@property (nonatomic, copy)   NSString *adType;
@property (nonatomic, assign) CGFloat  height;

- (instancetype)initWithAd:(NSObject *)adInstance adType:(NSString *)adType;
- (instancetype)initWithAd:(NSObject *)adInstance adType:(NSString *)adType height:(CGFloat)height;

@end

// ----------------------------------------------------------------------------
typedef void (^_Nonnull sacallback)(NSInteger placementId, SAEvent event);
@interface SuperAwesomeDelegate: NSObject

@property (nonatomic, assign) CoronaLuaRef      coronaListener;
@property (nonatomic, weak)   id<CoronaRuntime> coronaRuntime;
@property (nonatomic, copy)   sacallback        saInterstitialCallback;
@property (nonatomic, copy)   sacallback        saVideoCallback;
@property (nonatomic, copy)   sacallback       saBannerCallback;

- (void)dispatchLuaEvent:(NSDictionary *)dict;

@end

//----------------------------------------------------------------------------

class SuperAwesomeLibrary
{
public:
		typedef SuperAwesomeLibrary Self;
  
public:
		static const char kName[];
  
public:
  static int Open(lua_State *L);
  static int Finalizer(lua_State *L);
  static Self *ToLibrary(lua_State *L);
  
protected:
		SuperAwesomeLibrary();
		bool Initialize(void *platformContext);
  
public:
		static int init(lua_State *L);
		static int load(lua_State *L);
		static int isLoaded(lua_State *L);
		static int show(lua_State *L);
		static int hide(lua_State *L);
  
private: // internal helper functions
  static void logMsg(lua_State *L, NSString *msgType,  NSString *errorMsg);
  static bool isSDKInitialized(lua_State *L);
  
private:
  NSString *functionSignature;               // used in logMsg to identify function
  UIViewController *coronaViewController;
};

//----------------------------------------------------------------------------

const char SuperAwesomeLibrary::kName[] = PLUGIN_NAME;
SuperAwesomeDelegate *superAwesomeDelegate = nil;

// ----------------------------------------------------------------------------
// helper functions
// ----------------------------------------------------------------------------

// log message to console
void
SuperAwesomeLibrary::logMsg(lua_State *L, NSString* msgType, NSString* errorMsg)
{
  Self *context = ToLibrary(L);
  
  if (context) {
    Self& library = *context;
    
    NSString *functionID = [library.functionSignature copy];
    if (functionID.length > 0) {
      functionID = [functionID stringByAppendingString:@", "];
    }
    
    CoronaLuaLogPrefix(L, [msgType UTF8String], UTF8StringWithFormat(@"%@%@", functionID, errorMsg));
  }
}

// check if SDK calls can be made
bool
SuperAwesomeLibrary::isSDKInitialized(lua_State *L)
{
  // has init() been called?
  if (superAwesomeDelegate.coronaListener == NULL) {
    logMsg(L, ERROR_MSG, @"superawesome.init() must be called before calling other API methods");
    return false;
  }
  
  return true;
}

// ----------------------------------------------------------------------------
// plugin implementation
// ----------------------------------------------------------------------------

SuperAwesomeLibrary::SuperAwesomeLibrary()
: coronaViewController(NULL)
{
}

bool
SuperAwesomeLibrary::Initialize(void *platformContext)
{
  bool shouldInit = (superAwesomeDelegate == nil);
  
  if (shouldInit) {
    id<CoronaRuntime> runtime = (__bridge id<CoronaRuntime>)platformContext;
    coronaViewController = runtime.appViewController;
    
    superAwesomeDelegate = [SuperAwesomeDelegate new];
    superAwesomeDelegate.coronaRuntime = runtime;
    
    superAwesomeObjects = [NSMutableDictionary new];
  }
  
  return shouldInit;
}

// Open the library
int
SuperAwesomeLibrary::Open(lua_State *L)
{
  // Register __gc callback
  const char kMetatableName[] = __FILE__; // Globally unique string to prevent collision
  CoronaLuaInitializeGCMetatable(L, kMetatableName, Finalizer);
  
  void *platformContext = CoronaLuaGetContext(L);
  
  // Set library as upvalue for each library function
  Self *library = new Self;
  
  if (library->Initialize(platformContext)) {
    // Functions in library
    static const luaL_Reg kFunctions[] = {
      {"init", init},
      {"load", load},
      {"isLoaded", isLoaded},
      {"show", show},
      {"hide", hide},
      {NULL, NULL}
    };
    
    // Register functions as closures, giving each access to the
    // 'library' instance via ToLibrary()
    {
      CoronaLuaPushUserdata(L, library, kMetatableName);
      luaL_openlib(L, kName, kFunctions, 1); // leave "library" on top of stack
    }
  }
  
  return 1;
}

int
SuperAwesomeLibrary::Finalizer(lua_State *L)
{
  Self *library = (Self *)CoronaLuaToUserdata(L, 1);
  
  [SAInterstitialAd setCallback:nil];
  [SAVideoAd setCallback:nil];
  
  [superAwesomeObjects removeAllObjects];
  
  CoronaLuaDeleteRef(L, superAwesomeDelegate.coronaListener);
  superAwesomeDelegate = nil;
  
  delete library;
  
  return 0;
}

SuperAwesomeLibrary *
SuperAwesomeLibrary::ToLibrary(lua_State *L)
{
  // library is pushed as part of the closure
  Self *library = (Self *)CoronaLuaToUserdata(L, lua_upvalueindex(1));
  return library;
}

// [Lua] superawesome.init(adListener [, options])
int
SuperAwesomeLibrary::init(lua_State *L)
{
  Self *context = ToLibrary(L);
  
  if (! context) { // abort if no valid context
    return 0;
  }
  
  Self& library = *context;
  
  library.functionSignature = @"superawesome.init(listener [, options)";
  
  // prevent init from being called twice
  if (superAwesomeDelegate.coronaListener != NULL) {
    logMsg(L, WARNING_MSG, @"init() should only be called once");
    return 0;
  }
  
  // check number of arguments
  int nargs = lua_gettop(L);
  if ((nargs < 1) || (nargs > 2)) {
    logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 or 2 arguments, got %d", nargs));
    return 0;
  }
  
  bool testMode = false;
  
  // Get listener key (required)
  if (CoronaLuaIsListener(L, 1, PROVIDER_NAME)) {
    superAwesomeDelegate.coronaListener = CoronaLuaNewRef(L, 1);
  }
  else {
    logMsg(L, ERROR_MSG, MsgFormat(@"listener expected, got: %s", luaL_typename(L, 1)));
    return 0;
  }
  
  // check for options table
  if (! lua_isnoneornil(L, 2)){
    if (lua_type(L, 2) == LUA_TTABLE) {
      // traverse all options
      for (lua_pushnil(L); lua_next(L, 2) != 0; lua_pop(L, 1)) {
        if (lua_type(L, -2) != LUA_TSTRING) {
          logMsg(L, ERROR_MSG, @"options must be a key/value table");
          return 0;
        }
        
        const char *key = lua_tostring(L, -2);
        
        if (UTF8IsEqual(key, "testMode")) {
          if (lua_type(L, -1) == LUA_TBOOLEAN) {
            testMode = lua_toboolean(L, -1);
          }
          else {
            logMsg(L, ERROR_MSG, MsgFormat(@"options.testMode (boolean) expected, got: %s", luaL_typename(L, -1)));
            return 0;
          }
        }
        else {
          logMsg(L, ERROR_MSG, MsgFormat(@"Invalid option '%s'", key));
          return 0;
        }
      }
    }
    else {
      logMsg(L, ERROR_MSG, MsgFormat(@"options (table) expected, got %s", luaL_typename(L, 2)));
      return 0;
    }
  }
    
    
    
  // set the delegates (banners are set on each instance)
  [SAInterstitialAd setCallback:superAwesomeDelegate.saInterstitialCallback];
  [SAVideoAd setCallback:superAwesomeDelegate.saVideoCallback];
  
  // save setting for future use
  superAwesomeObjects[TESTMODE_KEY] = @(testMode);
  [AwesomeAds initSDK:testMode];
  
  // log the plugin version to device console
  NSLog(@"%s: %s (SDK: %s)", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_SDK_VERSION);
  
  // send Corona Lua event
  NSDictionary *coronaEvent = @{
                                @(CoronaEventPhaseKey()) : PHASE_INIT
                                };
  [superAwesomeDelegate dispatchLuaEvent:coronaEvent];
  
  return 0;
}

// [Lua] superawesome.load(adUnitType, options)
int
SuperAwesomeLibrary::load(lua_State *L)
{
  Self *context = ToLibrary(L);
  
  if (! context) { // abort if no valid context
    return 0;
  }
  
  Self& library = *context;
  
  library.functionSignature = @"superawesome.load(adUnitType, options)";
  
  if (! isSDKInitialized(L)) {
    return 0;
  }
  
  // check number of arguments
  int nargs = lua_gettop(L);
  if ((nargs < 1) || (nargs > 3)) { // 3 for backwards compatibility with legacy API
    logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 or 2 arguments, got %d", nargs));
    return 0;
  }
		
  const char *adUnitType = NULL;
  const char *placementId = NULL;
  const char *bannerSize = BANNER_50;
  bool legacyAPI = false;
  bool bannerTransparency = false;
  
  if (lua_type(L, 1) == LUA_TSTRING) {
    adUnitType = lua_tostring(L, 1);
  }
  else {
    logMsg(L, ERROR_MSG, MsgFormat(@"adUnitType (string) expected, got: %s", luaL_typename(L, 1)));
    return 0;
  }
  
  if (lua_type(L, 2) == LUA_TSTRING) {
    placementId = lua_tostring(L, 2);
    legacyAPI = true;
  }
  else if (lua_type(L, 2) == LUA_TTABLE) {
    // traverse all options
    for (lua_pushnil(L); lua_next(L, 2) != 0; lua_pop(L, 1)) {
      if (lua_type(L, -2) != LUA_TSTRING) {
        logMsg(L, ERROR_MSG, @"options must be a key/value table");
        return 0;
      }
      
      const char *key = lua_tostring(L, -2);
      
      if (UTF8IsEqual(key, "placementId")) {
        if (lua_type(L, -1) == LUA_TSTRING) {
          placementId = lua_tostring(L, -1);
        }
        else {
          logMsg(L, ERROR_MSG, MsgFormat(@"options.placementId (string) expected, got: %s", luaL_typename(L, -1)));
          return 0;
        }
      }
      else if (UTF8IsEqual(key, "bannerSize")) {
        if (lua_type(L, -1) == LUA_TSTRING) {
          bannerSize = lua_tostring(L, -1);
        }
        else {
          logMsg(L, ERROR_MSG, MsgFormat(@"options.bannerSize (string) expected, got: %s", luaL_typename(L, -1)));
          return 0;
        }
      }
      else if (UTF8IsEqual(key, "bannerTransparency")) {
        if (lua_type(L, -1) == LUA_TBOOLEAN) {
          bannerTransparency = lua_toboolean(L, -1);
        }
        else {
          logMsg(L, ERROR_MSG, MsgFormat(@"options.bannerTransparency (boolean) expected, got: %s", luaL_typename(L, -1)));
          return 0;
        }
      }
      else {
        logMsg(L, ERROR_MSG, MsgFormat(@"Invalid option '%s'", key));
        return 0;
      }
    }
  }
  else {
    logMsg(L, ERROR_MSG, MsgFormat(@"options (table) expected, got: %s", luaL_typename(L, 2)));
    return 0;
  }
  
  if (legacyAPI) {
    if (! lua_isnoneornil(L, 3)) {
      if (lua_type(L, 3) == LUA_TTABLE) {
        // traverse all options
        for (lua_pushnil(L); lua_next(L, 3) != 0; lua_pop(L, 1)) {
          if (lua_type(L, -2) != LUA_TSTRING) {
            logMsg(L, ERROR_MSG, @"options must be a key/value table");
            return 0;
          }
          
          const char *key = lua_tostring(L, -2);
          
          if (UTF8IsEqual(key, "bannerSize")) {
            if (lua_type(L, -1) == LUA_TSTRING) {
              bannerSize = lua_tostring(L, -1);
            }
            else {
              logMsg(L, ERROR_MSG, MsgFormat(@"options.bannerSize (string) expected, got: %s", luaL_typename(L, -1)));
              return 0;
            }
          }
          else {
            logMsg(L, ERROR_MSG, MsgFormat(@"Invalid option '%s'", key));
            return 0;
          }
        }
      }
      else {
        logMsg(L, ERROR_MSG, MsgFormat(@"options (table) expected, got: %s", luaL_typename(L, 3)));
        return 0;
      }
    }
  }
  
  // validation
  if (! [validAdTypes containsObject:@(adUnitType)]) {
    logMsg(L, ERROR_MSG, MsgFormat(@"adUnitType '%s' invalid", adUnitType));
    return 0;
  }
  
  // get saved settings
  bool testMode = [superAwesomeObjects[TESTMODE_KEY] boolValue];
  
  // check old instance
  CoronaSuperAwesomeAdInstance *oldInstance = superAwesomeObjects[@(placementId)];
  if (oldInstance != nil) {
    if (! [oldInstance.adType isEqualToString:@(adUnitType)]) {
      logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' is not of type %s", placementId, adUnitType));
      return 0;
    }
  }
  
  if (UTF8IsEqual(adUnitType, TYPE_INTERSTITIAL)) {
    [SAInterstitialAd setTestMode:testMode];
    
    // create ad info object to hold extra information not available in the SDK
    CoronaSuperAwesomeAdInstance *adInstance = [[CoronaSuperAwesomeAdInstance alloc] initWithAd:nil adType:@(TYPE_INTERSTITIAL)];
    superAwesomeObjects[@(placementId)] = adInstance;
      dispatch_async(dispatch_get_main_queue(), ^(void){
          [SAInterstitialAd load:atoi(placementId)];
      });
    
  }
  else if (UTF8IsEqual(adUnitType, TYPE_VIDEO)) {
    [SAVideoAd setTestMode:testMode];
    // create ad info object to hold extra information not available in the SDK
    CoronaSuperAwesomeAdInstance *adInstance = [[CoronaSuperAwesomeAdInstance alloc] initWithAd:nil adType:@(TYPE_VIDEO)];
    superAwesomeObjects[@(placementId)] = adInstance;
    [SAVideoAd load:atoi(placementId)];
  }
  else if (UTF8IsEqual(adUnitType, TYPE_BANNER)) {
    if (oldInstance != nil) {
      SABannerAd *banner = (SABannerAd *)oldInstance.adInstance;
      if ([banner hasAdAvailable]) {
        superAwesomeDelegate.saBannerCallback(atoi(placementId), SAEventAdAlreadyLoaded);
        return 0;
      }
    }
    
    // calculate the Corona->device coordinate ratio.
    // we don't use display.contentScaleY here as there are cases where it's difficult to get the proper values to use
    // especially on Android. uses the same formula for iOS and Android for the sake of consistency.
    // re-calculate this value on every load as the ratio can change between orientation changes
    CGPoint point1 = {0, 0};
    CGPoint point2 = {1000, 1000};
    CGPoint uikitPoint1 = [superAwesomeDelegate.coronaRuntime coronaPointToUIKitPoint: point1];
    CGPoint uikitPoint2 = [superAwesomeDelegate.coronaRuntime coronaPointToUIKitPoint: point2];
    CGFloat yRatio = (uikitPoint2.y - uikitPoint1.y) / 1000.0;
    superAwesomeObjects[Y_RATIO_KEY] = @(yRatio);
    
    // create the banner instance
    SABannerAd *banner = [SABannerAd new];
    [banner setCallback:superAwesomeDelegate.saBannerCallback];
    [banner setTestMode:testMode];
    [banner setColor:bannerTransparency];
    [banner setHidden:true];
    
    int bannerHeight = 50;
    
    if (UTF8IsEqual(bannerSize, BANNER_50)) {
      bannerHeight = 50;
    }
    else if (UTF8IsEqual(bannerSize, BANNER_90)) {
      bannerHeight = 90;
    }
    else if (UTF8IsEqual(bannerSize, BANNER_250)) {
      bannerHeight = 250;
    }
    else {
      logMsg(L, WARNING_MSG, MsgFormat(@"options.bannerSize '%s' invalid. Using default BANNER_50", bannerSize));
    }
    
    // get screen size
    CGFloat orientedWidth = library.coronaViewController.view.frame.size.width;
    
    banner.frame = CGRectMake(0, 0, orientedWidth, bannerHeight);
    [library.coronaViewController.view addSubview:banner];
    
    // create ad info object to hold extra information not available in the SDK
    CoronaSuperAwesomeAdInstance *adInstance = [[CoronaSuperAwesomeAdInstance alloc] initWithAd:banner adType:@(TYPE_BANNER) height:bannerHeight];
    superAwesomeObjects[@(placementId)] = adInstance;
    
    [banner load:atoi(placementId)];
  }
  
  return 0;
}

// [Lua] superawesome.isLoaded(placementId)
int
SuperAwesomeLibrary::isLoaded(lua_State *L)
{
  Self *context = ToLibrary(L);
  
  if (! context) { // abort if no valid context
    return 0;
  }
  
  Self& library = *context;
  
  library.functionSignature = @"superawesome.isLoaded(placementId)";
  
  if (! isSDKInitialized(L)) {
    return 0;
  }
  
  // check number of arguments
  int nargs = lua_gettop(L);
  if (nargs != 1) {
    logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 argument, got %d", nargs));
    return 0;
  }
  
  const char *placementId = NULL;
  
  if (lua_type(L, 1) == LUA_TSTRING) {
    placementId = lua_tostring(L, 1);
  }
  else {
    logMsg(L, ERROR_MSG, MsgFormat(@"placementId (string) expected, got: %s", luaL_typename(L, 1)));
    return 0;
  }
  
  bool hasLoaded = false;
  
  // get ad info object
  CoronaSuperAwesomeAdInstance *adInstance = superAwesomeObjects[@(placementId)];
  
  if (adInstance != nil) {
    if (UTF8IsEqual([adInstance.adType UTF8String], TYPE_INTERSTITIAL)) {
      hasLoaded = [SAInterstitialAd hasAdAvailable:atoi(placementId)];
    }
    else if (UTF8IsEqual([adInstance.adType UTF8String], TYPE_VIDEO)) {
      hasLoaded = [SAVideoAd hasAdAvailable:atoi(placementId)];
    }
    else if (UTF8IsEqual([adInstance.adType UTF8String], TYPE_BANNER)) {
      SABannerAd *banner = (SABannerAd *)adInstance.adInstance;
      hasLoaded = [banner hasAdAvailable];
    }
  }
  
  lua_pushboolean(L, hasLoaded);
  
  return 1;
}

// [Lua] superawesome.show(placementId [, options])
int
SuperAwesomeLibrary::show(lua_State *L)
{
  Self *context = ToLibrary(L);
  
  if (! context) { // abort if no valid context
    return 0;
  }
  
  Self& library = *context;
  
  library.functionSignature = @"superawesome.show(placementId [, options])";
  
  if (! isSDKInitialized(L)) {
    return 0;
  }
  
  // check number of arguments
  int nargs = lua_gettop(L);
  if ((nargs < 1) || (nargs > 2)) {
    logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 or 2 arguments, got %d", nargs));
    return 0;
  }
  
  const char *placementId = NULL;
  const char *lockOrientation = NULL;
  const char *yAlign = NULL;
  double yOffset = 0;
  bool useParentalGate = false;
  bool useSmallClickZone = false;
  bool showVideoCloseButton = true;
  bool closeVideoAtEnd = false;
  
  if (lua_type(L, 1) == LUA_TSTRING) {
    placementId = lua_tostring(L, 1);
  }
  else {
    logMsg(L, ERROR_MSG, MsgFormat(@"placementId (string) expected, got: %s", luaL_typename(L, 1)));
    return 0;
  }
  
  if (! lua_isnoneornil(L, 2)) {
    if (lua_type(L, 2) == LUA_TTABLE) {
      // traverse all options
      for (lua_pushnil(L); lua_next(L, 2) != 0; lua_pop(L, 1)) {
        if (lua_type(L, -2) != LUA_TSTRING) {
          logMsg(L, ERROR_MSG, @"options must be a key/value table");
          return 0;
        }
        
        const char *key = lua_tostring(L, -2);
        
        if (UTF8IsEqual(key, "useParentalGate")) {
          if (lua_type(L, -1) == LUA_TBOOLEAN) {
            useParentalGate = lua_toboolean(L, -1);
          }
          else {
            logMsg(L, ERROR_MSG, MsgFormat(@"options.useParentalGate (boolean) expected, got: %s", luaL_typename(L, -1)));
            return 0;
          }
        }
        else if (UTF8IsEqual(key, "showVideoCloseButton")) {
          if (lua_type(L, -1) == LUA_TBOOLEAN) {
            showVideoCloseButton = lua_toboolean(L, -1);
          }
          else {
            logMsg(L, ERROR_MSG, MsgFormat(@"options.showVideoCloseButton (boolean) expected, got: %s", luaL_typename(L, -1)));
            return 0;
          }
        }
        else if (UTF8IsEqual(key, "closeVideoAtEnd")) {
          if (lua_type(L, -1) == LUA_TBOOLEAN) {
            closeVideoAtEnd = lua_toboolean(L, -1);
          }
          else {
            logMsg(L, ERROR_MSG, MsgFormat(@"options.closeVideoAtEnd (boolean) expected, got: %s", luaL_typename(L, -1)));
            return 0;
          }
        }
        else if (UTF8IsEqual(key, "useSmallClickZone")) {
          if (lua_type(L, -1) == LUA_TBOOLEAN) {
            useSmallClickZone = lua_toboolean(L, -1);
          }
          else {
            logMsg(L, ERROR_MSG, MsgFormat(@"options.useSmallClickZone (boolean) expected, got: %s", luaL_typename(L, -1)));
            return 0;
          }
        }
        else if (UTF8IsEqual(key, "lockOrientation")) {
          if (lua_type(L, -1) == LUA_TSTRING) {
            lockOrientation = lua_tostring(L, -1);
          }
          else {
            logMsg(L, ERROR_MSG, MsgFormat(@"options.lockOrientation (string) expected, got: %s", luaL_typename(L, -1)));
            return 0;
          }
        }
        else if (UTF8IsEqual(key, "y")) {
          if (lua_type(L, -1) == LUA_TSTRING) {
            yAlign = lua_tostring(L, -1);
          }
          else if (lua_type(L, -1) == LUA_TNUMBER) {
            yOffset = lua_tonumber(L, -1);
          }
          else {
            logMsg(L, ERROR_MSG, MsgFormat(@"options.y (string or number) expected, got: %s", luaL_typename(L, -1)));
            return 0;
          }
        }
        else if (UTF8IsEqual(key, "yAlign")) { // legacy API (use y instead)
          if (lua_type(L, -1) == LUA_TSTRING) {
            yAlign = lua_tostring(L, -1);
          }
          else {
            logMsg(L, ERROR_MSG, MsgFormat(@"options.yAlign (string) expected, got: %s", luaL_typename(L, -1)));
            return 0;
          }
        }
        else {
          logMsg(L, ERROR_MSG, MsgFormat(@"Invalid option '%s'", key));
          return 0;
        }
      }
    }
    else {
      logMsg(L, ERROR_MSG, MsgFormat(@"options (table) expected, got: %s", luaL_typename(L, 2)));
      return 0;
    }
  }
  
  // validation
  if (yAlign != NULL) {
    if (! [validBannerPositions containsObject:@(yAlign)]) {
      logMsg(L, ERROR_MSG, MsgFormat(@"y '%s' invalid", yAlign));
      return 0;
    }
  }
  
  CoronaSuperAwesomeAdInstance *adInstance = superAwesomeObjects[@(placementId)];
  if (adInstance == nil) {
    logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' not loaded", placementId));
    return 0;
  }
  
  if (UTF8IsEqual([adInstance.adType UTF8String], TYPE_INTERSTITIAL)) {
    if (! [SAInterstitialAd hasAdAvailable:atoi(placementId)]) {
      logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' not loaded", placementId));
      return 0;
    }
    
    [SAInterstitialAd setParentalGate:useParentalGate];
    
    if (lockOrientation == NULL) {
      [SAInterstitialAd setOrientation:OrientationAny];
    }
    else if (UTF8IsEqual(lockOrientation, LOCK_LANDSCAPE)) {
      [SAInterstitialAd setOrientation:OrientationLandscape];
    }
    else if (UTF8IsEqual(lockOrientation, LOCK_PORTRAIT)) {
      [SAInterstitialAd setOrientation:OrientationPortrait];
    }
    else {
      logMsg(L, WARNING_MSG, MsgFormat(@"lockOrientation '%s' invalid. Using default 'any' orientation", lockOrientation));
      [SAInterstitialAd setOrientation:OrientationAny];
    }
    
    [SAInterstitialAd play:atoi(placementId) fromVC:library.coronaViewController];
  }
  else if (UTF8IsEqual([adInstance.adType UTF8String], TYPE_VIDEO)) {
    if (! [SAVideoAd hasAdAvailable:atoi(placementId)]) {
      logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' not loaded", placementId));
      return 0;
    }
    
    [SAVideoAd setParentalGate:useParentalGate];
    [SAVideoAd setCloseButton:showVideoCloseButton];
    [SAVideoAd setSmallClick:useSmallClickZone];
    [SAVideoAd setCloseAtEnd:closeVideoAtEnd];
    
    if (lockOrientation == NULL) {
      [SAVideoAd setOrientation:OrientationAny];
    }
    else if (UTF8IsEqual(lockOrientation, LOCK_LANDSCAPE)) {
      [SAVideoAd setOrientation:OrientationLandscape];
    }
    else if (UTF8IsEqual(lockOrientation, LOCK_PORTRAIT)) {
      [SAVideoAd setOrientation:OrientationPortrait];
    }
    else {
      logMsg(L, WARNING_MSG, MsgFormat(@"lockOrientation '%s' invalid. Using default 'any' orientation", lockOrientation));
      [SAVideoAd setOrientation:OrientationAny];
    }
    
    [SAVideoAd play:atoi(placementId) fromVC:library.coronaViewController];
  }
  else if (UTF8IsEqual([adInstance.adType UTF8String], TYPE_BANNER)) {
    SABannerAd *bannerAd = (SABannerAd *)adInstance.adInstance;
    if (! [bannerAd hasAdAvailable]) {
      logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' not loaded", placementId));
      return 0;
    }
    
    // get screen size
    CGFloat orientedWidth = library.coronaViewController.view.frame.size.width;
    CGFloat orientedHeight = library.coronaViewController.view.frame.size.height;
    
    // calculate the size for the ad, and set its frame
    CGSize bannerSize = bannerAd.bounds.size;
    
    CGFloat bannerCenterX = ((orientedWidth - bannerSize.width) / 2);
    CGFloat bannerCenterY = ((orientedHeight - bannerSize.height) / 2);
    CGFloat bannerTopY = 0;
    CGFloat bannerBottomY = (orientedHeight - bannerSize.height);
    
    CGRect bannerFrame = bannerAd.frame;
    bannerFrame.origin.x = bannerCenterX;
    
    // set the banner position
    if (yAlign == NULL) {
      // convert corona coordinates to device coordinates and set banner position
      CGFloat newBannerY = floor(yOffset * [superAwesomeObjects[Y_RATIO_KEY] floatValue]);
      
      // negative values count from bottom
      if (yOffset < 0) {
        newBannerY = bannerBottomY + newBannerY;
      }
      
      // make sure the banner frame is visible.
      // adjust it if the user has specified 'y' which will render it partially off-screen
      NSUInteger ySnap = 0;
      if (newBannerY + bannerFrame.size.height > orientedHeight) {
        logMsg(L, WARNING_MSG, @"Banner y position off screen. Adjusting position.");
        ySnap = newBannerY - orientedHeight + bannerFrame.size.height;
      }
      bannerFrame.origin.y = newBannerY - ySnap;
    }
    else {
      if (UTF8IsEqual(yAlign, BANNER_ALIGN_TOP)) {
        bannerFrame.origin.y = bannerTopY;
      }
      else if (UTF8IsEqual(yAlign, BANNER_ALIGN_CENTER)) {
        bannerFrame.origin.y = bannerCenterY;
      }
      else if (UTF8IsEqual(yAlign, BANNER_ALIGN_BOTTOM)) {
        bannerFrame.origin.y = bannerBottomY;
      }
    }
    
    [bannerAd setFrame:bannerFrame];
    [bannerAd setHidden:false];
    [bannerAd play];
  }
  
  return 0;
}

// [Lua] superawesome.hide(placementId)
int
SuperAwesomeLibrary::hide(lua_State *L)
{
  Self *context = ToLibrary(L);
  
  if (! context) { // abort if no valid context
    return 0;
  }
  
  Self& library = *context;
  
  library.functionSignature = @"superawesome.hide(placementId)";
  
  if (! isSDKInitialized(L)) {
    return 0;
  }
  
  // check number of arguments
  int nargs = lua_gettop(L);
  if (nargs != 1) {
    logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 argument, got %d", nargs));
    return 0;
  }
  
  const char *placementId = NULL;
  
  if (lua_type(L, 1) == LUA_TSTRING) {
    placementId = lua_tostring(L, 1);
  }
  else {
    logMsg(L, ERROR_MSG, MsgFormat(@"placementId (string) expected, got %s", luaL_typename(L, 1)));
    return 0;
  }
  
  // get ad info
  CoronaSuperAwesomeAdInstance *adInstance = superAwesomeObjects[@(placementId)];
  if (adInstance == nil) {
    logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' not loaded", placementId));
    return 0;
  }
  
  // only banners can be hidden
  if (! UTF8IsEqual([adInstance.adType UTF8String], TYPE_BANNER)) {
    logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' is not a banner", placementId));
    return 0;
  }
  
  // close and remove ad object
  SABannerAd *banner = (SABannerAd *)adInstance.adInstance;
  [banner close];
  [superAwesomeObjects removeObjectForKey:@(placementId)];
  
  return 0;
}

// ----------------------------------------------------------------------------
// delegate implementation
// ----------------------------------------------------------------------------

// Plugin Delegate implementation
@implementation SuperAwesomeDelegate

- (void)processEventWithPlacementId:(NSInteger)placementId event:(SAEvent)event adType:(NSString *)adType
{
  const char *pid = UTF8StringWithFormat(@"%ld", (long)placementId);
  
  if (event == SAEventAdLoaded) {
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
      @(CoronaEventPhaseKey()): PHASE_LOADED,
      @(CoronaEventTypeKey()): adType,
      @(CORONA_EVENT_PLACEMENTID_KEY): @(pid)
    };
    [superAwesomeDelegate dispatchLuaEvent:coronaEvent];
    
  }
  else if (event == SAEventAdEmpty) {
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
      @(CoronaEventPhaseKey()): PHASE_FAILED,
      @(CoronaEventTypeKey()): adType,
      @(CoronaEventIsErrorKey()): @(true),
      @(CoronaEventResponseKey()): RESPONSE_NOADS,
      @(CORONA_EVENT_PLACEMENTID_KEY): @(pid)
    };
    [superAwesomeDelegate dispatchLuaEvent:coronaEvent];
  }
  else if (event == SAEventAdFailedToLoad) {
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
      @(CoronaEventPhaseKey()): PHASE_FAILED,
      @(CoronaEventTypeKey()): adType,
      @(CoronaEventIsErrorKey()): @(true),
      @(CoronaEventResponseKey()): RESPONSE_LOADFAILED,
      @(CORONA_EVENT_PLACEMENTID_KEY): @(pid)
    };
    [superAwesomeDelegate dispatchLuaEvent:coronaEvent];
  }
  else if (event == SAEventAdShown) {
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
      @(CoronaEventPhaseKey()): PHASE_DISPLAYED,
      @(CoronaEventTypeKey()): adType,
      @(CORONA_EVENT_PLACEMENTID_KEY): @(pid)
    };
    [superAwesomeDelegate dispatchLuaEvent:coronaEvent];
    
  }
  else if (event == SAEventAdFailedToShow) {
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
      @(CoronaEventPhaseKey()): PHASE_FAILED,
      @(CoronaEventTypeKey()): adType,
      @(CoronaEventIsErrorKey()): @(true),
      @(CoronaEventResponseKey()): RESPONSE_SHOWFAILED,
      @(CORONA_EVENT_PLACEMENTID_KEY): @(pid)
    };
    [superAwesomeDelegate dispatchLuaEvent:coronaEvent];
  }
  else if (event == SAEventAdClicked) {
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
      @(CoronaEventPhaseKey()): PHASE_CLICKED,
      @(CoronaEventTypeKey()): adType,
      @(CORONA_EVENT_PLACEMENTID_KEY): @(pid)
    };
    [superAwesomeDelegate dispatchLuaEvent:coronaEvent];
  }
  else if (event == SAEventAdClosed) {
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
      @(CoronaEventPhaseKey()): ([adType isEqualToString:@(TYPE_BANNER)]) ? PHASE_HIDDEN : PHASE_CLOSED,
      @(CoronaEventTypeKey()): adType,
      @(CORONA_EVENT_PLACEMENTID_KEY): @(pid)
    };
    [superAwesomeDelegate dispatchLuaEvent:coronaEvent];
  }
  else if (event == SAEventAdEnded) {
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
      @(CoronaEventPhaseKey()): PHASE_PLAYBACK_ENDED,
      @(CoronaEventTypeKey()): adType,
      @(CORONA_EVENT_PLACEMENTID_KEY): @(pid)
    };
    [superAwesomeDelegate dispatchLuaEvent:coronaEvent];
  }
  else if (event == SAEventAdAlreadyLoaded) {
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
      @(CoronaEventPhaseKey()): PHASE_FAILED,
      @(CoronaEventTypeKey()): adType,
      @(CoronaEventIsErrorKey()): @(true),
      @(CoronaEventResponseKey()): RESPONSE_ALREADY_LOADED,
      @(CORONA_EVENT_PLACEMENTID_KEY): @(pid)
    };
    [superAwesomeDelegate dispatchLuaEvent:coronaEvent];
  }
}

- (instancetype)init {
  if (self = [super init]) {
    self.coronaListener = NULL;
    self.coronaRuntime = NULL;
    
    self.saInterstitialCallback = ^(NSInteger placementId, SAEvent event) {
      [superAwesomeDelegate processEventWithPlacementId:placementId event:event adType:@(TYPE_INTERSTITIAL)];
    };
    
    self.saVideoCallback = ^(NSInteger placementId, SAEvent event) {
      [superAwesomeDelegate processEventWithPlacementId:placementId event:event adType:@(TYPE_VIDEO)];
    };
    
    self.saBannerCallback = ^(NSInteger placementId, SAEvent event) {
      [superAwesomeDelegate processEventWithPlacementId:placementId event:event adType:@(TYPE_BANNER)];
    };
  }
  
  return self;
}

// dispatch a new Lua event
- (void)dispatchLuaEvent:(NSDictionary *)dict
{
  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
    lua_State *L = self.coronaRuntime.L;
    CoronaLuaRef coronaListener = self.coronaListener;
    bool hasErrorKey = false;
    
    // create new event
    CoronaLuaNewEvent(L, EVENT_NAME);
    
    for (NSString *key in dict) {
      CoronaLuaPushValue(L, [dict valueForKey:key]);
      lua_setfield(L, -2, key.UTF8String);
      
      if (! hasErrorKey) {
        hasErrorKey = [key isEqualToString:@(CoronaEventIsErrorKey())];
      }
    }
    
    // add error key if not in dict
    if (! hasErrorKey) {
      lua_pushboolean(L, false);
      lua_setfield(L, -2, CoronaEventIsErrorKey());
    }
    
    // add provider
    lua_pushstring(L, PROVIDER_NAME );
    lua_setfield(L, -2, CoronaEventProviderKey());
    
    CoronaLuaDispatchEvent(L, coronaListener, 0);
  }];
}

@end

// ----------------------------------------------------------------------------

@implementation CoronaSuperAwesomeAdInstance

- (instancetype)init {
  return [self initWithAd:nil adType:nil];
}

- (instancetype)initWithAd:(NSObject *)adInstance adType:(NSString *)adType
{
  return [self initWithAd:adInstance adType:adType height:0];
}

- (instancetype)initWithAd:(NSObject *)adInstance adType:(NSString *)adType height:(CGFloat)height
{
  if (self = [super init]) {
    self.adInstance = adInstance;
    self.adType = adType;
    self.height = height;
  }
  
  return self;
}

- (void)invalidateInfo
{
  if (self.adInstance != nil) {
    // make sure ad object gets deallocated
    if (UTF8IsEqual([self.adType UTF8String], TYPE_BANNER)) {
      SABannerAd *bannerAd = (SABannerAd *)self.adInstance;
      [bannerAd setCallback:nil];
      [bannerAd removeFromSuperview];
    }
    
    self.adInstance = nil;
  }
}

- (void)dealloc
{
  [self invalidateInfo];
}

@end

// ----------------------------------------------------------------------------

CORONA_EXPORT int luaopen_plugin_superawesome(lua_State *L)
{
  return SuperAwesomeLibrary::Open(L);
}
