//
//  LuaLoader.java
//  SuperAwesome Plugin
//
//  Copyright (c) 2016 CoronaLabs inc. All rights reserved.


package plugin.superawesome;

import java.util.*;

import static java.lang.Math.ceil;
import static java.lang.Math.random;

import android.os.Build;
import android.view.Display;
import android.view.View;
import android.view.Gravity;
import android.util.Log;
import android.graphics.Point;
import android.widget.FrameLayout;

import static android.content.res.Configuration.ORIENTATION_PORTRAIT;

import com.naef.jnlua.LuaState;
import com.naef.jnlua.LuaType;
import com.naef.jnlua.JavaFunction;
import com.naef.jnlua.NamedJavaFunction;

import com.ansca.corona.CoronaActivity;
import com.ansca.corona.CoronaEnvironment;
import com.ansca.corona.CoronaLua;
import com.ansca.corona.CoronaRuntime;
import com.ansca.corona.CoronaRuntimeListener;
import com.ansca.corona.CoronaRuntimeTask;
import com.ansca.corona.CoronaRuntimeTaskDispatcher;
import com.ansca.corona.CoronaLuaEvent;

// SDK provider imports
import tv.superawesome.sdk.publisher.AwesomeAds;
import tv.superawesome.sdk.publisher.SABannerAd;
import tv.superawesome.sdk.publisher.SAInterstitialAd;
import tv.superawesome.sdk.publisher.SAVideoAd;
import tv.superawesome.sdk.publisher.SAEvent;
import tv.superawesome.sdk.publisher.SAOrientation;
import tv.superawesome.sdk.publisher.SAInterface;

/**
 * Implements the Lua interface for the plugin.
 * <p>
 * Only one instance of this class will be created by Corona for the lifetime of the application.
 * This instance will be re-used for every new Corona activity that gets created.
 */
public class LuaLoader implements JavaFunction, CoronaRuntimeListener {
    private static final String PLUGIN_NAME = "plugin.superawesome";
    private static final String PLUGIN_VERSION = "2.0.8";
    private static final String PLUGIN_SDK_VERSION = "8.3.6"; // no API get get SDK version (yet)

    private static final String EVENT_NAME = "adsRequest";
    private static final String PROVIDER_NAME = "superawesome";

    // ad types
    private static final String TYPE_BANNER = "banner";
    private static final String TYPE_INTERSTITIAL = "interstitial";
    private static final String TYPE_VIDEO = "video";
    // App Wall isn't implemented as Google Play resticts usage for child-directed apps

    // valid ad types
    private static final List<String> validAdTypes = new ArrayList<>();

    // banner sizes
    private static final String BANNER_50 = "BANNER_50";
    private static final String BANNER_90 = "BANNER_90";
    private static final String BANNER_250 = "BANNER_250";

    // banner alignment
    private static final String BANNER_ALIGN_TOP = "top";
    private static final String BANNER_ALIGN_CENTER = "center";
    private static final String BANNER_ALIGN_BOTTOM = "bottom";

    // valid ad types
    private static final List<String> validBannerPositions = new ArrayList<>();

    // ad orientations
    private static final String LOCK_PORTRAIT = "portrait";
    private static final String LOCK_LANDSCAPE = "landscape";

    // event keys
    private static final String CORONA_EVENT_PLACEMENTID_KEY = "placementId";

    // event phases
    private static final String PHASE_INIT = "init";
    private static final String PHASE_LOADED = "loaded";
    private static final String PHASE_DISPLAYED = "displayed";
    private static final String PHASE_REFRESHED = "refreshed";
    private static final String PHASE_PLAYBACK_ENDED = "playbackEnded";
    private static final String PHASE_FAILED = "failed";
    private static final String PHASE_CLOSED = "closed";
    private static final String PHASE_HIDDEN = "hidden";
    private static final String PHASE_CLICKED = "clicked";

    // response codes
    private static final String RESPONSE_LOADFAILED = "failedToLoad";
    private static final String RESPONSE_SHOWFAILED = "failedToShow";
    private static final String RESPONSE_ALREADY_LOADED = "alreadyLoaded";
    private static final String RESPONSE_NOADS = "noAdsAvailable";

    // message constants
    private static final String CORONA_TAG = "Corona";
    private static final String ERROR_MSG = "ERROR: ";
    private static final String WARNING_MSG = "WARNING: ";

    // add missing event keys
    private static final String EVENT_PHASE_KEY = "phase";
    private static final String EVENT_DATA_KEY = "data";
    private static final String EVENT_TYPE_KEY = "type";
    private static final String EVENT_PLACEMENTID_KEY = "placementId";

    // saved objects (apiKey, ad state, etc)
    static Map<String, Object> superAwesomeObjects = new HashMap<>();

    // ad dictionary keys
    private static final String Y_RATIO_KEY = "yRatio";        // used to calculate Corona -> UIKit coordinate ratio
    private static final String TESTMODE_KEY = "testMode";

    private static int coronaListener = CoronaLua.REFNIL;
    private static CoronaRuntimeTaskDispatcher coronaRuntimeTaskDispatcher = null;

    private static String functionSignature = "";

    // ----------------------------------------------------------------------------------
    // Helper classes to keep track of information not available in the SDK base classes
    // ----------------------------------------------------------------------------------

    private class CoronaAdInstance {
        Object adInstance;
        String adType;
        float height;

        CoronaAdInstance(Object ad, String adType) {
            this(ad, adType, 0);
        }

        CoronaAdInstance(Object ad, String adType, float height) {
            this.adInstance = ad;
            this.adType = adType;
            this.height = height;
        }

