while not game:IsLoaded() do
	task.wait()
end

local Logger = loadstring(game:HttpGet("https://raw.githubusercontent.com/lain804/rolog/refs/heads/master/rolog.lua"))()

local DD2 = {}
local HttpService = game:GetService("HttpService")

local function decompileBytecode(bytecode)
	local env = getgenv()
	local encode = env.crypt and env.crypt.base64encode or crypt and crypt.base64encode
	local requestFunction = env.request

	if type(encode) ~= "function" then
		error("base64 encoder unavailable")
	end

	if type(requestFunction) ~= "function" then
		error("request unavailable")
	end

	local encoded = encode(bytecode)
	local response = requestFunction({
		Url = "https://api.lua.expert/decompile",
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json",
		},
		Body = HttpService:JSONEncode({
			script = encoded,
		}),
	})

	local statusCode = response.StatusCode or response.Status
	if type(statusCode) == "number" and (statusCode < 200 or statusCode >= 300) then
		error("decompile request failed: " .. tostring(statusCode))
	end

	local body = response.Body

	return body
end

function DD2:IsDecompilationViable(instance)
	if
		not instance:IsA("LuaSourceContainer")
		or instance:IsA("CoreScript")
		or (instance:IsA("Script") and instance.RunContext == Enum.RunContext.Server)
	then
		return false
	end

	return true
end

function DD2.GenericCollect()
	local scripts = {}

	for _, instance in game:GetDescendants() do
		local ok, viable = pcall(DD2.IsDecompilationViable, DD2, instance)
		if ok and viable then
			table.insert(scripts, instance)
		end
	end

	return scripts
end

function DD2:CollectViableAndUniqueScripts()
	local scriptCollectionFunctions = {
		{ collect = DD2.GenericCollect },
		{ collect = getscripts },
		{ collect = getmodules },
		{ collect = getloadedmodules },
		{ collect = getrunningscripts },
		{ collect = getinstances },
		{ collect = getnilinstances, expandNilRoots = true },
	}

	local candidates = {}
	local candidateSources = {}

	local function addCandidate(instance)
		if typeof(instance) ~= "Instance" or candidateSources[instance] then
			return
		end

		local ok, viable = pcall(DD2.IsDecompilationViable, DD2, instance)
		if not ok or not viable then
			return
		end

		candidateSources[instance] = true
		table.insert(candidates, instance)
	end

	local function collectEntry(entry)
		if type(entry.collect) ~= "function" then
			return
		end

		local ok, collected = pcall(entry.collect)
		if not ok then
			return
		end

		if type(collected) ~= "table" then
			return
		end

		for _, instance in collected do
			addCandidate(instance)

			if entry.expandNilRoots and typeof(instance) == "Instance" then
				local parentOk, parent = pcall(function()
					return instance.Parent
				end)

				if parentOk and parent == nil then
					local descendantsOk, descendants = pcall(function()
						return instance:GetDescendants()
					end)
					if descendantsOk then
						for _, descendant in descendants do
							addCandidate(descendant)
						end
					end
				end
			end
		end
	end

	for _, entry in scriptCollectionFunctions do
		collectEntry(entry)
	end

	local bytecodeOwners = {}
	local scriptPool = {}
	local bytecodeFailures = 0
	local duplicateCount = 0

	for _, instance in candidates do
		local bytecode

		local ok, result = pcall(getscriptbytecode, instance)

		if ok and type(result) == "string" and #result > 0 then
			bytecode = result
		end

		if not bytecode then
			bytecodeFailures += 1
			continue
		end

		local duplicateOwner = bytecodeOwners[bytecode]
		if duplicateOwner then
			duplicateCount += 1
			continue
		end

		bytecodeOwners[bytecode] = instance
		table.insert(scriptPool, {
			instance = instance,
			bytecode = bytecode,
		})
	end

	return scriptPool,
		{
			candidateCount = #candidates,
			uniqueCount = #scriptPool,
			duplicateCount = duplicateCount,
			bytecodeFailures = bytecodeFailures,
		}
end

local MAX_FILENAME_LENGTH = 251

DD2.InvalidScriptCounter = DD2.InvalidScriptCounter or 0
DD2.UsedScriptNames = DD2.UsedScriptNames or {}

function DD2.IsValidFileName(filename: string): boolean
	local RESERVED_NAMES = {
		["CON"] = true,
		["PRN"] = true,
		["AUX"] = true,
		["NUL"] = true,
		["COM1"] = true,
		["COM2"] = true,
		["COM3"] = true,
		["COM4"] = true,
		["COM5"] = true,
		["COM6"] = true,
		["COM7"] = true,
		["COM8"] = true,
		["COM9"] = true,
		["LPT1"] = true,
		["LPT2"] = true,
		["LPT3"] = true,
		["LPT4"] = true,
		["LPT5"] = true,
		["LPT6"] = true,
		["LPT7"] = true,
		["LPT8"] = true,
		["LPT9"] = true,
	}

	if type(filename) ~= "string" then
		return false
	end

	if filename == "" then
		return false
	end

	if filename:find('[%\\/:*%?"<>|]') then
		return false
	end

	if filename:find("[ %.]$") then
		return false
	end

	if filename == "." or filename == ".." then
		return false
	end

	if filename:find("[%z\1-\31]") then
		return false
	end

	local baseName = filename:match("^([^%.]+)") or filename
	baseName = baseName:upper()

	if RESERVED_NAMES[baseName] then
		return false
	end

	if #filename > MAX_FILENAME_LENGTH then
		return false
	end

	return true
end

