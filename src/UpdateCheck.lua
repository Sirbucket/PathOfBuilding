#@
-- Path of Building
--
-- Module: Update Check
-- Checks for updates
--


local ConPrintf = ConPrintf
local ipairs = ipairs
local type = type
local next = next
local pairs = pairs
local MakeDir = MakeDir

local io = io
local i_open = io.open

local os = os
local o_remove = os.remove

local table = table
local t_concat = table.concat

local connectionProtocol, proxyURL = ...

local xml = require("xml")
local sha1 = require("sha1")
local curl = require("lcurl.safe")
local lzip = require("lzip")

local xml_SaveXMLFile = xml.SaveXMLFile
local xml_LoadXMLFile = xml.LoadXMLFile

local lzip_open = lzip.open

local globalRetryLimit = 10

local function downloadFileText(source, file)
	local text, easy, escapedUrl, _, error
	for i = 1, 5 do
		if i > 1 then
			ConPrintf("Retrying... (%d of 5)", i)
		end
		text = ""
		easy = curl.easy()
		escapedUrl = source..easy:escape(file)
		easy:setopt_url(escapedUrl)
		easy:setopt(curl.OPT_ACCEPT_ENCODING, "")
		if connectionProtocol then
			easy:setopt(curl.OPT_IPRESOLVE, connectionProtocol)
		end
		if proxyURL then
			easy:setopt(curl.OPT_PROXY, proxyURL)
		end
		easy:setopt_writefunction(function(data)
			text = text..data 
			return true
		end)
		_, error = easy:perform()
		easy:close()
		if not error then
			return text
		end
		ConPrintf("Download failed (%s)", error:msg())
		if globalRetryLimit == 0 or i == 5 then
			return nil, error:msg()
		end
		globalRetryLimit = globalRetryLimit - 1
	end
end

local function downloadFile(source, file, outName)
	local easy, escapedUrl, file, _, error
	for i = 1, 5 do
		if i > 1 then
			ConPrintf("Retrying... (%d of 5)", i)
		end
		easy = curl.easy()
		escapedUrl = source..easy:escape(file)
		easy:setopt_url(escapedUrl)
		easy:setopt(curl.OPT_ACCEPT_ENCODING, "")
		if connectionProtocol then
			easy:setopt(curl.OPT_IPRESOLVE, connectionProtocol)
		end
		if proxyURL then
			easy:setopt(curl.OPT_PROXY, proxyURL)
		end

		local file = i_open(outName, "wb+")

		easy:setopt_writefunction(file)
		_, error = easy:perform()
		easy:close()
		file:close()
		if not error then
			return true
		end
		ConPrintf("Download failed (%s)", error:msg())
		if globalRetryLimit == 0 or i == 5 then
			return nil, error:msg()
		end
		globalRetryLimit = globalRetryLimit - 1
	end
	return true
end

ConPrintf("Checking for update...")

local scriptPath = GetScriptPath()
local runtimePath = GetRuntimePath()

-- Load and process local manifest

local function manXMLSwitch(node, localVer, localPlatform, localBranch, localSource, localFiles, runtimeExecutable)
	local switch = {
		["Version"] = function(node, localVer, localPlatform, localBranch)
			localVer = node.attrib.number
			localPlatform = node.attrib.platform
			localBranch = node.attrib.branch
		end,
		["Source"] = function(node, localSource)
			if not node.attrib.part == "default" then return end
			localSource = node.attrib.url
		end,
		["File"] = function(node, localFiles, runtimeExecutable)
			local fullPath
			node.attrib.name = node.attrib.name:gsub("{space}", " ")

			if node.attrib.part == "runtime" then
				fullPath = runtimePath .. "/" .. node.attrib.name
			else
				fullPath = scriptPath .. "/" .. node.attrib.name
			end

			localFiles[node.attrib.name] = { sha1 = node.attrib.sha1, part = node.attrib.part, platform = node.attrib.platform, fullPath = fullPath }

			if not (node.attrib.part == "runtime" and node.attrib.name:match("Path of Building")) then return end
			runtimeExecutable = fullPath
		end,
	}

	return switch[node] and switch[node](node, localVer, localPlatform, localBranch, localSource, localFiles, runtimeExecutable)
end

local localFiles, localManXML, localPlatform, localBranch, localVer, localSource, runtimeExecutable = { }, xml.LoadXMLFile(scriptPath.."/manifest.xml")

