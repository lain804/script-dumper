while not game:IsLoaded() do
    task.wait()
end

local decompilefunc = function(script_instance)
    local bytecode = getscriptbytecode(script_instance)
    local encoded = crypt.base64encode(bytecode)
    local r = request(
        {
            Url = "http://localhost:3000/luau/decompile",
            Method = "POST",
            Body = encoded
        }
    )
    return r.Body
end

local Logger = loadstring(game:HttpGet("https://raw.githubusercontent.com/lain804/rolog/refs/heads/master/rolog.lua"))()

local DD2 = {}

function DD2:IsDecompilationViable(instance:BaseScript)
    return
        instance:IsA("ModuleScript")
        or instance:IsA("LocalScript")
        or (instance:IsA("Script") and instance.RunContext == Enum.RunContext.Client)
end

function DD2:CollectViableAndUniqueScripts()
    
    function DD2.GenericCollect()
        local scripts = {}
        for _,v in game:GetDescendants() do
            if v:IsA("BaseScript") then
                table.insert(scripts,v)
            end
        end
        return scripts
    end
    
    local scriptCollectionFunctions = {
        { name = "getscripts", collect = getscripts },
        { name = "getmodules", collect = getmodules },
        { name = "getrunningscripts", collect = getrunningscripts },
        { name = "getnilinstances", collect = getnilinstances },
        { name = "GenericCollect", collect = DD2.GenericCollect },
    }

    local bytecodeCache = {}
    local bytecodeOwners = {}

    local scriptPool = {}

    for _,entry in scriptCollectionFunctions do
        local f = entry.collect
        if not f then
            continue
        end

        local collected = f() or {}

        for _,v in collected do
            if table.find(scriptPool,v) then
                continue
            end

            if not DD2:IsDecompilationViable(v) then
                continue
            end

            local ok, bytecode = pcall(getscriptbytecode, v)
            
            if not ok then
                continue
            end

            if not bytecode then
                continue
            end

            local duplicateOwner = bytecodeOwners[bytecode]
            if duplicateOwner then
                continue
            end

            table.insert(bytecodeCache,bytecode)
            bytecodeOwners[bytecode] = v
            table.insert(scriptPool,v)
        end
    end
    return scriptPool
end

local MAX_FILENAME_LENGTH = 255

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

function DD2.GetNextInvalidScriptName(): string
    DD2.InvalidScriptCounter += 1
    local name = "InvalidScript" .. tostring(DD2.InvalidScriptCounter)
    DD2.UsedScriptNames[name] = true
    return name
end

function DD2.GetValidFileNameOrFallback(filename: string): string
    if not DD2.IsValidFileName(filename) then
        return DD2.GetNextInvalidScriptName()
    end

    if not DD2.UsedScriptNames[filename] then
        DD2.UsedScriptNames[filename] = true
        return filename
    end

    local baseName, extension = filename:match("^(.*)%.([^%.]+)$")
    if not baseName then
        baseName = filename
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
            return DD2.GetNextInvalidScriptName()
        end

        if #candidateBase > maxBaseLength then
            candidateBase = candidateBase:sub(1, maxBaseLength)
        end

        local candidate = extension
            and (candidateBase .. suffix .. "." .. extension)
            or (candidateBase .. suffix)

        if DD2.IsValidFileName(candidate) and not DD2.UsedScriptNames[candidate] then
            DD2.UsedScriptNames[candidate] = true
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
    for i,v in getconnections(game:GetService("Players").LocalPlayer.Idled) do
        v:Disable()
    end
end

antiAFK()

local scripts = DD2:CollectViableAndUniqueScripts()
local scriptCount = #scripts

local decompiledCount = 0

task.spawn(function()
    while task.wait(1) do
        if decompiledCount == scriptCount then
            Logger.debug("Decompilation Finished")
            break
        else
            Logger.debug(`Decompiled {decompiledCount} out of {scriptCount} scripts`)
        end
    end
end)

for _,v in scripts do
    local scriptFileName = DD2.GetValidFileNameOrFallback(v.Name)
    local gameScriptPath = DD2.GetSafeFullName(v)
    local note = ("--[[ %* ]]--\n"):format(gameScriptPath)

    local path = DD2.GetDirectoryForScript(v)

    local fullPath = ("%*/%*.lua"):format(path,scriptFileName)
    
    --Logger.debug("Decompiling", gameScriptPath)
    
    task.spawn(function()
        local decompiled = decompilefunc(v)
        local scriptContent = decompiled
        local fullContent = note .. (scriptContent or "")

        writefile(fullPath,fullContent)

        --Logger.debug("Decompiled", gameScriptPath)
        decompiledCount += 1
    end)
end
