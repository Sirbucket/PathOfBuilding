#@ SimpleGraphic
-- Path of Building
--
-- Module: Launch Install
-- Installation bootstrap
--

--Cache globals

local require = require
local ConClear = ConClear
local ConPrintf = ConPrintf
local ipairs = ipairs
local type = type
local Exit = Exit
local Restart = Restart

local io = io
local i_open = io.open

local basicFiles = { "UpdateCheck.lua", "UpdateApply.lua", "Launch.lua" }

local xml = require("xml")
local curl = require("lcurl.safe")

ConClear()
ConPrintf("Preparing to complete installation...\n")

local function manXMLSwitch(node, localBranch, localSource)
	local switch = {
		["Version"] = function(node, localBranch)
			localBranch = node.attrib.branch
		end,
		["Source"] = function(node, localSource)
			if not node.attrib.part == "program" then return end
			localSource = node.attrib.url
		end
	}

	return switch[node] and switch[node](node, localBranch, localSource)
end

local localBranch, localSource
local localManXML = xml.LoadXMLFile("manifest.xml")
if localManXML and localManXML[1].elem == "PoBVersion" then
	for _, node in ipairs(localManXML[1]) do
		if type(node) ~= "table" then return end
		manXMLSwitch(node, localBranch, localSource)
	end
end

if not localBranch or not localSource then
	Exit("Install failed. (Missing or invalid manifest)")
	return
end

localSource = localSource:gsub("{branch}", localBranch)

local text, easy, size, outFile
for _, name in ipairs(basicFiles) do
	text = ""
	easy = curl.easy()
	easy:setopt_url(localSource..name)

	easy:setopt_writefunction(function(data)
		text = text..data 
		return true 
	end)

	easy:perform()
	size = easy:getinfo(curl.INFO_SIZE_DOWNLOAD)
	easy:close()

	if size == 0 then
		Exit("Install failed. (Couldn't download program files)")
		return
	end

	local outFile = i_open(name, "wb")
	outFile:write(text)
	outFile:close()
end

Restart()