-- Lemming v3: All parts copied at once via single concatenated clipboard string
-- Uses a delimiter system. Decoder splits automatically.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local screenSize = workspace.CurrentCamera.ViewportSize
local scaleFactor = math.min(screenSize.X / 400, screenSize.Y / 700)

if syn and syn.protect_gui then
    syn.protect_gui(CoreGui)
end

-- Base64 encoder
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

local SETTINGS = {
    Accent = Color3.fromRGB(0, 255, 140),
    Background = Color3.fromRGB(25, 25, 30),
    Secondary = Color3.fromRGB(35, 35, 40),
    Text = Color3.fromRGB(220, 220, 220),
    BatchSize = 15,
    BatchDelay = 0.03,
}

local copiedData = {
    Instances = {},
    Scripts = {},
    Metadata = {}
}

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
    for _, child in pairs(instance:GetChildren()) do
        local childData = recursiveCopy(child, depth + 1)
        if childData then
            table.insert(data.Children, childData)
        end
    end
    return data
end

-- UI
local function createMobileCircleUI()
    local screen = Instance.new("ScreenGui")
    screen.Name = "LemmingUI"
    screen.Parent = CoreGui
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.IgnoreGuiInset = true

    local w = math.floor(340 * scaleFactor)
    local h = math.floor(500 * scaleFactor)
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
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, math.floor(22 * scaleFactor))

    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, math.floor(50 * scaleFactor))
    titleBar.BackgroundColor3 = SETTINGS.Secondary
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame
    local tc = Instance.new("UICorner", titleBar)
    tc.CornerRadius = UDim.new(0, math.floor(22 * scaleFactor))
    local tp = Instance.new("Frame", titleBar)
    tp.Size = UDim2.new(1, 0, 0.5, 0)
    tp.Position = UDim2.new(0, 0, 0.5, 0)
    tp.BackgroundColor3 = SETTINGS.Secondary
    tp.BorderSizePixel = 0

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -20, 1, 0)
    titleText.Position = UDim2.new(0, 10, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = "LEMMING v3"
    titleText.TextColor3 = SETTINGS.Accent
    titleText.TextSize = math.floor(20 * scaleFactor)
    titleText.Font = Enum.Font.GothamBold
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = titleBar

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

    -- Circle container
    local circleContainer = Instance.new("Frame")
    circleContainer.Size = UDim2.new(1, 0, 0, math.floor(200 * scaleFactor))
    circleContainer.Position = UDim2.new(0, 0, 0, math.floor(60 * scaleFactor))
    circleContainer.BackgroundTransparency = 1
    circleContainer.Parent = mainFrame

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
    Instance.new("UICorner", startButton).CornerRadius = UDim.new(1, 0)

    local pulseBase = circleSize + math.floor(20 * scaleFactor)
    local pulseFrame = Instance.new("Frame")
    pulseFrame.Size = UDim2.new(0, pulseBase, 0, pulseBase)
    pulseFrame.Position = UDim2.new(0.5, -pulseBase/2, 0, -math.floor(8 * scaleFactor))
    pulseFrame.BackgroundColor3 = SETTINGS.Accent
    pulseFrame.BackgroundTransparency = 0.6
    pulseFrame.BorderSizePixel = 0
    pulseFrame.ZIndex = 0
    pulseFrame.Parent = circleContainer
    Instance.new("UICorner", pulseFrame).CornerRadius = UDim.new(1, 0)

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

    local statusText = Instance.new("TextLabel")
    statusText.Size = UDim2.new(1, -20, 0, math.floor(22 * scaleFactor))
    statusText.Position = UDim2.new(0, 10, 0, circleSize + math.floor(18 * scaleFactor))
    statusText.BackgroundTransparency = 1
    statusText.Text = "READY"
    statusText.TextColor3 = SETTINGS.Text
    statusText.TextSize = smallFont
    statusText.Font = Enum.Font.Gotham
    statusText.Parent = circleContainer

    local progFrame = Instance.new("Frame")
    progFrame.Size = UDim2.new(1, -math.floor(30 * scaleFactor), 0, math.floor(5 * scaleFactor))
    progFrame.Position = UDim2.new(0, math.floor(15 * scaleFactor), 0, circleSize + math.floor(46 * scaleFactor))
    progFrame.BackgroundColor3 = SETTINGS.Secondary
    progFrame.BorderSizePixel = 0
    progFrame.Visible = false
    progFrame.Parent = circleContainer
    Instance.new("UICorner", progFrame).CornerRadius = UDim.new(1, 0)

    local progFill = Instance.new("Frame")
    progFill.Size = UDim2.new(0, 0, 1, 0)
    progFill.BackgroundColor3 = SETTINGS.Accent
    progFill.BorderSizePixel = 0
    progFill.Name = "Fill"
    progFill.Parent = progFrame
    Instance.new("UICorner", progFill).CornerRadius = UDim.new(1, 0)

    local infoFrame = Instance.new("Frame")
    infoFrame.Size = UDim2.new(1, -math.floor(20 * scaleFactor), 0, math.floor(70 * scaleFactor))
    infoFrame.Position = UDim2.new(0, math.floor(10 * scaleFactor), 0, math.floor(270 * scaleFactor))
    infoFrame.BackgroundColor3 = SETTINGS.Secondary
    infoFrame.BackgroundTransparency = 0.3
    infoFrame.BorderSizePixel = 0
    infoFrame.Parent = mainFrame
    Instance.new("UICorner", infoFrame).CornerRadius = UDim.new(0, math.floor(12 * scaleFactor))

    local infoText = Instance.new("TextLabel")
    infoText.Size = UDim2.new(1, -math.floor(16 * scaleFactor), 1, -math.floor(8 * scaleFactor))
    infoText.Position = UDim2.new(0, math.floor(8 * scaleFactor), 0, math.floor(4 * scaleFactor))
    infoText.BackgroundTransparency = 1
    infoText.Text = "Place: " .. game.PlaceId
    infoText.TextColor3 = SETTINGS.Text
    infoText.TextSize = tinyFont
    infoText.Font = Enum.Font.Gotham
    infoText.TextXAlignment = Enum.TextXAlignment.Left
    infoText.TextYAlignment = Enum.TextYAlignment.Top
    infoText.TextWrapped = true
    infoText.Parent = infoFrame

    local exportBtn1 = Instance.new("TextButton")
    exportBtn1.Size = UDim2.new(1, -math.floor(30 * scaleFactor), 0, math.floor(40 * scaleFactor))
    exportBtn1.Position = UDim2.new(0, math.floor(15 * scaleFactor), 0, math.floor(350 * scaleFactor))
    exportBtn1.BackgroundColor3 = SETTINGS.Accent
    exportBtn1.Text = "COPY ALL TO CLIPBOARD"
    exportBtn1.TextColor3 = Color3.fromRGB(15, 15, 20)
    exportBtn1.TextSize = smallFont
    exportBtn1.Font = Enum.Font.GothamBold
    exportBtn1.BorderSizePixel = 0
    exportBtn1.Visible = false
    exportBtn1.Name = "ExportBtn1"
    exportBtn1.Parent = mainFrame
    Instance.new("UICorner", exportBtn1).CornerRadius = UDim.new(0, math.floor(14 * scaleFactor))

    local exportBtn2 = Instance.new("TextButton")
    exportBtn2.Size = UDim2.new(1, -math.floor(30 * scaleFactor), 0, math.floor(40 * scaleFactor))
    exportBtn2.Position = UDim2.new(0, math.floor(15 * scaleFactor), 0, math.floor(398 * scaleFactor))
    exportBtn2.BackgroundColor3 = SETTINGS.Secondary
    exportBtn2.Text = "SHOW DECODER"
    exportBtn2.TextColor3 = SETTINGS.Text
    exportBtn2.TextSize = smallFont
    exportBtn2.Font = Enum.Font.GothamBold
    exportBtn2.BorderSizePixel = 0
    exportBtn2.Visible = false
    exportBtn2.Name = "ExportBtn2"
    exportBtn2.Parent = mainFrame
    Instance.new("UICorner", exportBtn2).CornerRadius = UDim.new(0, math.floor(14 * scaleFactor))

    local creditText = Instance.new("TextLabel")
    creditText.Size = UDim2.new(1, -20, 0, math.floor(18 * scaleFactor))
    creditText.Position = UDim2.new(0, 10, 0, h - math.floor(22 * scaleFactor))
    creditText.BackgroundTransparency = 1
    creditText.Text = "Lemming v3 | One-Click Copy"
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

-- ============================================================
-- FIX: Single clipboard set with ALL parts concatenated
-- Uses delimiter |||LEMMING_SPLIT||| between parts
-- Decoder splits on this delimiter and joins automatically
-- ============================================================
local function copyAllAtOnce(data, fileName)
    local maxClipSize = 900000 -- Safe limit for all devices (900KB)
    if #data <= maxClipSize then
        -- Small enough, copy directly
        setclipboard("LEMMING_SINGLE:" .. fileName .. "|" .. data)
        return 1
    end

    -- Split into chunks with unified delimiter
    local parts = {}
    local chunkSize = maxClipSize
    local totalLen = #data
    local totalParts = math.ceil(totalLen / chunkSize)

    for i = 1, totalParts do
        local startIdx = (i-1)*chunkSize + 1
        local endIdx = math.min(i*chunkSize, totalLen)
        local chunk = string.sub(data, startIdx, endIdx)
        table.insert(parts, "LEMMING_PART_" .. i .. "_OF_" .. totalParts .. "_" .. fileName)
        table.insert(parts, chunk)
    end

    -- Join ALL parts with delimiter
    local fullClipboard = table.concat(parts, "|||LEMMING_SPLIT|||")

    -- Single setclipboard call -> nothing gets overwritten
    setclipboard(fullClipboard)
    return totalParts
end

-- Copy process
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

    spawn(function()
        -- Phase 1: Collect workspace objects
        ui.Status.Text = "Collecting objects..."
        local objs = {}
        pcall(function()
            for _, obj in pairs(workspace:GetDescendants()) do
                if obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("Folder") or obj:IsA("UnionOperation") or obj:IsA("MeshPart") or obj:IsA("Part") or obj:IsA("WedgePart") or obj:IsA("CornerWedgePart") then
                    table.insert(objs, obj)
                end
            end
        end)

        -- Phase 2: Recursive copy batched
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

        -- Phase 3: Scripts service by service
        ui.Status.Text = "Extracting scripts..."
        local services = {
            workspace, Players,
            game:GetService("Lighting"),
            game:GetService("ReplicatedStorage"),
            game:GetService("ServerScriptService"),
            game:GetService("StarterPack"),
            game:GetService("StarterGui"),
            game:GetService("StarterPlayer"),
        }
        local scriptCount = 0
        for si, svc in ipairs(services) do
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
            pcall(function()
                ui.ProgFill:TweenSize(UDim2.new(si/#services, 0, 1, 0), "Out", "Quad", 0.05, true)
            end)
        end

        -- Phase 4: Build JSON and base64
        ui.Status.Text = "Encoding..."
        RunService.Heartbeat:Wait()

        local fullData = {
            Version = "3.0",
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
        ui.Info.Text = "Objects: " .. #copiedData.Instances .. "\nScripts: " .. #copiedData.Scripts .. "\nSize: " .. sizeKB .. "KB"
        isRunning = false
    end)
end

local function exportAllToClipboard()
    if not currentB64Data or #currentB64Data == 0 then
        ui.Status.Text = "NO DATA - Run copy first"
        return
    end
    ui.Status.Text = "Copying ALL to clipboard..."
    local numParts = copyAllAtOnce(currentB64Data, currentFileName)
    if numParts == 1 then
        ui.Status.Text = "COPIED! Single part. Paste in decoder."
    else
        ui.Status.Text = "COPIED! " .. numParts .. " parts in ONE string."
    end
end

local function showDecoderInstructions()
    local msg = [[
DECODER STEPS:
1. Open LemmingDecoderV3.html in browser
2. Paste clipboard (Ctrl+V / long-press → Paste)
3. Click DECODE & DOWNLOAD
4. .rblxm file downloads automatically

ALL parts are in ONE clipboard string.
No sequential copying needed.
]]
    setclipboard(msg)
    ui.Status.Text = "Instructions copied to clipboard"
end

ui.StartBtn.MouseButton1Click:Connect(startCopyProcess)
ui.StartBtn.TouchTap:Connect(startCopyProcess)
ui.ExportBtn1.MouseButton1Click:Connect(exportAllToClipboard)
ui.ExportBtn1.TouchTap:Connect(exportAllToClipboard)
ui.ExportBtn2.MouseButton1Click:Connect(showDecoderInstructions)
ui.ExportBtn2.TouchTap:Connect(showDecoderInstructions)

game:GetService("CoreGui").ChildRemoved:Connect(function(child)
    if child.Name == "LemmingUI" then
        isRunning = false
    end
end)
