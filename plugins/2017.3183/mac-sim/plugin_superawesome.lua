-- SuperAwesome plugin

local Library = require "CoronaLibrary"

-- Create library
local lib = Library:new{ name="plugin.superawesome", publisherId="com.coronalabs", version=2 }

-------------------------------------------------------------------------------
-- BEGIN
-------------------------------------------------------------------------------

-- This sample implements the following Lua:
-- 
--    local superawesome = require "plugin.superawesome"
--    superawesome.init()
--    

local function showWarning(functionName)
    print( functionName .. " WARNING: The SuperAwesome plugin is only supported on iOS and Android devices. Please build for device")
end

function lib.init()
    showWarning("superawesome.init()")
end

function lib.load()
    showWarning("superawesome.load()")
end

function lib.isLoaded()
    showWarning("superawesome.isLoaded()")
end

function lib.show()
    showWarning("superawesome.show()")
end

function lib.hide()
    showWarning("superawesome.hide()")
end

-------------------------------------------------------------------------------
-- END
-------------------------------------------------------------------------------

-- Return an instance
return lib
