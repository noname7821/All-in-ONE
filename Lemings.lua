-- Lemming: Game File Ripper for Delta Executor Mobile
-- Copies current game's assets/scripts into a .rblxm studio file
-- Modern Circle UI. Touch-optimized. No Bloxy dependency.

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

local SETTINGS = {
    WindowName = "Lemming",
    Accent = Color3.fromRGB(0, 255, 140),
    Background = Color3.fromRGB(25, 25, 30),
    Secondary = Color3.fromRGB(35, 35, 40),
    Text = Color3.fromRGB(220, 220, 220),
    GrabScripts = true,
    GrabInstances = true,
    GrabTextures = true,
    CompressOutput = true,
}

local copiedData = {
    Instances = {},
    Scripts = {},
    Textures = {},
    Metadata = {}
}

-- Recursive copy function
local function recursiveCopy(instance, depth)
    depth = depth or 0
    if depth > 300 then return nil end
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
                data.Properties[prop] = val
            end
        end)
    end
    if instance:IsA("BasePart") or instance:IsA("UnionOperation") then
        data.Properties["CFrame"] = {instance.CFrame:GetComponents()}
    end
    for _, child in pairs(instance:GetChildren()) do
        if SETTINGS.GrabScripts and child:IsA("LuaSourceContainer") then
            table.insert(copiedData.Scripts, {
                Name = child.Name,
                Source = child.Source,
                Parent = instance:GetFullName()
            })
        elseif SETTINGS.GrabTextures and (child:IsA("Texture") or child:IsA("Decal")) then
            pcall(function()
                local id = child.Texture
                if id and string.find(id, "rbxassetid://") then
                    table.insert(copiedData.Textures, {
                        Parent = instance:GetFullName(),
                        AssetId = id
                    })
                end
            end)
        end
        if SETTINGS.GrabInstances then
            local childData = recursiveCopy(child, depth + 1)
            if childData then
                table.insert(data.Children, childData)
            end
        end
    end
    return data
end

local function generateRBLXM()
    local fullData = {
        Version = "1.0",
        Metadata = copiedData.Metadata,
        Instances = copiedData.Instances,
        Scripts = copiedData.Scripts,
        Textures = copiedData.Textures
    }
    local json = HttpService:JSONEncode(fullData)
    if SETTINGS.CompressOutput then
        json = json:gsub("%s+", "")
    end
    local fileName = "Lemming_" .. game.PlaceId .. "_" .. os.time() .. ".rblxm"
    writefile(fileName, json)
    return fileName, #json
end

