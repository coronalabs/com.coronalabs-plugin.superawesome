local metadata =
{
    plugin =
    {
        format = 'jar',
        manifest =
        {
            permissions = {},

            usesPermissions =
            {
                "android.permission.INTERNET",
                "android.permission.ACCESS_NETWORK_STATE"
            },

            usesFeatures =
            {
            },

            applicationChildElements =
            {
                [[
                <activity android:name="tv.superawesome.sdk.publisher.SAVideoAd"
                          android:label="SAFullscreenVideoAd"
                          android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen"
                          android:configChanges="keyboardHidden|orientation|screenSize"/>

                <activity android:name="tv.superawesome.sdk.publisher.SAInterstitialAd"
                          android:label="SAInterstitialAd"
                          android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen"
                          android:configChanges="keyboardHidden|orientation|screenSize"/>

                <activity android:name="tv.superawesome.sdk.publisher.SAAppWall"
                          android:screenOrientation="portrait"
                          android:label="SAAppWall"
                          android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen"
                          android:configChanges="keyboardHidden|orientation|screenSize"/>

                <service android:name="tv.superawesome.lib.sanetwork.asynctask.SAAsyncTask$SAAsync"
                         android:exported="false"
                         android:permission="tv.superawesome.sdk.SuperAwesomeSDK"/>
                ]]
            }
        }
    },

    coronaManifest = {
        dependencies = {
            ["shared.google.play.services.ads.identifier"] = "com.coronalabs"
        }
    }
}

return metadata