        // NOTE: only safe to call on the UI thread!
        void dealloc() {
            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

            if ((coronaActivity != null) && (adInstance != null)) {
                if (adInstance instanceof SABannerAd) {
                    SABannerAd oldBanner = (SABannerAd) adInstance;
                    if (oldBanner != null) {
                        oldBanner.setVisibility(View.INVISIBLE);
                        oldBanner.setListener(null);
                        coronaActivity.getOverlayView().removeView(oldBanner);
                    }
                }

                adInstance = null;
            }
        }
    }

    // -------------------------------------------------------
    // Plugin lifecycle events
    // -------------------------------------------------------

    /**
     * Called after the Corona runtime has been created and just before executing the "main.lua" file.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been loaded/initialized.
     *                Provides a LuaState object that allows the application to extend the Lua API.
     */
    @Override
    public void onLoaded(CoronaRuntime runtime) {
        // Note that this method will not be called the first time a Corona activity has been launched.
        // This is because this listener cannot be added to the CoronaEnvironment until after
        // this plugin has been required-in by Lua, which occurs after the onLoaded() event.
        // However, this method will be called when a 2nd Corona activity has been created.
        if (coronaRuntimeTaskDispatcher == null) {
            coronaRuntimeTaskDispatcher = new CoronaRuntimeTaskDispatcher(runtime);

            validAdTypes.add(TYPE_BANNER);
            validAdTypes.add(TYPE_INTERSTITIAL);
            validAdTypes.add(TYPE_VIDEO);

            validBannerPositions.add(BANNER_ALIGN_TOP);
            validBannerPositions.add(BANNER_ALIGN_CENTER);
            validBannerPositions.add(BANNER_ALIGN_BOTTOM);
        }
    }

    /**
     * Called just after the Corona runtime has executed the "main.lua" file.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been started.
     */
    @Override
    public void onStarted(CoronaRuntime runtime) {
    }

    /**
     * Called just after the Corona runtime has been suspended which pauses all rendering, audio, timers,
     * and other Corona related operations. This can happen when another Android activity (ie: window) has
     * been displayed, when the screen has been powered off, or when the screen lock is shown.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been suspended.
     */
    @Override
    public void onSuspended(CoronaRuntime runtime) {
    }

    /**
     * Called just after the Corona runtime has been resumed after a suspend.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been resumed.
     */
    @Override
    public void onResumed(CoronaRuntime runtime) {
    }

    /**
     * Called just before the Corona runtime terminates.
     * <p>
     * This happens when the Corona activity is being destroyed which happens when the user presses the Back button
     * on the activity, when the native.requestExit() method is called in Lua, or when the activity's finish()
     * method is called. This does not mean that the application is exiting.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that is being terminated.
     */
    @Override
    public void onExiting(final CoronaRuntime runtime) {
        final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

        if (coronaActivity != null) {
            Runnable runnableActivity = new Runnable() {
                public void run() {
                    SAInterstitialAd.setListener(null);
                    SAVideoAd.setListener(null);

                    // deallocate adInstance objects so garbage collection can be done
                    for (String key : superAwesomeObjects.keySet()) {
                        Object object = superAwesomeObjects.get(key);
                        if (object instanceof CoronaAdInstance) {
                            CoronaAdInstance adInstance = (CoronaAdInstance) object;
                            adInstance.dealloc();
                        }
                    }

                    // Remove the Lua listener reference.
                    CoronaLua.deleteRef(runtime.getLuaState(), coronaListener);
                    coronaListener = CoronaLua.REFNIL;

                    // clear lists and remove object references
                    validAdTypes.clear();
                    validBannerPositions.clear();
                    superAwesomeObjects.clear();

                    coronaRuntimeTaskDispatcher = null;
                }
            };

            coronaActivity.runOnUiThread(runnableActivity);
        }
    }

    // --------------------------------------------------------------------------
    // helper functions
    // --------------------------------------------------------------------------

    // log message to console
    private void logMsg(String msgType, String errorMsg) {
        String functionID = functionSignature;
        if (!functionID.isEmpty()) {
            functionID += ", ";
        }

        Log.i(CORONA_TAG, msgType + functionID + errorMsg);
    }

    // return true if SDK is properly initialized
    private boolean isSDKInitialized() {
        if (coronaListener == CoronaLua.REFNIL) {
            logMsg(ERROR_MSG, "superawesome.init() must be called before calling other API functions");
            return false;
        }

        return true;
    }

    // dispatch a Lua event to our callback (dynamic handling of properties through map)
    private void dispatchLuaEvent(final Map<String, Object> event) {
        if (coronaRuntimeTaskDispatcher != null) {
            coronaRuntimeTaskDispatcher.send(new CoronaRuntimeTask() {
                public void executeUsing(CoronaRuntime runtime) {
                    try {
                        LuaState L = runtime.getLuaState();
                        CoronaLua.newEvent(L, EVENT_NAME);
                        boolean hasErrorKey = false;

                        // add event parameters from map
                        for (String key : event.keySet()) {
                            CoronaLua.pushValue(L, event.get(key));           // push value
                            L.setField(-2, key);                              // push key

                            if (!hasErrorKey) {
                                hasErrorKey = key.equals(CoronaLuaEvent.ISERROR_KEY);
                            }
                        }

                        // add error key if not in map
                        if (!hasErrorKey) {
                            L.pushBoolean(false);
                            L.setField(-2, CoronaLuaEvent.ISERROR_KEY);
                        }

                        // add provider
                        L.pushString(PROVIDER_NAME);
                        L.setField(-2, CoronaLuaEvent.PROVIDER_KEY);

                        CoronaLua.dispatchEvent(L, coronaListener, 0);
                    } catch (Exception ex) {
                        ex.printStackTrace();
                    }
                }
            });
        }
    }




