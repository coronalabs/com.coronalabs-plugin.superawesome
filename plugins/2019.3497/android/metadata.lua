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
                "android.permission.ACCESS_NETWORK_STATE",
                "android.permission.WRITE_EXTERNAL_STORAGE"
            },

            usesFeatures =
            {
            },

        }
    },

    coronaManifest = {
        dependencies = {
            ["shared.android.support.v7.appcompat"] = "com.coronalabs"
        }
    }
}

return metadata