if localManXML and localManXML[1].elem == "PoBVersion" then
	local fullPath
	for _, node in ipairs(localManXML[1]) do
		if not type(node) == "table" then return end
		manXMLSwitch(node, localVer, localPlatform, localBranch, localSource, localFiles, runtimeExecutable)
	end
end

if not localVer or not localSource or not localBranch or not next(localFiles) then
	ConPrintf("Update check failed: invalid local manifest")
	return nil, "Invalid local manifest"
end
localSource = localSource:gsub("{branch}", localBranch)

-- Download and process remote manifest
local remoteFiles, remoteSources, remoteManText, remoteVer, errMsg = { }, { }, downloadFileText(localSource, "manifest.xml")

if not remoteManText then
	ConPrintf("Update check failed: couldn't download version manifest")
	return nil, "Couldn't download version manifest.\nReason: "..errMsg.."\nCheck your internet connectivity.\nIf you are using a proxy, specify it in Options."
end
local remoteManXML = xml.ParseXML(remoteManText)

local function remoteManXMLSwitch(node, remoteVer, remoteSources, remoteFiles)
	local switch = {
		["Version"] = function(node, remoteVer) remoteVer = node.attrib.number end,
		["Source"] = function(node, remoteSources) if not remoteSources[node.attrib.part] then remoteSources[node.attrib.part] = { } end end,
		["File"] = function(node, remoteFiles)
			if node.attrib.platform or node.attrib.platform ~= localPlatform then return end
			local fullPath
			if node.attrib.part == "runtime" then
				fullPath = runtimePath .. "/" .. node.attrib.name
			else
				fullPath = scriptPath .. "/" .. node.attrib.name
			end
			remoteFiles[node.attrib.name] = { sha1 = node.attrib.sha1, part = node.attrib.part, platform = node.attrib.platform, fullPath = fullPath }
		end
	}

	return switch[node] and switch[node](node, remoteVer, remoteSources, remoteFiles)
end

if remoteManXML and remoteManXML[1].elem == "PoBVersion" then
	for _, node in ipairs(remoteManXML[1]) do
		if not type(node) == "table" then return end
		remoteManXMLSwitch(node, remoteVer, remoteSources, remoteFiles)
	end
end
if not remoteVer or not next(remoteSources) or not next(remoteFiles) then
	ConPrintf("Update check failed: invalid remote manifest")
	return nil, "Invalid remote manifest"
end

