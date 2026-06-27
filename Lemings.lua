-- Lemming v2: Game File Ripper for Delta Executor (Mobile + PC)
-- Fixed: Freeze at "Grabbing Scripts" | Export via clipboard + base64 decode
-- No writefile permission needed. Uses setclipboard + external decoder.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local screenSize = workspace.CurrentCamera.ViewportSize
local scaleFactor = math.min(screenSize.X / 400, screenSize.Y / 700)

if syn and syn.protect_gui then
    syn.protect_gui(CoreGui)
end

-- Base64 encoder (pure Lua, no external deps)
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64Encode(data)
    local bytes = {}
    for i = 1, #data do
        bytes[i] = string.byte(data, i)
    end
    local result = {}
    for i = 1, #bytes, 3 do
        local b1 = bytes[i]
        local b2 = bytes[i+1] or 0
        local b3 = bytes[i+2] or 0
        local n = b1 * 65536 + b2 * 256 + b3
        local c1 = math.floor(n / 262144)
        local c2 = math.floor((n % 262144) / 4096)
        local c3 = math.floor((n % 4096) / 64)
        local c4 = n % 64
        table.insert(result, string.sub(b64chars, c1+1, c1+1))
        table.insert(result, string.sub(b64chars, c2+1, c2+1))
        if i+1 <= #bytes then
            table.insert(result, string.sub(b64chars, c3+1, c3+1))
        else
            table.insert(result, "=")
        end
        if i+2 <= #bytes then
            table.insert(result, string.sub(b64chars, c4+1, c4+1))
        else
            table.insert(result, "=")
        end
    end
    return table.concat(result)
end

-- Chunked clipboard for large files (splits >2MB into multiple clipboard sets)
local function setLargeClipboard(data)
    local chunks = {}
    local chunkSize = 1800000 -- 1.8MB per chunk (safe limit for mobile)
    local totalLen = #data
    for i = 1, totalLen, chunkSize do
        local chunk = string.sub(data, i, math.min(i + chunkSize - 1, totalLen))
        table.insert(chunks, chunk)
    end
    if #chunks == 1 then
        setclipboard(chunks[1])
        return 1
    else
        local manifest = "LEMMING_SPLIT:" .. #chunks .. ":" .. totalLen .. "|"
        for i, chunk in ipairs(chunks) do
            if i == 1 then
                setclipboard(manifest .. chunk)
            end
        end
        return #chunks
    end
end

local SETTINGS = {
    Accent = Color3.fromRGB(0, 255, 140),
    Background = Color3.fromRGB(25, 25, 30),
    Secondary = Color3.fromRGB(35, 35, 40),
    Text = Color3.fromRGB(220, 220, 220),
    BatchSize = 50, -- Process objects in batches to prevent freeze
    BatchDelay = 0.05, -- Seconds between batches
}

local copiedData = {
    Instances = {},
    Scripts = {},
    Metadata = {}
}

-- Recursive copy with depth guard
local function recursiveCopy(instance, depth)
    depth = depth or 0
    if depth > 200 then return nil end
    if not instance or not instance.Parent then return nil end
    local data = {
        ClassName = instance.ClassName,
        Name = instance.Name,
        Properties = {},
        Children = {}
    }
    local propsToCopy = {
        "Position", "Size", "Color", "Material", "Transparency",
        "Reflectance", "Anchored", "CanCollide", "Locked", "BrickColor",
        "Text", "Font", "TextSize", "TextColor3", "BackgroundColor3",
        "Image", "ImageRectSize", "ImageRectOffset", "MeshId", "TextureId"
    }
    for _, prop in pairs(propsToCopy) do
        pcall(function()
            local val = instance[prop]
            if val ~= nil then
                if typeof(val) == "CFrame" then
                    data.Properties[prop] = {val:GetComponents()}
                elseif typeof(val) == "Vector3" then
                    data.Properties[prop] = {val.X, val.Y, val.Z}
                elseif typeof(val) == "Color3" then
                    data.Properties[prop] = {val.R, val.G, val.B}
                elseif typeof(val) == "BrickColor" then
                    data.Properties[prop] = val.Number
                else
                    data.Properties[prop] = val
                end
            end
        end)
    end
    if SETTINGS.GrabInstances ~= false then
        for _, child in pairs(instance:GetChildren()) do
            local childData = recursiveCopy(child, depth + 1)
            if childData then
                table.insert(data.Children, childData)
            end
        end
    end
    return data