-- Mobile-optimized Circle UI
local function createMobileCircleUI()
    local screen = Instance.new("ScreenGui")
    screen.Name = "LemmingUI"
    screen.Parent = CoreGui
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.IgnoreGuiInset = true

    -- Scaled dimensions
    local w = math.floor(340 * scaleFactor)
    local h = math.floor(520 * scaleFactor)
    local circleSize = math.floor(130 * scaleFactor)
    local fontSize = math.floor(16 * scaleFactor)
    local smallFont = math.floor(11 * scaleFactor)
    local tinyFont = math.floor(9 * scaleFactor)

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
    titleText.Text = "LEMMING"
    titleText.TextColor3 = SETTINGS.Accent
    titleText.TextSize = math.floor(22 * scaleFactor)
    titleText.Font = Enum.Font.GothamBold
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = titleBar

    -- Touch drag handler
    local dragToggle = Instance.new("TextButton")
    dragToggle.Size = UDim2.new(1, 0, 1, 0)
    dragToggle.BackgroundTransparency = 1
    dragToggle.Text = ""
    dragToggle.Parent = titleBar

    local dragging, dragInput, dragStart, startPos
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
    circleContainer.Size = UDim2.new(1, 0, 0, math.floor(190 * scaleFactor))
    circleContainer.Position = UDim2.new(0, 0, 0, math.floor(65 * scaleFactor))
    circleContainer.BackgroundTransparency = 1
    circleContainer.Parent = mainFrame

    -- Main circle button (START COPY)
    local startButton = Instance.new("TextButton")
    startButton.Size = UDim2.new(0, circleSize, 0, circleSize)
    startButton.Position = UDim2.new(0.5, -circleSize/2, 0, math.floor(10 * scaleFactor))
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

    -- Pulse animation
    local pulseFrame = Instance.new("Frame")
    pulseFrame.Size = UDim2.new(0, circleSize + math.floor(20 * scaleFactor), 0, circleSize + math.floor(20 * scaleFactor))
    pulseFrame.Position = UDim2.new(0.5, -(circleSize + math.floor(20 * scaleFactor))/2, 0, 0)
    pulseFrame.BackgroundColor3 = SETTINGS.Accent
    pulseFrame.BackgroundTransparency = 0.6
    pulseFrame.BorderSizePixel = 0
    pulseFrame.ZIndex = 0
    pulseFrame.Parent = circleContainer

    local pulseCorner = Instance.new("UICorner")
    pulseCorner.CornerRadius = UDim.new(1, 0)
    pulseCorner.Parent = pulseFrame

    spawn(function()
        local baseSize = circleSize + math.floor(20 * scaleFactor)
        local expandSize = baseSize + math.floor(25 * scaleFactor)
        while pulseFrame and pulseFrame.Parent do
            pulseFrame:TweenSize(UDim2.new(0, expandSize, 0, expandSize), "Out", "Sine", 1.2, true)
            pulseFrame.Position = UDim2.new(0.5, -expandSize/2, 0, -math.floor(12 * scaleFactor))
            wait(1.2)
            pulseFrame:TweenSize(UDim2.new(0, baseSize, 0, baseSize), "Out", "Sine", 1.2, true)
            pulseFrame.Position = UDim2.new(0.5, -baseSize/2, 0, 0)
            wait(1.2)
        end
    end)

    -- Status Text
    local statusText = Instance.new("TextLabel")
    statusText.Size = UDim2.new(1, -20, 0, math.floor(25 * scaleFactor))
    statusText.Position = UDim2.new(0, 10, 0, circleSize + math.floor(22 * scaleFactor))
    statusText.BackgroundTransparency = 1
    statusText.Text = "READY"
    statusText.TextColor3 = SETTINGS.Text
    statusText.TextSize = smallFont
    statusText.Font = Enum.Font.Gotham
    statusText.Parent = circleContainer

    -- Progress bar
    local progFrame = Instance.new("Frame")
    progFrame.Size = UDim2.new(1, -math.floor(30 * scaleFactor), 0, math.floor(5 * scaleFactor))
    progFrame.Position = UDim2.new(0, math.floor(15 * scaleFactor), 0, circleSize + math.floor(50 * scaleFactor))
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

    -- Info display
    local infoFrame = Instance.new("Frame")
    infoFrame.Size = UDim2.new(1, -math.floor(20 * scaleFactor), 0, math.floor(110 * scaleFactor))
    infoFrame.Position = UDim2.new(0, math.floor(10 * scaleFactor), 0, math.floor(270 * scaleFactor))
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

    -- Export Button
    local copyButton = Instance.new("TextButton")
    copyButton.Size = UDim2.new(1, -math.floor(30 * scaleFactor), 0, math.floor(44 * scaleFactor))
    copyButton.Position = UDim2.new(0, math.floor(15 * scaleFactor), 0, math.floor(395 * scaleFactor))
    copyButton.BackgroundColor3 = SETTINGS.Secondary
    copyButton.Text = "EXPORT .RBLXM"
    copyButton.TextColor3 = SETTINGS.Text
    copyButton.TextSize = smallFont
    copyButton.Font = Enum.Font.GothamBold
    copyButton.BorderSizePixel = 0
    copyButton.Visible = false
    copyButton.Name = "ExportBtn"
    copyButton.Parent = mainFrame

    local exportCorner = Instance.new("UICorner")
    exportCorner.CornerRadius = UDim.new(0, math.floor(14 * scaleFactor))
    exportCorner.Parent = copyButton

    -- Bottom credit
    local creditText = Instance.new("TextLabel")
    creditText.Size = UDim2.new(1, -20, 0, math.floor(18 * scaleFactor))
    creditText.Position = UDim2.new(0, 10, 0, h - math.floor(25 * scaleFactor))
    creditText.BackgroundTransparency = 1
    creditText.Text = "Lemming v1.0 | Delta Mobile"
    creditText.TextColor3 = Color3.fromRGB(100, 100, 110)
    creditText.TextSize = math.floor(8 * scaleFactor)
    creditText.Font = Enum.Font.Gotham
    creditText.Parent = mainFrame

    -- Minimize button for mobile
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Size = UDim2.new(0, math.floor(30 * scaleFactor), 0, math.floor(30 * scaleFactor))
    minimizeBtn.Position = UDim2.new(1, -math.floor(35 * scaleFactor), 0, math.floor(10 * scaleFactor))
    minimizeBtn.BackgroundColor3 = SETTINGS.Secondary
    minimizeBtn.Text = "-"
    minimizeBtn.TextColor3 = SETTINGS.Text
    minimizeBtn.TextSize = math.floor(20 * scaleFactor)
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.BorderSizePixel = 0
    minimizeBtn.Parent = titleBar

    local minCorner = Instance.new("UICorner")
    minCorner.CornerRadius = UDim.new(1, 0)
    minCorner.Parent = minimizeBtn

    local isMinimized = false
    local minimizedSize = UDim2.new(0, math.floor(50 * scaleFactor), 0, math.floor(50 * scaleFactor))
    local normalSize = UDim2.new(0, w, 0, h)
    local minimizedPos = UDim2.new(1, -math.floor(60 * scaleFactor), 0, math.floor(30 * scaleFactor))

    minimizeBtn.MouseButton1Click:Connect(function()
        isMinimized = not isMinimized
        if isMinimized then
            mainFrame:TweenSize(minimizedSize, "Out", "Quad", 0.3, true)
            mainFrame:TweenPosition(minimizedPos, "Out", "Quad", 0.3, true)
            circleContainer.Visible = false
            infoFrame.Visible = false
            copyButton.Visible = false
            creditText.Visible = false
            minimizeBtn.Text = "+"
            titleText.Text = "L"
        else
            mainFrame:TweenSize(normalSize, "Out", "Quad", 0.3, true)
            mainFrame:TweenPosition(UDim2.new(0.5, -w/2, 0.5, -h/2), "Out", "Quad", 0.3, true)
            circleContainer.Visible = true
            infoFrame.Visible = true
            copyButton.Visible = (copiedData.Instances and #copiedData.Instances > 0)
            creditText.Visible = true
            minimizeBtn.Text = "-"
            titleText.Text = "LEMMING"
        end
    end)

    return {
        Main = mainFrame,
        StartBtn = startButton,
        Status = statusText,
        Info = infoText,
        ExportBtn = copyButton,
        ProgFrame = progFrame,
        ProgFill = progFill,
        Pulse = pulseFrame,
        MinimizeBtn = minimizeBtn,
    }
end

local ui = createMobileCircleUI()

-- Main Logic
local isRunning = false
local elapsed = 0
local startTick = 0

local function startCopy()
    if isRunning then return end
    isRunning = true
    ui.Status.Text = "SCANNING..."
    ui.StartBtn.Text = "..."
    ui.StartBtn.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    ui.ProgFrame.Visible = true
    ui.ExportBtn.Visible = false

    copiedData.Instances = {}
    copiedData.Scripts = {}
    copiedData.Textures = {}
    copiedData.Metadata = {
        PlaceId = game.PlaceId,
        PlaceName = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name,
        Timestamp = os.time(),
        Creator = Players.LocalPlayer.Name,
        GameVersion = game.PlaceVersion,
    }
    startTick = tick()

    spawn(function()
        -- Phase 1: Workspace objects
        local workspaceObjs = {}
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("Folder") or obj:IsA("UnionOperation") or obj:IsA("MeshPart") then
                table.insert(workspaceObjs, obj)
            end
        end
        local total = math.max(#workspaceObjs, 1)
        for i, obj in pairs(workspaceObjs) do
            local data = recursiveCopy(obj, 0)
            if data then
                table.insert(copiedData.Instances, data)
            end
            pcall(function()
                ui.ProgFill:TweenSize(UDim2.new(i/total, 0, 1, 0), "Out", "Quad", 0.1, true)
            end)
            RunService.Heartbeat:Wait()
        end

        -- Phase 2: Scripts
        ui.Status.Text = "GRABBING SCRIPTS..."
        local allDescendants = {}
        local services = {
            workspace, Players, game:GetService("Lighting"),
            game:GetService("ReplicatedStorage"), game:GetService("ServerScriptService"),
            game:GetService("StarterPack"), game:GetService("StarterGui"),
            game:GetService("StarterPlayer"), game:GetService("SoundService"),
            game:GetService("Chat")
        }
        for _, svc in pairs(services) do
            pcall(function()
                for _, obj in pairs(svc:GetDescendants()) do
                    table.insert(allDescendants, obj)
                end
            end)
        end
        for _, obj in pairs(allDescendants) do
            pcall(function()
                if obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("Script") then
                    table.insert(copiedData.Scripts, {
                        Name = obj.Name,
                        ClassName = obj.ClassName,
                        Source = obj.Source,
                        Parent = obj.Parent and obj.Parent:GetFullName() or "Unknown",
                        Disabled = obj.Disabled,
                    })
                end
            end)
            RunService.Heartbeat:Wait()
        end

        -- Phase 3: Generate
        ui.Status.Text = "COMPILING .RBLXM..."
        wait(0.5)
        local fileName, fileSize = generateRBLXM()
        elapsed = math.floor((tick() - startTick) * 100) / 100

        ui.Status.Text = "DONE! " .. tostring(fileSize) .. "B"
        ui.StartBtn.Text = "START\nCOPY"
        ui.StartBtn.BackgroundColor3 = SETTINGS.Accent
        ui.ExportBtn.Visible = true
        ui.Info.Text = "File: " .. fileName .. "\nSize: " .. tostring(fileSize) .. " bytes\nTime: " .. tostring(elapsed) .. "s\nPlace: " .. game.PlaceId
        isRunning = false
    end)
end

ui.StartBtn.MouseButton1Click:Connect(startCopy)
ui.StartBtn.TouchTap:Connect(startCopy)

local function exportFile()
    if isRunning then return end
    local fileName = "Lemming_" .. game.PlaceId .. "_" .. os.time() .. ".rblxm"
    local json = HttpService:JSONEncode(copiedData)
    if SETTINGS.CompressOutput then
        json = json:gsub("%s+", "")
    end
    writefile(fileName, json)
    ui.Status.Text = "EXPORTED: " .. fileName
    wait(2.5)
    ui.Status.Text = "READY"
end

ui.ExportBtn.MouseButton1Click:Connect(exportFile)
ui.ExportBtn.TouchTap:Connect(exportFile)

-- Prevent screen timeout during long operations
local lastInteraction = tick()
UserInputService.TouchStarted:Connect(function()
    lastInteraction = tick()
end)

spawn(function()
    while true do
        if isRunning and (tick() - lastInteraction > 25) then
            pcall(function()
                game:GetService("GuiService"):ClearError()
            end)
            lastInteraction = tick()
        end
        wait(20)
    end
end)
