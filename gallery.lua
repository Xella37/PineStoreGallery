
-- TODO:
-- Randomize order
-- Add cache for same url to buffer (image + size + mode) to make it easier on the backend

local betterblittle = require("betterblittle")

local BASE_URL = "https://pinestore.cc/api"
-- local BASE_URL = "http://localhost:3704/api"

local charToColor = {
	["0"] = colors.white,
	["1"] = colors.orange,
	["2"] = colors.magenta,
	["3"] = colors.lightBlue,
	["4"] = colors.yellow,
	["5"] = colors.lime,
	["6"] = colors.pink,
	["7"] = colors.gray,
	["8"] = colors.lightGray,
	["9"] = colors.cyan,
	["a"] = colors.purple,
	["b"] = colors.blue,
	["c"] = colors.brown,
	["d"] = colors.green,
	["e"] = colors.red,
	["f"] = colors.black,
}

local settings = {
	{
		id = "displayCtrlMenu",
		name = "Display LCtrl for menu",
		options = {
			"yes",
			"no",
		},
		selected = 1,
	},
	{
		id = "displayInfo",
		name = "Display info (title + author)",
		options = {
			"yes",
			"no",
		},
		selected = 1,
	},
	{
		id = "fit",
		name = "Fit mode",
		options = {
			"cover",
			"contain",
			"stretch",
		},
		selected = 1,
	},
	{
		id = "includeMedia",
		name = "Show all media",
		options = {
			"yes",
			"no",
		},
		selected = 2,
	},
	{
		id = "filterProject",
		name = "Filter project id",
		value = "",
	},
	{
		id = "filterUser",
		name = "Filter owner id",
		value = "",
	},
	{
		id = "filterTags",
		name = "Filter tags e.g. \"fun,audio\"",
		value = "",
	},
	{
		id = "sleepDelay",
		name = "Sleep delay in seconds",
		value = "30",
	},
}
local selectedSetting = 1
local function loadSettings()
	if not fs.exists("settings.json") then return end
	local file = fs.open("settings.json", "r")
	local raw = file.readAll()
	file.close()
	local savedSettings = textutils.unserialiseJSON(raw)
	for _, settingSaved in pairs(savedSettings) do
		for _, setting in pairs(settings) do
			if settingSaved.id == setting.id then
				if settingSaved.selected then
					setting.selected = settingSaved.selected
				elseif settingSaved.value then
					setting.value = settingSaved.value
				end
				break
			end
		end
	end
end
loadSettings()

local function saveSettings()
	local file = fs.open("settings.json", "w")
	file.write(textutils.serialiseJSON(settings))
	file.close()
end

local function getSettingValue(id)
	for _, setting in pairs(settings) do
		if setting.id == id then
			if setting.value then
				return setting.value
			elseif setting.options then
				return setting.options[setting.selected]
			end
		end
	end
end