function DD2.GetNextInvalidScriptName(directory: string): string
	local directoryNames = DD2.UsedScriptNames[directory]

	while true do
		DD2.InvalidScriptCounter += 1
		local name = "InvalidScript" .. tostring(DD2.InvalidScriptCounter)
		local normalizedName = string.lower(name)

		if not directoryNames[normalizedName] then
			directoryNames[normalizedName] = true
			return name
		end
	end
end

function DD2.GetValidFileNameOrFallback(filename: string, directory: string): string
	DD2.UsedScriptNames[directory] = DD2.UsedScriptNames[directory] or {}
	local directoryNames = DD2.UsedScriptNames[directory]

	local targetName = filename
	if not DD2.IsValidFileName(targetName) then
		if type(targetName) ~= "string" then
			return DD2.GetNextInvalidScriptName(directory)
		end

		local sanitized = targetName:gsub('[%\\/:*%?"<>|]', "")
		sanitized = sanitized:gsub("[%z\1-\31]", "")
		sanitized = sanitized:gsub("[ %.]+$", "")

		if sanitized == "" or sanitized == "." or sanitized == ".." then
			return DD2.GetNextInvalidScriptName(directory)
		end
		targetName = sanitized
	end

	local normalizedName = string.lower(targetName)
	if DD2.IsValidFileName(targetName) and not directoryNames[normalizedName] then
		directoryNames[normalizedName] = true
		return targetName
	end

	local baseName, extension = targetName:match("^(.*)%.([^%.]+)$")
	if not baseName then
		baseName = targetName
		extension = nil
	end

	local counter = 2
	while true do
		local suffix = tostring(counter)
		local candidateBase = baseName
		local extraLength = #suffix

		if extension then
			extraLength += #extension + 1
		end

		local maxBaseLength = MAX_FILENAME_LENGTH - extraLength
		if maxBaseLength < 1 then
			return DD2.GetNextInvalidScriptName(directory)
		end

		if #candidateBase > maxBaseLength then
			candidateBase = candidateBase:sub(1, maxBaseLength)
		end

		local candidate = extension and (candidateBase .. suffix .. "." .. extension) or (candidateBase .. suffix)

		local normalizedCandidate = string.lower(candidate)
		if DD2.IsValidFileName(candidate) and not directoryNames[normalizedCandidate] then
			directoryNames[normalizedCandidate] = true
			return candidate
		end

		counter += 1
	end
end

local base = "Script Dumper V2"
local gameFolder = base .. "/" .. tostring(game.PlaceId)
local modulesDir = gameFolder .. "/ModuleScripts"
local defaultDir = gameFolder .. "/LocalScripts"

if not isfolder(base) then
	makefolder(base)
end

if not isfolder(gameFolder) then
	makefolder(gameFolder)
end

if not isfolder(modulesDir) then
	makefolder(modulesDir)
end

if not isfolder(defaultDir) then
	makefolder(defaultDir)
end

function DD2.GetDirectoryForScript(instance)
	if instance:IsA("ModuleScript") then
		return modulesDir
	else
		return defaultDir
	end
end

function DD2.GetLocalPlayer()
	local ok, localPlayer = pcall(function()
		return game:GetService("Players").LocalPlayer
	end)

	if ok then
		return localPlayer
	end

	return nil
end

function DD2.GetInstancePathSegments(instance)
	local segments = {}
	local current = instance
	local localPlayer = DD2.GetLocalPlayer()

	while current and current ~= game do
		if localPlayer and current == localPlayer then
			table.insert(segments, 1, "game.Players.LocalPlayer")

			local parent = current.Parent
			current = parent and parent.Parent or nil
		else
			table.insert(segments, 1, current.Name)
			current = current.Parent
		end
	end

	return segments
end

function DD2.GetSafeFullName(instance)
	local ok, segments = pcall(DD2.GetInstancePathSegments, instance)

	if ok and segments and #segments > 0 then
		return table.concat(segments, ".")
	end

	return instance.Name or "Invalid Script Path"
end

local function antiAFK()
	if type(getconnections) ~= "function" then
		return
	end

	local localPlayer = DD2.GetLocalPlayer()
	if not localPlayer then
		return
	end

	local ok, connections = pcall(getconnections, localPlayer.Idled)
	if not ok or type(connections) ~= "table" then
		return
	end

	for _, connection in connections do
		pcall(connection.Disable, connection)
	end
end

antiAFK()

local scripts, collectionStats = DD2:CollectViableAndUniqueScripts()
local scriptCount = #scripts
local decompiledCount = 0
local decompileFailures = 0

for _, job in scripts do
	local instance = job.instance
	local directory = DD2.GetDirectoryForScript(instance)
	local scriptFileName = DD2.GetValidFileNameOrFallback(instance.Name, directory)

	job.gameScriptPath = DD2.GetSafeFullName(instance)
	job.fullPath = ("%*/%*.lua"):format(directory, scriptFileName)
end

local function writeOnce(path, content)
	local ok, result = pcall(writefile, path, content)
	if ok then
		return true
	end

	return false, tostring(result)
end

for _, job in scripts do
	local ok = pcall(function()
		local decompiled = decompileBytecode(job.bytecode)
		if not decompiled then
			error("decompile failed")
		end

		local note = ("--[[ %* ]]--\n"):format(job.gameScriptPath)
		local writeOk, writeError = writeOnce(job.fullPath, note .. decompiled)
		if not writeOk then
			error("write failed: " .. tostring(writeError))
		end
	end)

	if not ok then
		decompileFailures += 1
	end

	decompiledCount += 1
	Logger.debug(`Decompiled {decompiledCount} out of {scriptCount} scripts`)
end

Logger.debug(
	`Finished: {scriptCount - decompileFailures}/{scriptCount} unique scripts written; `
		.. `{collectionStats.duplicateCount} duplicate instances and `
		.. `{collectionStats.bytecodeFailures} bytecode failures`
)
