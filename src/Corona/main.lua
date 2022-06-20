-- Abstract: SuperAwesome
-- Version: 1.0
-- Sample code is MIT licensed; see https://www.coronalabs.com/links/code/license
---------------------------------------------------------------------------------------

local superawesome = require("plugin.superawesome")
local widget = require("widget")
local json = require("json")

display.setStatusBar( display.HiddenStatusBar )

local background = display.newImageRect("back-whiteorange.png", display.actualContentWidth, display.actualContentHeight)
background.x = display.contentCenterX
background.y = display.contentCenterY

local r1 = display.newRect(0,0,50,50)
r1.anchorX, r1.anchorY = 0, 0
r1:setFillColor(1,0,0)
local r2 = display.newRect(0,0,50,50)
r2.anchorX, r2.anchorY = 1, 1
r2:setFillColor(1,0,0)

r1.x = display.screenOriginX
r1.y = display.screenOriginY
r2.x = display.actualContentWidth + display.screenOriginX
r2.y = display.actualContentHeight + display.screenOriginY


local placementIds = {
	{adUnitType = "banner", 		pid = "31231", info = "300x50",  size = "BANNER_50"},
	{adUnitType = "banner", 		pid = "31232", info = "320x50",  size = "BANNER_50"},
	{adUnitType = "banner", 		pid = "31235", info = "728x90",  size = "BANNER_90"},
	{adUnitType = "banner", 		pid = "31236", info = "300x250", size = "BANNER_250"},
	{adUnitType = "interstitial", 	pid = "31237", info = "320x480"},
	{adUnitType = "interstitial", 	pid = "31238", info = "480x320"},
	{adUnitType = "interstitial", 	pid = "31240", info = "768x1024"},
	{adUnitType = "interstitial", 	pid = "31241", info = "1024x768"},
	{adUnitType = "video", 			pid = "32430", info = "600x480"}
}
local currentPlacementId = 1

local adTypeText = display.newText({
	text = string.format("%s, %s, PID: %s", 
		placementIds[currentPlacementId].adUnitType, 
		placementIds[currentPlacementId].info, 
		placementIds[currentPlacementId].pid
	),
	font = native.systemFont,
	fontSize = 14,
	align = "left",
	width = 320,
	height = 200,
})
adTypeText:setFillColor(0)
adTypeText.anchorX = 0
adTypeText.anchorY = 0
adTypeText.x = 5
adTypeText.y = display.screenOriginY + 10

local statusText = display.newText({
	text = "",
	font = native.systemFont,
	fontSize = 14,
	align = "left",
	width = 320,
	height = 200,
})
statusText:setFillColor(0)
statusText.anchorX = 0
statusText.anchorY = 0
statusText.x = 5
statusText.y = display.screenOriginY + 30

local function superawesomeListener(event)
    local logString = json.prettify(event):gsub("\\","")
    logString = "\nPHASE: "..event.phase.." - - - - - - - - - \n" .. logString
	statusText.text = logString
	print(logString)
end

superawesome.init(superawesomeListener, {
	testMode = true,
})

local changePidButton = widget.newButton({
	label = "Change PID",
	width = 250,
	onRelease = function(event)
		currentPlacementId = currentPlacementId + 1
		if currentPlacementId > #placementIds then
			currentPlacementId = 1
		end

		adTypeText.text = string.format("%s, %s, PID: %s", 
			placementIds[currentPlacementId].adUnitType, 
			placementIds[currentPlacementId].info, 
			placementIds[currentPlacementId].pid
		)
	end
})
changePidButton.x = display.contentCenterX
changePidButton.y = statusText.y + (statusText.height) + 10

local loadAdButton = widget.newButton({
	label = "Load Ad",
	onRelease = function(event)
		superawesome.load(
			placementIds[currentPlacementId].adUnitType, 			
			{
				placementId=placementIds[currentPlacementId].pid, 
				bannerSize=placementIds[currentPlacementId].size,
				bannerTransparency=true
			}
		)
	end
})
loadAdButton.x = display.contentCenterX
loadAdButton.y = changePidButton.y + loadAdButton.height + loadAdButton.height * .15

local showAdButton = widget.newButton({
	label = "Show Ad",
	onRelease = function(event)
		local adOptions = {
			useParentalGate = true,
			showVideoCloseButton = false,
			useSmallClickZone = false,
			closeVideoAtEnd = false,
			y = "bottom"
		}
		superawesome.show(placementIds[currentPlacementId].pid, adOptions)
	end
})
showAdButton.x = display.contentCenterX
showAdButton.y = loadAdButton.y + showAdButton.height + showAdButton.height * .15

local hideAdButton = widget.newButton({
	label = "Hide Ad",
	onRelease = function(event)
		superawesome.hide(placementIds[currentPlacementId].pid)
	end
})
hideAdButton.x = display.contentCenterX
hideAdButton.y = showAdButton.y + hideAdButton.height + hideAdButton.height * .15