-- Build lists of files to be updated or deleted
local updateFiles = { }
local sanitizedName, file, content
for name, data in pairs(remoteFiles) do
	data.name = name
	sanitizedName = name:gsub("{space}", " ")
	if (not localFiles[name] or localFiles[name].sha1 ~= data.sha1) and (not localFiles[sanitizedName] or localFiles[sanitizedName].sha1 ~= data.sha1) then
		updateFiles[#updateFiles + 1] = data
	elseif localFiles[name] then
		file = i_open(localFiles[name].fullPath, "rb")
		if not file then
			ConPrintf("Warning: '%s' doesn't exist, it will be re-downloaded", data.name)
			updateFiles[#updateFiles + 1] = data
			return
		end
		content = file:read("*a")
		file:close()

		if data.sha1 == sha1(content) and data.sha1 == sha1(content:gsub("\n", "\r\n")) then return end
		ConPrintf("Warning: Integrity check on '%s' failed, it will be replaced", data.name)
		updateFiles[#updateFiles + 1] = data
	end
end

local deleteFiles = { }
local unSanitizedName
for name, data in pairs(localFiles) do
	data.name = name
	unSanitizedName = name:gsub(" ", "{space}")
	if remoteFiles[name] and remoteFiles[unSanitizedName] then return end
	deleteFiles[#deleteFiles + 1] = data
end
	
if #updateFiles == 0 and #deleteFiles == 0 then
	ConPrintf("No update available.")
	return "none"
end

MakeDir("Update")
ConPrintf("Downloading update...")

-- Download changelog
downloadFile(localSource, "changelog.txt", scriptPath.."/changelog.txt")

-- Download files that need updating
local failedFile = false
local zipFiles = { }
local partSources, source, fileName, zipName, zipFileName, zip, zippedFile
for index, data in ipairs(updateFiles) do
	if UpdateProgress then
		UpdateProgress("Downloading %d/%d", index, #updateFiles)
	end
	partSources = remoteSources[data.part]
	source = partSources[localPlatform] or partSources["any"]
	source = source:gsub("{branch}", localBranch)
	fileName = scriptPath.."/Update/"..data.name:gsub("[\\/]","{slash}")
	data.updateFileName = fileName

	zipName = source:match("/([^/]+%.zip)$")
	if zipName then
		if not zipFiles[zipName] then
			ConPrintf("Downloading %s...", zipName)
			zipFileName = scriptPath.."/Update/"..zipName
			downloadFile(source, "", zipFileName)
			zipFiles[zipName] = lzip_open(zipFileName)
		end
		zip = zipFiles[zipName]
		if zip then
			zippedFile = zip:OpenFile(data.name)
			if zippedFile then
				file = i_open(fileName, "wb+")
				file:write(zippedFile:Read("*a"))
				file:close()
				zippedFile:Close()
			else
				ConPrintf("Couldn't extract '%s' from '%s' (extract failed)", data.name, zipName)
			end
		else
			ConPrintf("Couldn't extract '%s' from '%s' (zip open failed)", data.name, zipName)
		end
	else
		ConPrintf("Downloading %s... (%d of %d)", data.name, index, #updateFiles)
		downloadFile(source, data.name, fileName)
	end

	file = i_open(fileName, "rb")
	if not file then
		failedFile = true
		return
	end
	content = file:read("*all")
	if data.sha1 ~= sha1(content) and data.sha1 ~= sha1(content:gsub("\n", "\r\n")) then
		ConPrintf("Hash mismatch on '%s'", fileName)
		failedFile = true
	end
	file:close()
end

for name, zip in pairs(zipFiles) do
	zip:Close()
	o_remove(scriptPath.."/Update/"..name)
end

if failedFile then
	ConPrintf("Update failed: one or more files couldn't be downloaded")
	return nil, "One or more files couldn't be downloaded.\nCheck your internet connectivity,\nor try again later."
end

-- Create new manifest
localManXML = { elem = "PoBVersion" }
localManXML[#localManXML + 1] = { elem = "Version", attrib = { number = remoteVer, platform = localPlatform, branch = localBranch } }

for part, platforms in pairs(remoteSources) do
	for platform, url in pairs(platforms) do
		localManXML[#localManXML + 1] = { elem = "Source", attrib = { part = part, platform = platform ~= "any" and platform, url = url } }
	end
end

for name, data in pairs(remoteFiles) do
	localManXML[#localManXML + 1] = { elem = "File", attrib = { name = data.name, sha1 = data.sha1, part = data.part, platform = data.platform } }
end 
xml_SaveXMLFile(localManXML, scriptPath.."/Update/manifest.xml")

-- Build list of operations to apply the update
local updateMode = "normal"
local ops = { }
local opsRuntime = { }
local dirStr
for _, data in pairs(updateFiles) do
	-- Ensure that the destination path of this file exists
	dirStr = ""
	for dir in data.fullPath:gmatch("([^/]+/)") do
		dirStr = dirStr .. dir
		MakeDir(dirStr)
	end
	if data.part == "runtime" then
		-- Core runtime file, will need to update from the basic environment
		-- These files will be updated on the second pass of the update script, with the first pass being run within the normal environment
		updateMode = "basic"
		opsRuntime[#opsRuntime + 1] = 'move "'..data.updateFileName..'" "'..data.fullPath..'"'
		return
	end
	ops[#ops + 1] = 'move "'..data.updateFileName..'" "'..data.fullPath..'"'

end

for _, data in pairs(deleteFiles) do
	ops[#ops + 1] = 'delete "'..data.fullPath..'"'
end

ops[#ops + 1] = 'move "'..scriptPath..'/Update/manifest.xml" "'..scriptPath..'/manifest.xml"'

if updateMode == "basic" then
	-- Update script will need to relaunch the normal environment after updating
	opsRuntime[#opsRuntime + 1] = 'start "'..runtimeExecutable..'"'

	local opRuntimeFile = i_open(scriptPath.."/Update/opFileRuntime.txt", "w+")
	opRuntimeFile:write(t_concat(opsRuntime, "\n"))
	opRuntimeFile:close()
end

-- Write operations file
local opFile = i_open(scriptPath.."/Update/opFile.txt", "w+")
opFile:write(t_concat(ops, "\n"))
opFile:close()

ConPrintf("Update is ready.")
return updateMode