end

-- Batch processor to prevent freezing
local function processBatch(items, startIdx, batchSize, callback)
    local total = #items
    local idx = startIdx or 1
    spawn(function()
        while idx <= total do
            local batchEnd = math.min(idx + batchSize - 1, total)
            for i = idx, batchEnd do
                local success, err = pcall(callback, items[i], i, total)
                if not success then
                    -- Silently skip problematic objects
                end
            end
            idx = batchEnd + 1
            if idx <= total then
                local progress = idx / total
                pcall(function()
                    ui.ProgFill:TweenSize(UDim2.new(progress, 0, 1, 0), "Out", "Quad", 0.1, true)
                end)
                wait(SETTINGS.BatchDelay)
            end
        end
    end)
    return total
end

-- Mobile-optimized Circle UI
local function createMobileCircleUI()
    local screen = Instance.new("ScreenGui")
    screen.Name = "LemmingUI"
    screen.Parent = CoreGui
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.IgnoreGuiInset = true

    local w = math.floor(340 * scaleFactor)
    local h = math.floor(540 * scaleFactor)
    local circleSize = math.floor(130 * scaleFactor)
    local fontSize = math.floor(16 * scaleFactor)
    local smallFont = math.floor(12 * scaleFactor)
    local tinyFont = math.floor(10 * scaleFactor)

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "Main"
    mainFrame.Size = UDim2.new(0, w, 0, h)
    mainFrame.Position = UDim2.new(0.5, -w/2, 0.5, -h/2)
    mainFrame.BackgroundColor3 = SETTINGS.Background
    mainFrame.BackgroundTransparency = 0.1
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screen

    local circleCorner = Instance.new("UICorner")
    circleCorner.CornerRadius = UDim.new(0, math.floor(22 * scaleFactor))
    circleCorner.Parent = mainFrame

    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, math.floor(50 * scaleFactor))
    titleBar.BackgroundColor3 = SETTINGS.Secondary
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame

    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, math.floor(22 * scaleFactor))
    titleCorner.Parent = titleBar

    local titlePatch = Instance.new("Frame")
    titlePatch.Size = UDim2.new(1, 0, 0.5, 0)
    titlePatch.Position = UDim2.new(0, 0, 0.5, 0)
    titlePatch.BackgroundColor3 = SETTINGS.Secondary
    titlePatch.BorderSizePixel = 0
    titlePatch.Parent = titleBar

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -20, 1, 0)
    titleText.Position = UDim2.new(0, 10, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = "LEMMING v2"
    titleText.TextColor3 = SETTINGS.Accent
    titleText.TextSize = math.floor(20 * scaleFactor)
    titleText.Font = Enum.Font.GothamBold
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = titleBar

    -- Touch drag
    local dragToggle = Instance.new("TextButton")
    dragToggle.Size = UDim2.new(1, 0, 1, 0)
    dragToggle.BackgroundTransparency = 1
    dragToggle.Text = ""
    dragToggle.Parent = titleBar
    local dragging, dragStart, startPos
    dragToggle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    dragToggle.InputChanged:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) and dragging then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- Circle button container
    local circleContainer = Instance.new("Frame")
    circleContainer.Size = UDim2.new(1, 0, 0, math.floor(200 * scaleFactor))
    circleContainer.Position = UDim2.new(0, 0, 0, math.floor(60 * scaleFactor))
    circleContainer.BackgroundTransparency = 1
    circleContainer.Parent = mainFrame

    -- Main circle button
    local startButton = Instance.new("TextButton")
    startButton.Size = UDim2.new(0, circleSize, 0, circleSize)
    startButton.Position = UDim2.new(0.5, -circleSize/2, 0, math.floor(5 * scaleFactor))
    startButton.BackgroundColor3 = SETTINGS.Accent
    startButton.Text = "START\nCOPY"
    startButton.TextColor3 = Color3.fromRGB(15, 15, 20)
    startButton.TextSize = fontSize
    startButton.Font = Enum.Font.GothamBold
    startButton.BorderSizePixel = 0
    startButton.Parent = circleContainer

    local circleCorner2 = Instance.new("UICorner")
    circleCorner2.CornerRadius = UDim.new(1, 0)
    circleCorner2.Parent = startButton

    -- Pulse
    local pulseFrame = Instance.new("Frame")
    local pulseBase = circleSize + math.floor(20 * scaleFactor)
    pulseFrame.Size = UDim2.new(0, pulseBase, 0, pulseBase)
    pulseFrame.Position = UDim2.new(0.5, -pulseBase/2, 0, -math.floor(8 * scaleFactor))
    pulseFrame.BackgroundColor3 = SETTINGS.Accent
    pulseFrame.BackgroundTransparency = 0.6
    pulseFrame.BorderSizePixel = 0
    pulseFrame.ZIndex = 0
    pulseFrame.Parent = circleContainer

    local pulseCorner = Instance.new("UICorner")
    pulseCorner.CornerRadius = UDim.new(1, 0)
    pulseCorner.Parent = pulseFrame

    spawn(function()
        local expandSize = pulseBase + math.floor(25 * scaleFactor)
        while pulseFrame and pulseFrame.Parent do
            pulseFrame:TweenSize(UDim2.new(0, expandSize, 0, expandSize), "Out", "Sine", 1.2, true)
            pulseFrame.Position = UDim2.new(0.5, -expandSize/2, 0, -math.floor(20 * scaleFactor))
            wait(1.2)
            pulseFrame:TweenSize(UDim2.new(0, pulseBase, 0, pulseBase), "Out", "Sine", 1.2, true)
            pulseFrame.Position = UDim2.new(0.5, -pulseBase/2, 0, -math.floor(8 * scaleFactor))
            wait(1.2)
        end
    end)

    -- Status Text
    local statusText = Instance.new("TextLabel")
    statusText.Size = UDim2.new(1, -20, 0, math.floor(22 * scaleFactor))
    statusText.Position = UDim2.new(0, 10, 0, circleSize + math.floor(18 * scaleFactor))
    statusText.BackgroundTransparency = 1
    statusText.Text = "READY"
    statusText.TextColor3 = SETTINGS.Text
    statusText.TextSize = smallFont
    statusText.Font = Enum.Font.Gotham
    statusText.Parent = circleContainer

    -- Progress bar
    local progFrame = Instance.new("Frame")
    progFrame.Size = UDim2.new(1, -math.floor(30 * scaleFactor), 0, math.floor(5 * scaleFactor))
    progFrame.Position = UDim2.new(0, math.floor(15 * scaleFactor), 0, circleSize + math.floor(46 * scaleFactor))
    progFrame.BackgroundColor3 = SETTINGS.Secondary
    progFrame.BorderSizePixel = 0
    progFrame.Visible = false
    progFrame.Parent = circleContainer
    local progCorner = Instance.new("UICorner")
    progCorner.CornerRadius = UDim.new(1, 0)
    progCorner.Parent = progFrame

    local progFill = Instance.new("Frame")
    progFill.Size = UDim2.new(0, 0, 1, 0)
    progFill.BackgroundColor3 = SETTINGS.Accent
    progFill.BorderSizePixel = 0
    progFill.Name = "Fill"
    progFill.Parent = progFrame
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = progFill

    -- Info panel
    local infoFrame = Instance.new("Frame")
    infoFrame.Size = UDim2.new(1, -math.floor(20 * scaleFactor), 0, math.floor(90 * scaleFactor))
    infoFrame.Position = UDim2.new(0, math.floor(10 * scaleFactor), 0, math.floor(275 * scaleFactor))
    infoFrame.BackgroundColor3 = SETTINGS.Secondary
    infoFrame.BackgroundTransparency = 0.3
    infoFrame.BorderSizePixel = 0
    infoFrame.Parent = mainFrame

    local infoCorner = Instance.new("UICorner")
    infoCorner.CornerRadius = UDim.new(0, math.floor(12 * scaleFactor))
    infoCorner.Parent = infoFrame

    local infoText = Instance.new("TextLabel")
    infoText.Size = UDim2.new(1, -math.floor(16 * scaleFactor), 1, -math.floor(8 * scaleFactor))
    infoText.Position = UDim2.new(0, math.floor(8 * scaleFactor), 0, math.floor(4 * scaleFactor))
    infoText.BackgroundTransparency = 1
    infoText.Text = "Place: " .. game.PlaceId .. "\nGame: " .. game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
    infoText.TextColor3 = SETTINGS.Text
    infoText.TextSize = tinyFont
    infoText.Font = Enum.Font.Gotham
    infoText.TextXAlignment = Enum.TextXAlignment.Left
    infoText.TextYAlignment = Enum.TextYAlignment.Top
    infoText.TextWrapped = true
    infoText.Parent = infoFrame

    -- Export Buttons (multiple methods)
    local exportBtn1 = Instance.new("TextButton")
    exportBtn1.Size = UDim2.new(1, -math.floor(30 * scaleFactor), 0, math.floor(36 * scaleFactor))
    exportBtn1.Position = UDim2.new(0, math.floor(15 * scaleFactor), 0, math.floor(378 * scaleFactor))
    exportBtn1.BackgroundColor3 = SETTINGS.Accent
    exportBtn1.Text = "COPY TO CLIPBOARD"
    exportBtn1.TextColor3 = Color3.fromRGB(15, 15, 20)
    exportBtn1.TextSize = smallFont
    exportBtn1.Font = Enum.Font.GothamBold
    exportBtn1.BorderSizePixel = 0
    exportBtn1.Visible = false
    exportBtn1.Name = "ExportBtn1"
    exportBtn1.Parent = mainFrame

    local exportCorner1 = Instance.new("UICorner")
    exportCorner1.CornerRadius = UDim.new(0, math.floor(14 * scaleFactor))
    exportCorner1.Parent = exportBtn1

    local exportBtn2 = Instance.new("TextButton")
    exportBtn2.Size = UDim2.new(1, -math.floor(30 * scaleFactor), 0, math.floor(36 * scaleFactor))
    exportBtn2.Position = UDim2.new(0, math.floor(15 * scaleFactor), 0, math.floor(420 * scaleFactor))
    exportBtn2.BackgroundColor3 = SETTINGS.Secondary
    exportBtn2.Text = "SHOW DECODE LINK"
    exportBtn2.TextColor3 = SETTINGS.Text
    exportBtn2.TextSize = smallFont
    exportBtn2.Font = Enum.Font.GothamBold
    exportBtn2.BorderSizePixel = 0
    exportBtn2.Visible = false
    exportBtn2.Name = "ExportBtn2"
    exportBtn2.Parent = mainFrame

    local exportCorner2 = Instance.new("UICorner")
    exportCorner2.CornerRadius = UDim.new(0, math.floor(14 * scaleFactor))
    exportCorner2.Parent = exportBtn2

    -- Method hint
    local methodHint = Instance.new("TextLabel")
    methodHint.Size = UDim2.new(1, -math.floor(30 * scaleFactor), 0, math.floor(30 * scaleFactor))
    methodHint.Position = UDim2.new(0, math.floor(15 * scaleFactor), 0, math.floor(460 * scaleFactor))
    methodHint.BackgroundTransparency = 1
    methodHint.Text = "Export: base64 → pastebin → decode → .rblxm"
    methodHint.TextColor3 = Color3.fromRGB(130, 130, 140)
    methodHint.TextSize = math.floor(8 * scaleFactor)
    methodHint.Font = Enum.Font.Gotham
    methodHint.Parent = mainFrame

    -- Credit
    local creditText = Instance.new("TextLabel")
    creditText.Size = UDim2.new(1, -20, 0, math.floor(18 * scaleFactor))
    creditText.Position = UDim2.new(0, 10, 0, h - math.floor(22 * scaleFactor))
    creditText.BackgroundTransparency = 1
    creditText.Text = "Lemming v2 | Clip Export"
    creditText.TextColor3 = Color3.fromRGB(100, 100, 110)
    creditText.TextSize = math.floor(8 * scaleFactor)
    creditText.Font = Enum.Font.Gotham
    creditText.Parent = mainFrame

    return {
        Main = mainFrame,
        StartBtn = startButton,
        Status = statusText,
        Info = infoText,
        ExportBtn1 = exportBtn1,
        ExportBtn2 = exportBtn2,
        ProgFrame = progFrame,
        ProgFill = progFill,
        Pulse = pulseFrame,
    }