    // -------------------------------------------------------
    // plugin implementation
    // -------------------------------------------------------

    /**
     * <p>
     * Note that a new LuaLoader instance will not be created for every CoronaActivity instance.
     * That is, only one instance of this class will be created for the lifetime of the application process.
     * This gives a plugin the option to do operations in the background while the CoronaActivity is destroyed.
     */
    public LuaLoader() {
        // Set up this plugin to listen for Corona runtime events to be received by methods
        // onLoaded(), onStarted(), onSuspended(), onResumed(), and onExiting().
        CoronaEnvironment.addRuntimeListener(this);
    }

    /**
     * Called when this plugin is being loaded via the Lua require() function.
     * <p>
     * Note that this method will be called everytime a new CoronaActivity has been launched.
     * This means that you'll need to re-initialize this plugin here.
     * <p>
     * Warning! This method is not called on the main UI thread.
     *
     * @param L Reference to the Lua state that the require() function was called from.
     * @return Returns the number of values that the require() function will return.
     * <p>
     * Expected to return 1, the library that the require() function is loading.
     */
    @Override
    public int invoke(LuaState L) {
        // Register this plugin into Lua with the following functions.
        NamedJavaFunction[] luaFunctions = new NamedJavaFunction[]
                {
                        new Init(),
                        new Load(),
                        new IsLoaded(),
                        new Show(),
                        new Hide(),
                };

        String libName = L.toString(1);
        L.register(libName, luaFunctions);

        // Returning 1 indicates that the Lua require() function will return the above Lua
        return 1;
    }

    // [Lua] superawesome.init(adListener, [options])
    private class Init implements NamedJavaFunction {
        // Gets the name of the Lua function as it would appear in the Lua script
        @Override
        public String getName() {
            return "init";
        }

        // This method is executed when the Lua function is called
        @Override
        public int invoke(LuaState L) {
            functionSignature = "superawesome.init(listener [, options)";

            // prevent init from being called twice
            if (coronaListener != CoronaLua.REFNIL) {
                logMsg(WARNING_MSG, "init() should only be called once");
                return 0;
            }

            // check number of arguments
            int nargs = L.getTop();
            if ((nargs < 1) || (nargs > 2)) {
                logMsg(ERROR_MSG, "Expected 1 or 2 arguments, got " + nargs);
                return 0;
            }

            boolean testMode = false;

            // Get listener key (required)
            if (CoronaLua.isListener(L, 1, PROVIDER_NAME)) {
                coronaListener = CoronaLua.newRef(L, 1);
            } else {
                logMsg(ERROR_MSG, "listener expected, got: " + L.typeName(1));
                return 0;
            }

            // check for options table
            if (!L.isNoneOrNil(2)) {
                if (L.type(2) == LuaType.TABLE) {
                    // traverse all options
                    for (L.pushNil(); L.next(2); L.pop(1)) {
                        if (L.type(-2) != LuaType.STRING) {
                            logMsg(ERROR_MSG, "options must be a key/value table");
                            return 0;
                        }

                        String key = L.toString(-2);

                        if (key.equals("testMode")) {
                            if (L.type(-1) == LuaType.BOOLEAN) {
                                testMode = L.toBoolean(-1);
                            } else {
                                logMsg(ERROR_MSG, "options.testMode (boolean) expected, got: " + L.typeName(-1));
                                return 0;
                            }
                        } else {
                            logMsg(ERROR_MSG, "Invalid option '" + key + "'");
                            return 0;
                        }
                    }
                } else {
                    logMsg(ERROR_MSG, "options (table) expected, got " + L.typeName(2));
                    return 0;
                }
            }

            // set the delegates (banners are set on each instance)
            SAInterstitialAd.setListener(new CoronaSADelegate(TYPE_INTERSTITIAL));
            SAVideoAd.setListener(new CoronaSADelegate(TYPE_VIDEO));

            // save setting for future use
            superAwesomeObjects.put(TESTMODE_KEY, testMode);
            AwesomeAds.init(CoronaEnvironment.getCoronaActivity(), testMode);

            // log the plugin version to device console
            Log.i(CORONA_TAG, PLUGIN_NAME + ": " + PLUGIN_VERSION + " (SDK: " + PLUGIN_SDK_VERSION + ")");

            // send Corona Lua event
            HashMap<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_INIT);
            dispatchLuaEvent(coronaEvent);