local bufferCache = {}
local function urlToBuffer(url)
	if bufferCache[url] then
		return bufferCache[url]
	end

	local res = http.get(url)
	if not res then return end
	local raw = res.readAll()
	res.close()
	local buffer = {}
	for line in raw:gmatch("[^\n]+") do
		local linebuffer = {}
		local i = 1
		for char in line:gmatch(".") do
			linebuffer[i] = charToColor[char]
			i = i + 1
		end
		buffer[#buffer+1] = linebuffer
	end
	bufferCache[url] = buffer
	return buffer
end

local projects = {}
local function loadProjects()
	local function shuffle(tbl)
		for i = #tbl, 2, -1 do
			local j = math.random(i)
			tbl[i], tbl[j] = tbl[j], tbl[i]
		end
		return tbl
	end

	while true do
		local res = http.get(BASE_URL .. "/projects")
		if not res then
			print("Got no response from the server. Trying again in 5 seconds...")
			sleep(5)
		else
			local raw = res.readAll()
			res.close()

			local data = textutils.unserialiseJSON(raw)
			if data.success then
				projects = shuffle(data.projects)
				return
			else
				print("Error: " .. (data.error or "unknown error"))
				print("Trying again in 60 seconds...")
				sleep(60)
			end
		end
	end
end

local function refreshProjects()
	while true do
		loadProjects()
		sleep(60 * 30) -- reload every half hour
	end
end

local menuOpened = false
local currentBuffer
local currentProject

local function renderFrame()
	if menuOpened then return end

	local width, height = term.getSize()
	local displayCtrlMenu = getSettingValue("displayCtrlMenu") == "yes"
	local displayInfo = getSettingValue("displayInfo") == "yes"

	local win = window.create(term.current(), 1, 1, width, (displayCtrlMenu or displayInfo) and (height - 1) or height)
	betterblittle.drawBuffer(currentBuffer, win)
	if displayCtrlMenu or displayInfo then
		term.setCursorPos(1, height)
		term.setBackgroundColor(colors.black)
		term.clearLine()
		if displayCtrlMenu then
			term.setCursorPos(1, height)
			term.setTextColour(colors.gray)
			term.write("Ctrl 4 Menu")
		end
		if displayInfo then
			local name = currentProject.name
			local author = currentProject.owner_name

			local length = #name + 4 + #author
			term.setCursorPos(math.floor(width*0.5 - length*0.5 + 1), height)
			term.setTextColor(colors.yellow)
			term.write(name)
			term.setTextColor(colors.lightGray)
			term.write(" by ")
			term.setTextColor(colors.white)
			term.write(author)
		end
	end
end

local function inFilter(project)
	local filterProject = tonumber(getSettingValue("filterProject"))
	if filterProject and project.id ~= filterProject then
		return false
	end
	local filterUser = getSettingValue("filterUser")
	if #filterUser > 0 and project.owner_discord ~= filterUser then
		return false
	end
	local filterTags = getSettingValue("filterTags")
	if #filterTags > 0 then
		for tagFilter in filterTags:gmatch("[^,]+") do
			-- check if project has filter
			local hasTag = false
			for _, tag in pairs(project.tags) do
				if tag == tagFilter then
					hasTag = true
					break
				end
			end
			if not hasTag then
				return false
			end
		end
	end

	return true
end

local function render()
	while #projects <= 0 do
		sleep(0.5)
	end

	while true do
		local totalInFilter = 0
		for _, project in pairs(projects) do
			if inFilter(project) then
				totalInFilter = totalInFilter + 1

				local width, height = term.getSize()
				local media = getSettingValue("includeMedia")
				local imageId = "thumbnail"
				if media == "yes" then
					local r = math.random(-1, project.media_count-1)
					if r >= 0 then
						imageId = r
					end
				end
				local url = BASE_URL .. "/project/" .. project.id .. "/image/" .. imageId .. "?w=" .. (width * 2) .. "&h=" .. (height * 3) .. "&mode=" .. getSettingValue("fit")
				local newBuffer = urlToBuffer(url)
				if newBuffer then
					currentBuffer = newBuffer
					currentProject = project
					renderFrame()
				end

				local sleepDelay = tonumber(getSettingValue("sleepDelay"))
				sleep(sleepDelay or 30)
			end
		end
		if totalInFilter > 1 then
			sleep(0)
		else
			sleep(1)
		end
	end
end

local function renderMenu()
	term.setBackgroundColor(colors.black)
	term.clear()
	for i = 1, #settings do
		local setting = settings[i]

		term.setCursorPos(1, i+1)
		if selectedSetting == i then
			term.setTextColor(colors.yellow)
			term.write("> ")
		else
			term.write("  ")
		end

		term.setTextColor(colors.white)
		term.write(setting.name .. ": ")

		local options = setting.options
		if options then
			for j = 1, #options do
				if j == setting.selected then
					term.setBackgroundColor(colors.white)
					term.setTextColor(colors.black)
				else
					term.setBackgroundColor(colors.black)
					term.setTextColor(colors.lightGray)
				end
				term.write(options[j])

				term.setBackgroundColor(colors.black)
				term.write(" ")
			end
		else
			term.write(setting.value)
			if selectedSetting == i then
				term.setTextColor(colors.lightGray)
				term.write("_")
			end
		end
	end
end

local function handleInput()
	local cancelNextCtrl = false
	while true do
		local event, param = os.pullEvent()
		if event == "key" then
			if menuOpened then
				local setting = settings[selectedSetting]
				if param == keys.up then
					selectedSetting = math.max(1, selectedSetting - 1)
				elseif param == keys.down then
					selectedSetting = math.min(#settings, selectedSetting + 1)
				elseif param == keys.left then
					if setting.options then
						setting.selected = math.max(1, setting.selected - 1)
					saveSettings()
					end
				elseif param == keys.right then
					if setting.options then
						setting.selected = math.min(#setting.options, setting.selected + 1)
					saveSettings()
					end
				elseif param == keys.backspace and setting.value then
					setting.value = setting.value:sub(1, #setting.value - 1)
					saveSettings()
				end
			end
		elseif event == "key_up" then
			if param == keys.leftCtrl or param == keys.rightCtrl then
				if cancelNextCtrl then
					cancelNextCtrl = false
				else
					menuOpened = not menuOpened
					if not menuOpened then
						renderFrame()
					end
				end
			end
		elseif event == "char" then
			if menuOpened then
				local setting = settings[selectedSetting]
				if setting.value then
					setting.value = setting.value .. param
					saveSettings()
				end
			end
		elseif event == "paste" then
			if menuOpened then
				local setting = settings[selectedSetting]
				if setting.value then
					setting.value = setting.value .. param
					cancelNextCtrl = true
					saveSettings()
				end
			end
		elseif event == "term_resize" then
			bufferCache = {}
			collectgarbage()
		end

		if menuOpened then
			renderMenu()
		end
	end
end

term.setBackgroundColor(colors.black)
term.setTextColour(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Loading...")
parallel.waitForAny(refreshProjects, render, handleInput)