end

local ui = createMobileCircleUI()

local isRunning = false
local currentB64Data = ""
local currentFileName = ""

-- Non-blocking copy process using Heartbeat scheduling
local function startCopyProcess()
    if isRunning then return end
    isRunning = true
    ui.Status.Text = "SCANNING..."
    ui.StartBtn.Text = "..."
    ui.StartBtn.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    ui.ProgFrame.Visible = true
    ui.ExportBtn1.Visible = false
    ui.ExportBtn2.Visible = false
    copiedData.Instances = {}
    copiedData.Scripts = {}
    copiedData.Metadata = {
        PlaceId = game.PlaceId,
        PlaceName = pcall(function() return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name end) and game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or "Unknown",
        Timestamp = os.time(),
        Creator = Players.LocalPlayer.Name,
        GameVersion = game.PlaceVersion,
    }

    local startTick = tick()
    local totalPhases = 3
    local currentPhase = 0

    -- Schedule work across multiple heartbeats
    local workQueue = {}

    -- Phase 1: Collect all workspace objects (non-recursive first pass)
    table.insert(workQueue, function()
        currentPhase = 1
        ui.Status.Text = "PHASE 1/3: Collecting objects..."
        local objs = {}
        pcall(function()
            for _, obj in pairs(workspace:GetDescendants()) do
                if obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("Folder") or obj:IsA("UnionOperation") or obj:IsA("MeshPart") or obj:IsA("Part") or obj:IsA("WedgePart") or obj:IsA("CornerWedgePart") then
                    table.insert(objs, obj)
                end
            end
        end)
        return objs
    end)

    -- Phase 2: Recursive copy (batched)
    table.insert(workQueue, function(objs)
        currentPhase = 2
        local total = #objs
        ui.Status.Text = "PHASE 2/3: Copying " .. total .. " objects..."
        local count = 0
        for i, obj in ipairs(objs) do
            pcall(function()
                local data = recursiveCopy(obj, 0)
                if data then
                    table.insert(copiedData.Instances, data)
                end
            end)
            count = count + 1
            -- Yield every 10 objects
            if count % 10 == 0 then
                RunService.Heartbeat:Wait()
                pcall(function()
                    ui.ProgFill:TweenSize(UDim2.new(i/total, 0, 1, 0), "Out", "Quad", 0.05, true)
                end)
            end
        end
        return total
    end)

    -- Phase 3: Script extraction (service by service to avoid mass Descendants call)
    table.insert(workQueue, function()
        currentPhase = 3
        ui.Status.Text = "PHASE 3/3: Extracting scripts..."
        local services = {
            {workspace, "Workspace"},
            {Players, "Players"},
            {game:GetService("Lighting"), "Lighting"},
            {game:GetService("ReplicatedStorage"), "ReplicatedStorage"},
            {game:GetService("ServerScriptService"), "ServerScriptService"},
            {game:GetService("StarterPack"), "StarterPack"},
            {game:GetService("StarterGui"), "StarterGui"},
            {game:GetService("StarterPlayer"), "StarterPlayer"},
            {game:GetService("SoundService"), "SoundService"},
            {game:GetService("Chat"), "Chat"},
        }
        local scriptCount = 0
        for _, svcPair in ipairs(services) do
            local svc = svcPair[1]
            pcall(function()
                for _, obj in pairs(svc:GetDescendants()) do
                    if obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("Script") then
                        table.insert(copiedData.Scripts, {
                            Name = obj.Name,
                            ClassName = obj.ClassName,
                            Source = obj.Source,
                            Parent = obj.Parent and obj.Parent:GetFullName() or "Unknown",
                            Disabled = pcall(function() return obj.Disabled end) and obj.Disabled or false,
                        })
                        scriptCount = scriptCount + 1
                    end
                    if scriptCount % 25 == 0 then
                        RunService.Heartbeat:Wait()
                    end
                end
            end)
            ui.Status.Text = "PHASE 3/3: " .. svcPair[2] .. " (" .. scriptCount .. " scripts)"
            pcall(function()
                ui.ProgFill:TweenSize(UDim2.new((table.find(services, svcPair) or 1)/#services, 0, 1, 0), "Out", "Quad", 0.05, true)
            end)
        end
        return scriptCount
    end)

    -- Execute work queue step by step with Heartbeat yields between steps
    spawn(function()
        local phase1Result = nil
        local phase2Result = nil
        local phase3Result = nil

        for _, taskFn in ipairs(workQueue) do
            RunService.Heartbeat:Wait()
            local success, result = pcall(function()
                if phase1Result == nil and taskFn == workQueue[2] then
                    return taskFn(workQueue[1] and select(2, pcall(workQueue[1])) or {})
                elseif phase1Result ~= nil and taskFn == workQueue[3] then
                    return taskFn()
                else
                    return taskFn()
                end
            end)
            if not success then
                ui.Status.Text = "ERROR: " .. tostring(result):sub(1, 30)
                isRunning = false
                ui.StartBtn.Text = "RETRY"
                ui.StartBtn.BackgroundColor3 = Color3.fromRGB(255, 165, 0)
                return
            end
        end

        -- Re-execute properly
        local objs = {}
        pcall(function()
            for _, obj in pairs(workspace:GetDescendants()) do
                if obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("Folder") or obj:IsA("UnionOperation") or obj:IsA("MeshPart") or obj:IsA("Part") or obj:IsA("WedgePart") or obj:IsA("CornerWedgePart") then
                    table.insert(objs, obj)
                end
            end
        end)

        ui.Status.Text = "Copying " .. #objs .. " objects..."
        for i, obj in ipairs(objs) do
            pcall(function()
                local data = recursiveCopy(obj, 0)
                if data then
                    table.insert(copiedData.Instances, data)
                end
            end)
            if i % 15 == 0 then
                RunService.Heartbeat:Wait()
                pcall(function()
                    ui.ProgFill:TweenSize(UDim2.new(i/#objs, 0, 1, 0), "Out", "Quad", 0.05, true)
                end)
            end
        end

        -- Scripts
        ui.Status.Text = "Extracting scripts..."
        local services = {workspace, Players, game:GetService("Lighting"), game:GetService("ReplicatedStorage"), game:GetService("ServerScriptService"), game:GetService("StarterPack"), game:GetService("StarterGui"), game:GetService("StarterPlayer")}
        local scriptCount = 0
        for _, svc in ipairs(services) do
            pcall(function()
                for _, obj in pairs(svc:GetDescendants()) do
                    if obj:IsA("LuaSourceContainer") then
                        table.insert(copiedData.Scripts, {
                            Name = obj.Name,
                            ClassName = obj.ClassName,
                            Source = obj.Source,
                            Parent = obj.Parent and obj.Parent:GetFullName() or "Unknown",
                        })
                        scriptCount = scriptCount + 1
                    end
                    if scriptCount % 30 == 0 then
                        RunService.Heartbeat:Wait()
                    end
                end
            end)
        end

        -- Build JSON and base64
        ui.Status.Text = "Encoding..."
        RunService.Heartbeat:Wait()

        local fullData = {
            Version = "2.0",
            Metadata = copiedData.Metadata,
            Instances = copiedData.Instances,
            Scripts = copiedData.Scripts,
        }
        local json = HttpService:JSONEncode(fullData)
        local b64 = base64Encode(json)
        currentB64Data = b64
        currentFileName = "Lemming_" .. game.PlaceId .. "_" .. os.time()

        local elapsed = math.floor((tick() - startTick) * 100) / 100
        local sizeKB = math.floor(#b64 / 1024)

        ui.Status.Text = "DONE: " .. sizeKB .. "KB | " .. elapsed .. "s"
        ui.StartBtn.Text = "START\nCOPY"
        ui.StartBtn.BackgroundColor3 = SETTINGS.Accent
        ui.ExportBtn1.Visible = true
        ui.ExportBtn2.Visible = true
        ui.Info.Text = "Objects: " .. #copiedData.Instances .. "\nScripts: " .. #copiedData.Scripts .. "\nSize: " .. sizeKB .. "KB base64\nFile: " .. currentFileName .. ".rblxm"
        isRunning = false
    end)
end

local function exportToClipboard()
    if not currentB64Data or #currentB64Data == 0 then
        ui.Status.Text = "NO DATA - Run copy first"
        return
    end
    ui.Status.Text = "Copying to clipboard..."
    -- For files >1.5MB, split into chunks with reassembly instructions
    if #currentB64Data > 1500000 then
        local chunkSize = 1400000
        local totalChunks = math.ceil(#currentB64Data / chunkSize)
        for i = 1, totalChunks do
            local chunk = string.sub(currentB64Data, (i-1)*chunkSize + 1, math.min(i*chunkSize, #currentB64Data))
            local payload = "LEMMING_PART_" .. i .. "_OF_" .. totalChunks .. "_" .. currentFileName .. "|" .. chunk
            setclipboard(payload)
            ui.Status.Text = "Part " .. i .. "/" .. totalChunks .. " copied"
            wait(1.5)
        end
        ui.Status.Text = "ALL " .. totalChunks .. " parts copied sequentially"
        setclipboard("LEMMING_DONE: " .. currentFileName .. " | Parts: " .. totalChunks .. " | Use LemmingDecoder.html to reassemble")
    else
        setclipboard(currentB64Data)
        ui.Status.Text = "Copied! " .. math.floor(#currentB64Data/1024) .. "KB"
    end
end

local function showDecodeInstructions()
    local instructions = [[
DECODE INSTRUCTIONS:
1. Copy clipboard content
2. Go to: https://www.base64decode.org
3. Paste and decode (output: .rblxm JSON)
4. Save decoded text as .rblxm file
5. Open in Roblox Studio: File → Open

ALTERNATIVE:
- Use LemmingDecoder.html (local HTML file)
- Paste base64, click decode, download .rblxm

For multi-part: concatenate all parts
in order, then decode.]]
    setclipboard(instructions)
    ui.Status.Text = "Instructions copied to clipboard"
end

ui.StartBtn.MouseButton1Click:Connect(startCopyProcess)
ui.StartBtn.TouchTap:Connect(startCopyProcess)
ui.ExportBtn1.MouseButton1Click:Connect(exportToClipboard)
ui.ExportBtn1.TouchTap:Connect(exportToClipboard)
ui.ExportBtn2.MouseButton1Click:Connect(showDecodeInstructions)
ui.ExportBtn2.TouchTap:Connect(showDecodeInstructions)

-- Cleanup
game:GetService("CoreGui").ChildRemoved:Connect(function(child)
    if child.Name == "LemmingUI" then
        isRunning = false
    end
end)