            return 0;
        }
    }

    // [Lua] superawesome.load(adUnitType, options)"
    private class Load implements NamedJavaFunction {
        // Gets the name of the Lua function as it would appear in the Lua script
        @Override
        public String getName() {
            return "load";
        }

        // This method is executed when the Lua function is called
        @Override
        public int invoke(LuaState L) {
            functionSignature = "superawesome.load(adUnitType, options)";

            if (!isSDKInitialized()) {
                return 0;
            }

            // check number of arguments
            int nargs = L.getTop();
            if ((nargs < 1) || (nargs > 3)) { // 3 for backwards compatibility with legacy API
                logMsg(ERROR_MSG, "Expected 1 or 2 arguments, got " + nargs);
                return 0;
            }

            String adUnitType = null;
            String placementId = null;
            String bannerSize = BANNER_50;
            boolean legacyAPI = false;
            boolean bannerTransparency = false;

            if (L.type(1) == LuaType.STRING) {
                adUnitType = L.toString(1);
            } else {
                logMsg(ERROR_MSG, "adUnitType (string) expected, got: " + L.typeName(1));
                return 0;
            }

            if (L.type(2) == LuaType.STRING) {
                placementId = L.toString(2);
                legacyAPI = true;
            } else if (L.type(2) == LuaType.TABLE) {
                // traverse all options
                for (L.pushNil(); L.next(2); L.pop(1)) {
                    if (L.type(-2) != LuaType.STRING) {
                        logMsg(ERROR_MSG, "options must be a key/value table");
                        return 0;
                    }

                    String key = L.toString(-2);

                    if (key.equals("placementId")) {
                        if (L.type(-1) == LuaType.STRING) {
                            placementId = L.toString(-1);
                        } else {
                            logMsg(ERROR_MSG, "options.placementId (string) expected, got: " + L.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("bannerSize")) {
                        if (L.type(-1) == LuaType.STRING) {
                            bannerSize = L.toString(-1);
                        } else {
                            logMsg(ERROR_MSG, "options.bannerSize (string) expected, got: " + L.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("bannerTransparency")) {
                        if (L.type(-1) == LuaType.BOOLEAN) {
                            bannerTransparency = L.toBoolean(-1);
                        } else {
                            logMsg(ERROR_MSG, "options.bannerTransparency (boolean) expected, got: " + L.typeName(-1));
                            return 0;
                        }
                    } else {
                        logMsg(ERROR_MSG, "Invalid option '" + key + "'");
                        return 0;
                    }
                }
            } else {
                logMsg(ERROR_MSG, "options (table) expected, got: " + L.typeName(2));
                return 0;
            }

            if (legacyAPI) {
                if (!L.isNoneOrNil(3)) {
                    if (L.type(3) == LuaType.TABLE) {
                        // traverse all options
                        for (L.pushNil(); L.next(3); L.pop(1)) {
                            if (L.type(-2) != LuaType.STRING) {
                                logMsg(ERROR_MSG, "options must be a key/value table");
                                return 0;
                            }

                            String key = L.toString(-2);

                            if (key.equals("bannerSize")) {
                                if (L.type(-1) == LuaType.STRING) {
                                    bannerSize = L.toString(-1);
                                } else {
                                    logMsg(ERROR_MSG, "options.bannerSize (string) expected, got: " + L.typeName(-1));
                                    return 0;
                                }
                            } else {
                                logMsg(ERROR_MSG, "Invalid option '" + key + "'");
                                return 0;
                            }
                        }
                    } else {
                        logMsg(ERROR_MSG, "options (table) expected, got: " + L.typeName(3));
                        return 0;
                    }
                }
            }

            // validation
            if (!validAdTypes.contains(adUnitType)) {
                logMsg(ERROR_MSG, "adUnitType '" + adUnitType + "' invalid");
                return 0;
            }

            // make final vars for inner loop
            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
            final boolean testMode = (boolean) superAwesomeObjects.get(TESTMODE_KEY);
            final boolean fBannerTransparency = bannerTransparency;
            final String fAdUnitType = adUnitType;
            final String fPlacementId = placementId;
            final String fBannerSize = bannerSize;

            // check old instance
            final CoronaAdInstance oldInstance = (CoronaAdInstance) superAwesomeObjects.get(fPlacementId);
            if (oldInstance != null) {
                if (!oldInstance.adType.equals(fAdUnitType)) {
                    logMsg(ERROR_MSG, "placementId '" + fPlacementId + "' is not of type " + fAdUnitType);
                    return 0;
                }
            }

            if (coronaActivity != null) {
                Runnable runnableActivity = new Runnable() {
                    public void run() {
                        if (fAdUnitType.equals(TYPE_INTERSTITIAL)) {
                            if (oldInstance != null) {
                                oldInstance.dealloc();
                            }

                            SAInterstitialAd.setTestMode(testMode);

                            // create ad info object to hold extra information not available in the SDK
                            CoronaAdInstance adInstance = new CoronaAdInstance(null, TYPE_INTERSTITIAL);
                            superAwesomeObjects.put(fPlacementId, adInstance);

                            SAInterstitialAd.load(Integer.parseInt(fPlacementId), coronaActivity);
                        } else if (fAdUnitType.equals(TYPE_VIDEO)) {
                            if (oldInstance != null) {
                                oldInstance.dealloc();
                            }

                            SAVideoAd.setTestMode(testMode);

                            // create ad info object to hold extra information not available in the SDK
                            CoronaAdInstance adInstance = new CoronaAdInstance(null, TYPE_VIDEO);
                            superAwesomeObjects.put(fPlacementId, adInstance);

                            SAVideoAd.load(Integer.parseInt(fPlacementId), coronaActivity);
                        } else if (fAdUnitType.equals(TYPE_BANNER)) {
                            if (oldInstance != null) {
                                SABannerAd banner = (SABannerAd) oldInstance.adInstance;
                                if (banner.hasAdAvailable()) {
                                    // can't get the delegate of the banner so create a temporary one here for sending the event
                                    CoronaSADelegate temporaryDelegate = new CoronaSADelegate(TYPE_BANNER);
                                    temporaryDelegate.onEvent(Integer.parseInt(fPlacementId), SAEvent.adAlreadyLoaded);
                                    return;
                                }

                                oldInstance.dealloc();
                            }

                            // calculate the Corona->device coordinate ratio.
                            // we don't use display.contentScaleY here as there are cases where it's difficult to get the proper values to use
                            // especially on Android. uses the same formula for iOS and Android for the sake of consistency.
                            // re-calculate this value on every load as the ratio can change between orientation changes
                            Point point1 = coronaActivity.convertCoronaPointToAndroidPoint(0, 0);
                            Point point2 = coronaActivity.convertCoronaPointToAndroidPoint(1000, 1000);
                            double yRatio = (double) (point2.y - point1.y) / 1000.0;
                            superAwesomeObjects.put(Y_RATIO_KEY, yRatio);

                            // create the banner instance
                            SABannerAd banner = new SABannerAd(coronaActivity);
                            banner.setId((int) (random() * Integer.MAX_VALUE)); // set an id to avoid crash when displaying ad
                            banner.setListener(new CoronaSADelegate(TYPE_BANNER));
                            banner.setTestMode(testMode);
                            banner.setColor(fBannerTransparency);
                            banner.setVisibility(View.INVISIBLE);

                            int bannerHeight = 50;

                            if (fBannerSize.equals(BANNER_50)) {
                                bannerHeight = 50;
                            } else if (fBannerSize.equals(BANNER_90)) {
                                bannerHeight = 90;
                            } else if (fBannerSize.equals(BANNER_250)) {
                                bannerHeight = 250;
                            } else {
                                logMsg(WARNING_MSG, "options.bannerSize '" + fBannerSize + "' invalid. Using default BANNER_50");
                            }

                            // create ad info object to hold extra information not available in the SDK
                            CoronaAdInstance adInstance = new CoronaAdInstance(banner, TYPE_BANNER, bannerHeight);
                            superAwesomeObjects.put(fPlacementId, adInstance);

                            banner.load(Integer.parseInt(fPlacementId));
                        }
                    }
                };

                coronaActivity.runOnUiThread(runnableActivity);
            }

            return 0;
        }
    }

    // [Lua] superawesome.isLoaded(placementId)
    private class IsLoaded implements NamedJavaFunction {
        // Gets the name of the Lua function as it would appear in the Lua script
        @Override
        public String getName() {
            return "isLoaded";
        }

        // This method is executed when the Lua function is called
        @Override
        public int invoke(LuaState L) {
            functionSignature = "superawesome.isLoaded(placementId)";

            if (!isSDKInitialized()) {
                return 0;
            }

            // check number of arguments
            int nargs = L.getTop();
            if (nargs != 1) {
                logMsg(ERROR_MSG, "Expected 1 argument, got " + nargs);
                return 0;
            }

            String placementId = null;

            if (L.type(1) == LuaType.STRING) {
                placementId = L.toString(1);
            } else {
                logMsg(ERROR_MSG, "placementId (string) expected, got: " + L.typeName(1));
                return 0;
            }

            boolean hasLoaded = false;

            // get ad info object
            CoronaAdInstance adInstance = (CoronaAdInstance) superAwesomeObjects.get(placementId);

            if (adInstance != null) {
                if (adInstance.adType.equals(TYPE_INTERSTITIAL)) {
                    hasLoaded = SAInterstitialAd.hasAdAvailable(Integer.parseInt(placementId));
                } else if (adInstance.adType.equals(TYPE_VIDEO)) {
                    hasLoaded = SAVideoAd.hasAdAvailable(Integer.parseInt(placementId));
                } else if (adInstance.adType.equals(TYPE_BANNER)) {
                    SABannerAd banner = (SABannerAd) adInstance.adInstance;
                    hasLoaded = banner.hasAdAvailable();
                }
            }

            L.pushBoolean(hasLoaded);

            return 1;
        }
    }

    // [Lua] superawesome.show(placementId [, options])
    private class Show implements NamedJavaFunction {
        // Gets the name of the Lua function as it would appear in the Lua script
        @Override
        public String getName() {
            return "show";
        }

        // This method is executed when the Lua function is called
        @Override
        public int invoke(final LuaState L) {
            functionSignature = "superawesome.show(placementId [, options])";

            if (!isSDKInitialized()) {
                return 0;
            }

            // check number of arguments
            int nargs = L.getTop();
            if ((nargs < 1) || (nargs > 2)) {
                logMsg(ERROR_MSG, "Expected 1 or 2 arguments, got " + nargs);
                return 0;
            }

            String placementId = null;
            String lockOrientation = null;
            String yAlign = null;
            double yOffset = 0;
            boolean useParentalGate = false;
            boolean useSmallClickZone = false;
            boolean showVideoCloseButton = true;
            boolean closeVideoAtEnd = false;

            if (L.type(1) == LuaType.STRING) {
                placementId = L.toString(1);
            } else {
                logMsg(ERROR_MSG, "placementId (string) expected, got: " + L.typeName(1));
                return 0;
            }

            if (!L.isNoneOrNil(2)) {
                if (L.type(2) == LuaType.TABLE) {
                    // traverse all options
                    for (L.pushNil(); L.next(2); L.pop(1)) {
                        if (L.type(-2) != LuaType.STRING) {
                            logMsg(ERROR_MSG, "options must be a key/value table");
                            return 0;
                        }

                        String key = L.toString(-2);

                        if (key.equals("useParentalGate")) {
                            if (L.type(-1) == LuaType.BOOLEAN) {
                                useParentalGate = L.toBoolean(-1);
                            } else {
                                logMsg(ERROR_MSG, "options.useParentalGate (boolean) expected, got: " + L.typeName(-1));
                                return 0;
                            }
                        } else if (key.equals("showVideoCloseButton")) {
                            if (L.type(-1) == LuaType.BOOLEAN) {
                                showVideoCloseButton = L.toBoolean(-1);
                            } else {
                                logMsg(ERROR_MSG, "options.showVideoCloseButton (boolean) expected, got: " + L.typeName(-1));
                                return 0;
                            }
                        } else if (key.equals("closeVideoAtEnd")) {
                            if (L.type(-1) == LuaType.BOOLEAN) {
                                closeVideoAtEnd = L.toBoolean(-1);
                            } else {
                                logMsg(ERROR_MSG, "options.closeVideoAtEnd (boolean) expected, got: " + L.typeName(-1));
                                return 0;
                            }
                        } else if (key.equals("useSmallClickZone")) {
                            if (L.type(-1) == LuaType.BOOLEAN) {
                                useSmallClickZone = L.toBoolean(-1);
                            } else {
                                logMsg(ERROR_MSG, "options.useSmallClickZone (boolean) expected, got: " + L.typeName(-1));
                                return 0;
                            }
                        } else if (key.equals("lockOrientation")) {
                            if (L.type(-1) == LuaType.STRING) {
                                lockOrientation = L.toString(-1);
                            } else {
                                logMsg(ERROR_MSG, "options.lockOrientation (string) expected, got: " + L.typeName(-1));
                                return 0;
                            }
                        } else if (key.equals("y")) {
                            if (L.type(-1) == LuaType.STRING) {
                                yAlign = L.toString(-1);
                            } else if (L.type(-1) == LuaType.NUMBER) {
                                yOffset = L.toNumber(-1);
                            } else {
                                logMsg(ERROR_MSG, "options.y (string or number) expected, got: " + L.typeName(-1));
                                return 0;
                            }
                        } else if (key.equals("yAlign")) { // legacy API (use y instead)
                            if (L.type(-1) == LuaType.STRING) {
                                yAlign = L.toString(-1);
                            } else {
                                logMsg(ERROR_MSG, "options.yAlign (string) expected, got: " + L.typeName(-1));
                                return 0;
                            }
                        } else {
                            logMsg(ERROR_MSG, "Invalid option '" + key + "'");
                            return 0;
                        }
                    }
                } else {
                    logMsg(ERROR_MSG, "options (table) expected, got: " + L.typeName(2));
                    return 0;
                }
            }

            // validation
            if (yAlign != null) {
                if (!validBannerPositions.contains(yAlign)) {
                    logMsg(ERROR_MSG, "y '" + yAlign + "' invalid");
                    return 0;
                }
            }

            final CoronaAdInstance adInstance = (CoronaAdInstance) superAwesomeObjects.get(placementId);
            if (adInstance == null) {
                logMsg(ERROR_MSG, "placementId '" + placementId + "' not loaded");
                return 0;
            }

            // make final vars for inner loop
            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
            final String fPlacementId = placementId;
            final String fLockOrientation = lockOrientation;
            final String fYAlign = yAlign;
            final boolean fUseParentalGate = useParentalGate;
            final boolean fShowVideoCloseButton = showVideoCloseButton;
            final boolean fUseSmallClickZone = useSmallClickZone;
            final boolean fCloseVideoAtEnd = closeVideoAtEnd;
            final double fYOffset = yOffset;

            if (coronaActivity != null) {
                Runnable runnableActivity = new Runnable() {
                    public void run() {
                        if (adInstance.adType.equals(TYPE_INTERSTITIAL)) {
                            if (!SAInterstitialAd.hasAdAvailable(Integer.parseInt(fPlacementId))) {
                                logMsg(ERROR_MSG, "placementId '" + fPlacementId + "' not loaded");
                                return;
                            }

                            SAInterstitialAd.setParentalGate(fUseParentalGate);

                            if (fLockOrientation == null) {
                                SAInterstitialAd.setOrientation(SAOrientation.ANY);
                            } else if (fLockOrientation.equals(LOCK_LANDSCAPE)) {
                                SAInterstitialAd.setOrientation(SAOrientation.LANDSCAPE);
                            } else if (fLockOrientation.equals(LOCK_PORTRAIT)) {
                                SAInterstitialAd.setOrientation(SAOrientation.PORTRAIT);
                            } else {
                                logMsg(WARNING_MSG, "lockOrientation '" + fLockOrientation + "' invalid. Using default 'any' orientation");
                                SAInterstitialAd.setOrientation(SAOrientation.ANY);
                            }

                            SAInterstitialAd.play(Integer.parseInt(fPlacementId), coronaActivity);
                        } else if (adInstance.adType.equals(TYPE_VIDEO)) {
                            if (!SAVideoAd.hasAdAvailable(Integer.parseInt(fPlacementId))) {
                                logMsg(ERROR_MSG, "placementId '" + fPlacementId + "' not loaded");
                                return;
                            }

                            SAVideoAd.setParentalGate(fUseParentalGate);
                            SAVideoAd.setCloseButton(fShowVideoCloseButton);
                            SAVideoAd.setSmallClick(fUseSmallClickZone);
                            SAVideoAd.setCloseAtEnd(fCloseVideoAtEnd);

                            if (fLockOrientation == null) {
                                SAVideoAd.setOrientation(SAOrientation.ANY);
                            } else if (fLockOrientation.equals(LOCK_LANDSCAPE)) {
                                SAVideoAd.setOrientation(SAOrientation.LANDSCAPE);
                            } else if (fLockOrientation.equals(LOCK_PORTRAIT)) {
                                SAVideoAd.setOrientation(SAOrientation.PORTRAIT);
                            } else {
                                logMsg(WARNING_MSG, "lockOrientation '" + fLockOrientation + "' invalid. Using default 'any' orientation");
                                SAVideoAd.setOrientation(SAOrientation.ANY);
                            }

                            SAVideoAd.play(Integer.parseInt(fPlacementId), coronaActivity);
                        } else if (adInstance.adType.equals(TYPE_BANNER)) {
                            SABannerAd bannerAd = (SABannerAd) adInstance.adInstance;
                            if (!bannerAd.hasAdAvailable()) {
                                logMsg(ERROR_MSG, "placementId '" + fPlacementId + "' not loaded");
                                return;
                            }

                            // remove old layout
                            if (bannerAd.getParent() != null) {
                                coronaActivity.getOverlayView().removeView(bannerAd);
                            }

                            // get device scale
                            double deviceScale = coronaActivity.getApplicationContext().getResources().getDisplayMetrics().density;

                            // set final layout params
                            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                                    FrameLayout.LayoutParams.MATCH_PARENT,
                                    (int) (adInstance.height * deviceScale)
                            );

                            // set the banner position
                            if (fYAlign == null) {
                                Display display = coronaActivity.getWindowManager().getDefaultDisplay();
                                int orientation = coronaActivity.getResources().getConfiguration().orientation;
                                int orientedHeight;

                                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.HONEYCOMB_MR2) {
                                    if (orientation == ORIENTATION_PORTRAIT) {
                                        orientedHeight = display.getHeight();
                                    } else {
                                        orientedHeight = display.getWidth();
                                    }
                                } else {
                                    Point size = new Point();
                                    display.getSize(size);

                                    if (orientation == ORIENTATION_PORTRAIT) {
                                        orientedHeight = size.y;
                                    } else {
                                        orientedHeight = size.x;
                                    }
                                }

                                // convert corona coordinates to device coordinates and set banner position
                                double newBannerY = ceil(fYOffset * (double) superAwesomeObjects.get(Y_RATIO_KEY));

                                // make sure the banner frame is visible.
                                // adjust it if the user has specified 'y' which will render it partially off-screen
                                if (newBannerY >= 0) { // offset from top
                                    if (newBannerY + bannerAd.getHeight() > orientedHeight) {
                                        logMsg(WARNING_MSG, "Banner y position off screen. Adjusting position.");
                                        params.gravity = Gravity.BOTTOM | Gravity.CENTER;
                                    } else {
                                        params.gravity = Gravity.TOP | Gravity.CENTER;
                                        params.topMargin = (int) newBannerY;
                                    }
                                } else { // offset from bottom
                                    if (orientedHeight - bannerAd.getHeight() + newBannerY < 0) {
                                        logMsg(WARNING_MSG, "Banner y position off screen. Adjusting position.");
                                        params.gravity = Gravity.TOP | Gravity.CENTER;
                                    } else {
                                        params.gravity = Gravity.BOTTOM | Gravity.CENTER;
                                        params.bottomMargin = Math.abs((int) newBannerY);
                                    }
                                }
                            } else {
                                if (fYAlign.equals(BANNER_ALIGN_TOP)) {
                                    params.gravity = Gravity.TOP | Gravity.CENTER;
                                } else if (fYAlign.equals(BANNER_ALIGN_CENTER)) {
                                    params.gravity = Gravity.CENTER;
                                } else if (fYAlign.equals(BANNER_ALIGN_BOTTOM)) {
                                    params.gravity = Gravity.BOTTOM | Gravity.CENTER;
                                }
                            }

                            // display the banner
                            bannerAd.setVisibility(View.VISIBLE);
                            coronaActivity.getOverlayView().addView(bannerAd, params);
                            bannerAd.play(coronaActivity);
                            bannerAd.bringToFront();
                        }

                        // the displayed event is sent in the show() function since the activity takes control
                        // before this event is handled by Corona
                        Map<String, Object> coronaEvent = new HashMap<>();
                        coronaEvent.put(EVENT_PHASE_KEY, PHASE_DISPLAYED);
                        coronaEvent.put(EVENT_TYPE_KEY, adInstance.adType);
                        coronaEvent.put(EVENT_PLACEMENTID_KEY, fPlacementId);
                        dispatchLuaEvent(coronaEvent);
                    }
                };

                coronaActivity.runOnUiThread(runnableActivity);
            }

            return 0;
        }
    }

    // [Lua] superawesome.hide(placementId)
    private class Hide implements NamedJavaFunction {
        // Gets the name of the Lua function as it would appear in the Lua script
        @Override
        public String getName() {
            return "hide";
        }

        // This method is executed when the Lua function is called
        @Override
        public int invoke(LuaState L) {
            functionSignature = "superawesome.hide(placementId)";

            if (!isSDKInitialized()) {
                return 0;
            }

            // check number of arguments
            int nargs = L.getTop();
            if (nargs != 1) {
                logMsg(ERROR_MSG, "Expected 1 argument, got " + nargs);
                return 0;
            }

            String placementId = null;

            if (L.type(1) == LuaType.STRING) {
                placementId = L.toString(1);
            } else {
                logMsg(ERROR_MSG, "placementId (string) expected, got " + L.typeName(1));
                return 0;
            }

            // get ad info
            final CoronaAdInstance adInstance = (CoronaAdInstance) superAwesomeObjects.get(placementId);
            if (adInstance == null) {
                logMsg(ERROR_MSG, "placementId '" + placementId + "' not loaded");
                return 0;
            }

            // only banners can be hidden
            if (!adInstance.adType.equals(TYPE_BANNER)) {
                logMsg(ERROR_MSG, "placementId '" + placementId + "' is not a banner");
                return 0;
            }

            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
            final String fPlacementId = placementId;

            if (coronaActivity != null) {
                Runnable runnableActivity = new Runnable() {
                    public void run() {
                        // close banner
                        SABannerAd banner = (SABannerAd) adInstance.adInstance;
                        banner.close();

                        // invalidate ad instance object
                        adInstance.dealloc();

                        // remove ad object
                        superAwesomeObjects.remove(fPlacementId);
                    }
                };

                coronaActivity.runOnUiThread(runnableActivity);
            }

            return 0;
        }
    }

    // ----------------------------------------------------------------------------
    // delegate implementation
    // ----------------------------------------------------------------------------

    private class CoronaSADelegate implements SAInterface {
        String adType;

        CoronaSADelegate(String adType) {
            this.adType = adType;
        }

        @Override
        public void onEvent(int placementId, SAEvent saEvent) {
            String pid = Integer.toString(placementId);

            if (saEvent == SAEvent.adLoaded) {
                // send Corona Lua event
                Map<String, Object> coronaEvent = new HashMap<>();
                coronaEvent.put(EVENT_PHASE_KEY, PHASE_LOADED);
                coronaEvent.put(EVENT_TYPE_KEY, adType);
                coronaEvent.put(EVENT_PLACEMENTID_KEY, pid);
                dispatchLuaEvent(coronaEvent);
            } else if (saEvent == SAEvent.adEmpty) {
                // send Corona Lua event
                Map<String, Object> coronaEvent = new HashMap<>();
                coronaEvent.put(EVENT_PHASE_KEY, PHASE_FAILED);
                coronaEvent.put(EVENT_TYPE_KEY, adType);
                coronaEvent.put(CoronaLuaEvent.ISERROR_KEY, true);
                coronaEvent.put(CoronaLuaEvent.RESPONSE_KEY, RESPONSE_NOADS);
                coronaEvent.put(EVENT_PLACEMENTID_KEY, pid);
                dispatchLuaEvent(coronaEvent);
            } else if (saEvent == SAEvent.adFailedToLoad) {
                // send Corona Lua event
                Map<String, Object> coronaEvent = new HashMap<>();
                coronaEvent.put(EVENT_PHASE_KEY, PHASE_FAILED);
                coronaEvent.put(EVENT_TYPE_KEY, adType);
                coronaEvent.put(CoronaLuaEvent.ISERROR_KEY, true);
                coronaEvent.put(CoronaLuaEvent.RESPONSE_KEY, RESPONSE_LOADFAILED);
                coronaEvent.put(EVENT_PLACEMENTID_KEY, pid);
                dispatchLuaEvent(coronaEvent);
            } else if (saEvent == SAEvent.adShown) {
                // the displayed event is sent in the show() function since the activity takes control
                // before this event is handled by Corona
            } else if (saEvent == SAEvent.adFailedToShow) {
                // send Corona Lua event
                Map<String, Object> coronaEvent = new HashMap<>();
                coronaEvent.put(EVENT_PHASE_KEY, PHASE_FAILED);
                coronaEvent.put(EVENT_TYPE_KEY, adType);
                coronaEvent.put(CoronaLuaEvent.ISERROR_KEY, true);
                coronaEvent.put(CoronaLuaEvent.RESPONSE_KEY, RESPONSE_SHOWFAILED);
                coronaEvent.put(EVENT_PLACEMENTID_KEY, pid);
                dispatchLuaEvent(coronaEvent);
            } else if (saEvent == SAEvent.adClicked) {
                // send Corona Lua event
                Map<String, Object> coronaEvent = new HashMap<>();
                coronaEvent.put(EVENT_PHASE_KEY, PHASE_CLICKED);
                coronaEvent.put(EVENT_TYPE_KEY, adType);
                coronaEvent.put(EVENT_PLACEMENTID_KEY, pid);
                dispatchLuaEvent(coronaEvent);
            } else if (saEvent == SAEvent.adClosed) {
                // send Corona Lua event
                Map<String, Object> coronaEvent = new HashMap<>();
                coronaEvent.put(EVENT_PHASE_KEY, adType.equals(TYPE_BANNER) ? PHASE_HIDDEN : PHASE_CLOSED);
                coronaEvent.put(EVENT_TYPE_KEY, adType);
                coronaEvent.put(EVENT_PLACEMENTID_KEY, pid);
                dispatchLuaEvent(coronaEvent);
            } else if (saEvent == SAEvent.adEnded) {
                // send Corona Lua event
                Map<String, Object> coronaEvent = new HashMap<>();
                coronaEvent.put(EVENT_PHASE_KEY, PHASE_PLAYBACK_ENDED);
                coronaEvent.put(EVENT_TYPE_KEY, adType);
                coronaEvent.put(EVENT_PLACEMENTID_KEY, pid);
                dispatchLuaEvent(coronaEvent);
            } else if (saEvent == SAEvent.adAlreadyLoaded) {
                // send Corona Lua event
                Map<String, Object> coronaEvent = new HashMap<>();
                coronaEvent.put(EVENT_PHASE_KEY, PHASE_FAILED);
                coronaEvent.put(EVENT_TYPE_KEY, adType);
                coronaEvent.put(CoronaLuaEvent.ISERROR_KEY, true);
                coronaEvent.put(CoronaLuaEvent.RESPONSE_KEY, RESPONSE_ALREADY_LOADED);
                coronaEvent.put(EVENT_PLACEMENTID_KEY, pid);
                dispatchLuaEvent(coronaEvent);
            }
        }
    }
}
