-- Lemming v6: Generates .rbxl BINARY format
-- Native Roblox Studio format. File → Open directly.
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

-- ============================================================
-- RBXL BINARY WRITER (emulates Roblox binary chunk format)
-- ============================================================
local RBXL = {}

-- Roblox type IDs for binary format
local TYPE_STRING = 0x01
local TYPE_BOOL = 0x02
local TYPE_INT = 0x03
local TYPE_FLOAT = 0x04
local TYPE_DOUBLE = 0x05
local TYPE_UDIM = 0x06
local TYPE_UDIM2 = 0x07
local TYPE_RAY = 0x08
local TYPE_FACES = 0x09
local TYPE_AXES = 0x0A
local TYPE_BRICKCOLOR = 0x0B
local TYPE_COLOR3 = 0x0C
local TYPE_VECTOR2 = 0x0D
local TYPE_VECTOR3 = 0x0E
local TYPE_CFRAME = 0x10
local TYPE_ENUM = 0x12
local TYPE_REF = 0x13
local TYPE_VECTOR3INT16 = 0x14
local TYPE_NUMBERSEQUENCE = 0x15
local TYPE_COLORSEQUENCE = 0x16
local TYPE_NUMBERRANGE = 0x17
local TYPE_CONTENT = 0x18

local function writeByte(data, value)
    table.insert(data, string.char(value % 256))
end

local function writeInt32(data, value)
    -- LSB first
    for i = 1, 4 do
        table.insert(data, string.char(value % 256))
        value = math.floor(value / 256)
    end
end

local function writeFloat(data, value)
    -- IEEE 754 single precision, LSB first
    if value == 0 then
        for i = 1, 4 do table.insert(data, "\0") end
        return
    end
    local sign = value < 0 and 1 or 0
    value = math.abs(value)
    local exponent = math.floor(math.log(value) / math.log(2))
    if exponent < -126 then exponent = -126 end
    if exponent > 127 then exponent = 127 end
    local mantissa = value / (2^exponent) - 1
    local bits = sign * 0x80000000 + (exponent + 127) * 0x800000 + math.floor(mantissa * 0x800000)
    for i = 1, 4 do
        table.insert(data, string.char(bits % 256))
        bits = math.floor(bits / 256)
    end
end

local function writeDouble(data, value)
    -- Simplified: store as 8 bytes LSB
    if value == 0 then
        for i = 1, 8 do table.insert(data, "\0") end
        return
    end
    -- Use string.pack if available (Lua 5.3+), else manual
    local packed = string.pack("<d", value)
    for i = 1, #packed do
        table.insert(data, string.sub(packed, i, i))
    end
end

local function writeString(data, str)
    writeInt32(data, #str)
    for i = 1, #str do
        table.insert(data, string.sub(str, i, i))
    end
end

local function writeTypeAndValue(data, propName, value, valueType)
    -- Write property type byte
    writeByte(data, valueType)
    -- Write property name
    writeString(data, propName)
    
    if valueType == TYPE_STRING then
        writeString(data, tostring(value))
    elseif valueType == TYPE_BOOL then
        writeByte(data, value and 1 or 0)
    elseif valueType == TYPE_INT then
        writeInt32(data, math.floor(tonumber(value) or 0))
    elseif valueType == TYPE_FLOAT then
        writeFloat(data, tonumber(value) or 0)
    elseif valueType == TYPE_DOUBLE then
        writeDouble(data, tonumber(value) or 0)
    elseif valueType == TYPE_BRICKCOLOR then
        writeInt32(data, math.floor(tonumber(value) or 0))
    elseif valueType == TYPE_COLOR3 then
        if type(value) == "table" and #value >= 3 then
            writeFloat(data, value[1])
            writeFloat(data, value[2])
            writeFloat(data, value[3])
        else
            writeFloat(data, 0); writeFloat(data, 0); writeFloat(data, 0)
        end
    elseif valueType == TYPE_VECTOR3 then
        if type(value) == "table" and #value >= 3 then
            writeFloat(data, value[1])
            writeFloat(data, value[2])
            writeFloat(data, value[3])
        else
            writeFloat(data, 0); writeFloat(data, 0); writeFloat(data, 0)
        end
    elseif valueType == TYPE_CFRAME then
        if type(value) == "table" and #value >= 12 then
            for i = 1, 12 do
                writeFloat(data, value[i] or 0)
            end
        else
            -- Identity CFrame: pos 0,0,0 + identity rotation
            writeFloat(data, 0); writeFloat(data, 0); writeFloat(data, 0)
            writeFloat(data, 1); writeFloat(data, 0); writeFloat(data, 0)
            writeFloat(data, 0); writeFloat(data, 1); writeFloat(data, 0)
            writeFloat(data, 0); writeFloat(data, 0); writeFloat(data, 1)
        end
    elseif valueType == TYPE_REF then
        writeString(data, tostring(value))
    elseif valueType == TYPE_ENUM then
        writeInt32(data, math.floor(tonumber(value) or 0))
    elseif valueType == TYPE_CONTENT then
        writeString(data, tostring(value))
    else
        -- Fallback: write as string
        writeString(data, tostring(value))
    end
end

local function getTypeForProperty(propName, value)
    if propName == "Name" then return TYPE_STRING
    elseif propName == "Parent" then return TYPE_REF
    elseif propName == "Source" then return TYPE_STRING
    elseif propName == "Disabled" then return TYPE_BOOL
    elseif propName == "Anchored" then return TYPE_BOOL
    elseif propName == "CanCollide" then return TYPE_BOOL
    elseif propName == "Locked" then return TYPE_BOOL
    elseif propName == "Transparency" then return TYPE_FLOAT
    elseif propName == "Reflectance" then return TYPE_FLOAT
    elseif propName == "Material" then return TYPE_ENUM
    elseif propName == "BrickColor" then return TYPE_BRICKCOLOR
    elseif propName == "Color" then return TYPE_COLOR3
    elseif propName == "TextColor3" then return TYPE_COLOR3
    elseif propName == "BackgroundColor3" then return TYPE_COLOR3
    elseif propName == "Position" then return TYPE_VECTOR3
    elseif propName == "Size" then return TYPE_VECTOR3
    elseif propName == "CFrame" then return TYPE_CFRAME
    elseif propName == "Text" then return TYPE_STRING
    elseif propName == "Font" then return TYPE_ENUM
    elseif propName == "TextSize" then return TYPE_FLOAT
    elseif propName == "Image" then return TYPE_CONTENT
    elseif propName == "MeshId" then return TYPE_CONTENT
    elseif propName == "TextureId" then return TYPE_CONTENT
    elseif propName == "ImageRectSize" then return TYPE_VECTOR3
    elseif propName == "ImageRectOffset" then return TYPE_VECTOR3
    else
        if type(value) == "boolean" then return TYPE_BOOL
        elseif type(value) == "number" then return TYPE_FLOAT
        elseif type(value) == "string" then return TYPE_STRING
        else return TYPE_STRING
        end
    end
end

-- ============================================================
-- RBXL Chunk builder
-- ============================================================
local function buildRbxlBinary(data)
    local chunks = {}
    local referent = 0
    local function nextRef() referent = referent + 1; return referent end
    
    -- INST chunk: holds all instances
    local function buildInstance(item, parentId)
        local id = nextRef()
        local className = item.ClassName or "Part"
        local name = item.Name or "Part"
        
        -- INST chunk: [type_id:1][class_name:str][is_service:1][instance_count:4][referents...]
        local chunk = {}
        writeString(chunk, className) -- class name
        writeByte(chunk, 0) -- is_service = false
        writeInt32(chunk, 1) -- number of instances in this chunk
        writeInt32(chunk, id) -- referent
        
        -- Store properties for PROP chunk
        local props = {}
        table.insert(props, {name = "Name", value = name, typeId = TYPE_STRING})
        if parentId then
            table.insert(props, {name = "Parent", value = "RBX" .. tostring(parentId), typeId = TYPE_REF})
        end
        
        for pname, pval in pairs(item.Properties) do
            local t = getTypeForProperty(pname, pval)
            local v = pval
            -- Convert table types to raw values
            if t == TYPE_VECTOR3 and type(v) == "table" and #v >= 3 then
                v = v
            elseif t == TYPE_CFRAME and type(v) == "table" and #v >= 12 then
                v = v
            elseif t == TYPE_COLOR3 and type(v) == "table" and #v >= 3 then
                v = v
            elseif t == TYPE_BRICKCOLOR and type(v) == "number" then
                v = math.floor(v)
            end
            table.insert(props, {name = pname, value = v, typeId = t})
        end
        
        -- PRNT chunk: parent relationships
        if parentId then
            local prntChunk = {}
            writeByte(prntChunk, 0) -- version
            writeInt32(prntChunk, 1) -- count
            writeInt32(prntChunk, id) -- child
            writeInt32(prntChunk, parentId) -- parent
            table.insert(chunks, {type = "PRNT", data = table.concat(prntChunk)})
        end
        
        -- PROP chunk for this instance
        local propChunk = {}
        writeInt32(propChunk, id) -- referent
        writeInt32(propChunk, #props) -- property count
        for _, prop in ipairs(props) do
            writeTypeAndValue(propChunk, prop.name, prop.value, prop.typeId)
        end
        table.insert(chunks, {type = "PROP", data = table.concat(propChunk)})
        
        -- Instance data
        table.insert(chunks, {type = "INST", data = table.concat(chunk)})
        
        -- Recursively build children
        if item.Children then
            for _, child in ipairs(item.Children) do
                buildInstance(child, id)
            end
        end
        
        return id
    end
    
    -- Header signature
    local header = "<roblox!\x89\xFF\x0D\x0A\x1A\x0A"
    local result = {header}
    
    -- Build all instances
    local rootId = nextRef()
    
    -- Root folder INST
    local rootChunk = {}
    writeString(rootChunk, "Folder")
    writeByte(rootChunk, 0) -- not service
    writeInt32(rootChunk, 1)
    writeInt32(rootChunk, rootId)
    table.insert(chunks, {type = "INST", data = table.concat(rootChunk)})
    
    -- Root PROP
    local rootProp = {}
    writeInt32(rootProp, rootId)
    writeInt32(rootProp, 1)
    writeTypeAndValue(rootProp, "Name", "Lemming_Import", TYPE_STRING)
    table.insert(chunks, {type = "PROP", data = table.concat(rootProp)})
    
    -- Build all workspace instances
    for _, inst in ipairs(data.Instances) do
        buildInstance(inst, rootId)
    end
    
    -- Build scripts under root
    for _, scr in ipairs(data.Scripts) do
        local sid = nextRef()
        local sc = {}
        writeString(sc, scr.ClassName or "Script")
        writeByte(sc, 0)
        writeInt32(sc, 1)
        writeInt32(sc, sid)
        table.insert(chunks, {type = "INST", data = table.concat(sc)})
        
        -- Script properties
        local sp = {}
        writeInt32(sp, sid)
        local propCount = 2
        if scr.Disabled then propCount = 3 end
        writeInt32(sp, propCount)
        writeTypeAndValue(sp, "Name", scr.Name, TYPE_STRING)
        writeTypeAndValue(sp, "Parent", "RBX" .. tostring(rootId), TYPE_REF)
        if scr.Disabled then
            writeTypeAndValue(sp, "Disabled", true, TYPE_BOOL)
        end
        table.insert(chunks, {type = "PROP", data = table.concat(sp)})
        
        -- Script source in separate PROP (some parsers want it)
        local ssp = {}
        writeInt32(ssp, sid)
        writeInt32(ssp, 1)
        writeTypeAndValue(ssp, "Source", scr.Source or "", TYPE_STRING)
        table.insert(chunks, {type = "PROP", data = table.concat(ssp)})
        
        -- Parent
        local sprnt = {}
        writeByte(sprnt, 0)
        writeInt32(sprnt, 1)
        writeInt32(sprnt, sid)
        writeInt32(sprnt, rootId)
        table.insert(chunks, {type = "PRNT", data = table.concat(sprnt)})
    end
    
    -- END chunk
    table.insert(chunks, {type = "END", data = ""})
    
    -- Write all chunks with length prefix
    for _, chunk in ipairs(chunks) do
        local chunkData = chunk.type .. "\n" .. chunk.data
        table.insert(result, chunkData)
    end
    
    return table.concat(result)
end

-- ============================================================
-- Rest of script (base64, UI, copy logic) same as v5
-- ============================================================
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64Encode(data)
    local bytes = {}
    for i = 1, #data do bytes[i] = string.byte(data, i) end
    local result = {}
    for i = 1, #bytes, 3 do
        local b1, b2, b3 = bytes[i], bytes[i+1] or 0, bytes[i+2] or 0
        local n = b1 * 65536 + b2 * 256 + b3
        table.insert(result, string.sub(b64chars, math.floor(n/262144)+1, math.floor(n/262144)+1))
        table.insert(result, string.sub(b64chars, math.floor((n%262144)/4096)+1, math.floor((n%262144)/4096)+1))
        table.insert(result, i+1 <= #bytes and string.sub(b64chars, math.floor((n%4096)/64)+1, math.floor((n%4096)/64)+1) or "=")
        table.insert(result, i+2 <= #bytes and string.sub(b64chars, n%64+1, n%64+1) or "=")
    end
    return table.concat(result)
end

local SETTINGS = {
    Accent = Color3.fromRGB(0, 255, 140),
    Background = Color3.fromRGB(25, 25, 30),
    Secondary = Color3.fromRGB(35, 35, 40),
    Text = Color3.fromRGB(220, 220, 220),
}

local copiedData = {Instances = {}, Scripts = {}, Metadata = {}}

local function recursiveCopy(instance, depth)
    depth = depth or 0
    if depth > 200 or not instance or not instance.Parent then return nil end
    local data = {ClassName = instance.ClassName, Name = instance.Name, Properties = {}, Children = {}}
    local props = {"Position", "Size", "Color", "Material", "Transparency", "Reflectance", "Anchored", "CanCollide", "Locked", "BrickColor", "Text", "Font", "TextSize", "TextColor3", "BackgroundColor3", "Image", "ImageRectSize", "ImageRectOffset", "MeshId", "TextureId"}
    for _, p in pairs(props) do
        pcall(function()
            local v = instance[p]
            if v ~= nil then
                if typeof(v) == "CFrame" then data.Properties[p] = {v:GetComponents()}
                elseif typeof(v) == "Vector3" then data.Properties[p] = {v.X, v.Y, v.Z}
                elseif typeof(v) == "Color3" then data.Properties[p] = {v.R, v.G, v.B}
                elseif typeof(v) == "BrickColor" then data.Properties[p] = v.Number
                else data.Properties[p] = v end
            end
        end)
    end
    for _, child in pairs(instance:GetChildren()) do
        local d = recursiveCopy(child, depth+1)
        if d then table.insert(data.Children, d) end
    end
    return data
end

-- UI (identical to v5)
local function createUI()
    local screen = Instance.new("ScreenGui")
    screen.Name = "LemmingUI"
    screen.Parent = CoreGui
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.IgnoreGuiInset = true
    local w, h = math.floor(340*scaleFactor), math.floor(500*scaleFactor)
    local cs = math.floor(130*scaleFactor)
    local fs, sf, tf = math.floor(16*scaleFactor), math.floor(12*scaleFactor), math.floor(10*scaleFactor)
    local main = Instance.new("Frame", screen)
    main.Size = UDim2.new(0,w,0,h)
    main.Position = UDim2.new(0.5,-w/2,0.5,-h/2)
    main.BackgroundColor3 = SETTINGS.Background
    main.BackgroundTransparency = 0.1
    main.BorderSizePixel = 0
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, math.floor(22*scaleFactor))
    local tb = Instance.new("Frame", main)
    tb.Size = UDim2.new(1,0,0,math.floor(50*scaleFactor))
    tb.BackgroundColor3 = SETTINGS.Secondary
    tb.BorderSizePixel = 0
    local tc = Instance.new("UICorner", tb)
    tc.CornerRadius = UDim.new(0, math.floor(22*scaleFactor))
    Instance.new("Frame", tb).Size = UDim2.new(1,0,0.5,0)
    local tp2 = Instance.new("Frame", tb)
    tp2.Position = UDim2.new(0,0,0.5,0)
    tp2.Size = UDim2.new(1,0,0.5,0)
    tp2.BackgroundColor3 = SETTINGS.Secondary
    tp2.BorderSizePixel = 0
    local tt = Instance.new("TextLabel", tb)
    tt.Size = UDim2.new(1,-20,1,0)
    tt.Position = UDim2.new(0,10,0,0)
    tt.BackgroundTransparency = 1
    tt.Text = "LEMMING v6"
    tt.TextColor3 = SETTINGS.Accent
    tt.TextSize = math.floor(20*scaleFactor)
    tt.Font = Enum.Font.GothamBold
    tt.TextXAlignment = Enum.TextXAlignment.Left
    local drag = Instance.new("TextButton", tb)
    drag.Size = UDim2.new(1,0,1,0)
    drag.BackgroundTransparency = 1
    drag.Text = ""
    local dragging, ds, sp
    drag.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; ds = inp.Position; sp = main.Position
            inp.Changed:Connect(function() if inp.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end)
    drag.InputChanged:Connect(function(inp)
        if (inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseMovement) and dragging then
            local d = inp.Position - ds
            main.Position = UDim2.new(sp.X.Scale, sp.X.Offset+d.X, sp.Y.Scale, sp.Y.Offset+d.Y)
        end
    end)
    local cc = Instance.new("Frame", main)
    cc.Size = UDim2.new(1,0,0,math.floor(200*scaleFactor))
    cc.Position = UDim2.new(0,0,0,math.floor(60*scaleFactor))
    cc.BackgroundTransparency = 1
    local sb = Instance.new("TextButton", cc)
    sb.Size = UDim2.new(0,cs,0,cs)
    sb.Position = UDim2.new(0.5,-cs/2,0,math.floor(5*scaleFactor))
    sb.BackgroundColor3 = SETTINGS.Accent
    sb.Text = "START\nCOPY"
    sb.TextColor3 = Color3.fromRGB(15,15,20)
    sb.TextSize = fs
    sb.Font = Enum.Font.GothamBold
    sb.BorderSizePixel = 0
    Instance.new("UICorner", sb).CornerRadius = UDim.new(1,0)
    local pb = cs + math.floor(20*scaleFactor)
    local pf = Instance.new("Frame", cc)
    pf.Size = UDim2.new(0,pb,0,pb)
    pf.Position = UDim2.new(0.5,-pb/2,0,-math.floor(8*scaleFactor))
    pf.BackgroundColor3 = SETTINGS.Accent
    pf.BackgroundTransparency = 0.6
    pf.BorderSizePixel = 0
    pf.ZIndex = 0
    Instance.new("UICorner", pf).CornerRadius = UDim.new(1,0)
    spawn(function()
        local es = pb + math.floor(25*scaleFactor)
        while pf and pf.Parent do
            pf:TweenSize(UDim2.new(0,es,0,es),"Out","Sine",1.2,true)
            pf.Position = UDim2.new(0.5,-es/2,0,-math.floor(20*scaleFactor))
            wait(1.2)
            pf:TweenSize(UDim2.new(0,pb,0,pb),"Out","Sine",1.2,true)
            pf.Position = UDim2.new(0.5,-pb/2,0,-math.floor(8*scaleFactor))
            wait(1.2)
        end
    end)
    local st = Instance.new("TextLabel", cc)
    st.Size = UDim2.new(1,-20,0,math.floor(22*scaleFactor))
    st.Position = UDim2.new(0,10,0,cs+math.floor(18*scaleFactor))
    st.BackgroundTransparency = 1
    st.Text = "READY"
    st.TextColor3 = SETTINGS.Text
    st.TextSize = sf
    st.Font = Enum.Font.Gotham
    local pgr = Instance.new("Frame", cc)
    pgr.Size = UDim2.new(1,-math.floor(30*scaleFactor),0,math.floor(5*scaleFactor))
    pgr.Position = UDim2.new(0,math.floor(15*scaleFactor),0,cs+math.floor(46*scaleFactor))
    pgr.BackgroundColor3 = SETTINGS.Secondary
    pgr.BorderSizePixel = 0
    pgr.Visible = false
    Instance.new("UICorner", pgr).CornerRadius = UDim.new(1,0)
    local pgf = Instance.new("Frame", pgr)
    pgf.Size = UDim2.new(0,0,1,0)
    pgf.BackgroundColor3 = SETTINGS.Accent
    pgf.BorderSizePixel = 0
    pgf.Name = "Fill"
    Instance.new("UICorner", pgf).CornerRadius = UDim.new(1,0)
    local inf = Instance.new("Frame", main)
    inf.Size = UDim2.new(1,-math.floor(20*scaleFactor),0,math.floor(70*scaleFactor))
    inf.Position = UDim2.new(0,math.floor(10*scaleFactor),0,math.floor(270*scaleFactor))
    inf.BackgroundColor3 = SETTINGS.Secondary
    inf.BackgroundTransparency = 0.3
    inf.BorderSizePixel = 0
    Instance.new("UICorner", inf).CornerRadius = UDim.new(0,math.floor(12*scaleFactor))
    local it = Instance.new("TextLabel", inf)
    it.Size = UDim2.new(1,-math.floor(16*scaleFactor),1,-math.floor(8*scaleFactor))
    it.Position = UDim2.new(0,math.floor(8*scaleFactor),0,math.floor(4*scaleFactor))
    it.BackgroundTransparency = 1
    it.Text = "Place: "..game.PlaceId.."\nFormat: .rbxl BINARY"
    it.TextColor3 = SETTINGS.Text
    it.TextSize = tf
    it.Font = Enum.Font.Gotham
    it.TextXAlignment = Enum.TextXAlignment.Left
    it.TextYAlignment = Enum.TextYAlignment.Top
    it.TextWrapped = true
    local eb1 = Instance.new("TextButton", main)
    eb1.Size = UDim2.new(1,-math.floor(30*scaleFactor),0,math.floor(40*scaleFactor))
    eb1.Position = UDim2.new(0,math.floor(15*scaleFactor),0,math.floor(350*scaleFactor))
    eb1.BackgroundColor3 = SETTINGS.Accent
    eb1.Text = "COPY .RBXL TO CLIPBOARD"
    eb1.TextColor3 = Color3.fromRGB(15,15,20)
    eb1.TextSize = sf
    eb1.Font = Enum.Font.GothamBold
    eb1.BorderSizePixel = 0
    eb1.Visible = false
    eb1.Name = "ExportBtn1"
    Instance.new("UICorner", eb1).CornerRadius = UDim.new(0,math.floor(14*scaleFactor))
    local eb2 = Instance.new("TextButton", main)
    eb2.Size = UDim2.new(1,-math.floor(30*scaleFactor),0,math.floor(40*scaleFactor))
    eb2.Position = UDim2.new(0,math.floor(15*scaleFactor),0,math.floor(398*scaleFactor))
    eb2.BackgroundColor3 = SETTINGS.Secondary
    eb2.Text = "SHOW DECODER"
    eb2.TextColor3 = SETTINGS.Text
    eb2.TextSize = sf
    eb2.Font = Enum.Font.GothamBold
    eb2.BorderSizePixel = 0
    eb2.Visible = false
    eb2.Name = "ExportBtn2"
    Instance.new("UICorner", eb2).CornerRadius = UDim.new(0,math.floor(14*scaleFactor))
    local cr = Instance.new("TextLabel", main)
    cr.Size = UDim2.new(1,-20,0,math.floor(18*scaleFactor))
    cr.Position = UDim2.new(0,10,0,h-math.floor(22*scaleFactor))
    cr.BackgroundTransparency = 1
    cr.Text = "Lemming v6 | .rbxl Binary"
    cr.TextColor3 = Color3.fromRGB(100,100,110)
    cr.TextSize = math.floor(8*scaleFactor)
    cr.Font = Enum.Font.Gotham
    return {StartBtn=sb, Status=st, Info=it, ExportBtn1=eb1, ExportBtn2=eb2, ProgFrame=pgr, ProgFill=pgf}
end

local ui = createUI()
local isRunning = false
local currentBinaryData = ""
local currentFileName = ""

local function copyAllAtOnce(data, fileName)
    -- Binary data needs base64 encoding for clipboard
    local b64 = base64Encode(data)
    local maxClip = 900000
    if #b64 <= maxClip then
        setclipboard("LEMMING_SINGLE:" .. fileName .. "|" .. b64)
        return 1
    end
    local parts, totalParts = {}, math.ceil(#b64 / maxClip)
    for i = 1, totalParts do
        local s = (i-1)*maxClip + 1
        local e = math.min(i*maxClip, #b64)
        table.insert(parts, "LEMMING_PART_"..i.."_OF_"..totalParts.."_"..fileName)
        table.insert(parts, string.sub(b64, s, e))
    end
    setclipboard(table.concat(parts, "|||LEMMING_SPLIT|||"))
    return totalParts
end

local function startCopyProcess()
    if isRunning then return end
    isRunning = true
    ui.Status.Text = "SCANNING..."
    ui.StartBtn.Text = "..."
    ui.StartBtn.BackgroundColor3 = Color3.fromRGB(255,100,100)
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
    }
    local startTick = tick()
    spawn(function()
        ui.Status.Text = "Collecting objects..."
        local objs = {}
        pcall(function()
            for _, obj in pairs(workspace:GetDescendants()) do
                if obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("Folder") or obj:IsA("UnionOperation") or obj:IsA("MeshPart") or obj:IsA("Part") or obj:IsA("WedgePart") then
                    table.insert(objs, obj)
                end
            end
        end)
        ui.Status.Text = "Copying "..#objs.." objects..."
        for i, obj in ipairs(objs) do
            pcall(function()
                local d = recursiveCopy(obj, 0)
                if d then table.insert(copiedData.Instances, d) end
            end)
            if i % 15 == 0 then
                RunService.Heartbeat:Wait()
                pcall(function() ui.ProgFill:TweenSize(UDim2.new(i/#objs,0,1,0),"Out","Quad",0.05,true) end)
            end
        end
        ui.Status.Text = "Extracting scripts..."
        local services = {workspace, Players, game:GetService("Lighting"), game:GetService("ReplicatedStorage"), game:GetService("ServerScriptService"), game:GetService("StarterPack"), game:GetService("StarterGui"), game:GetService("StarterPlayer")}
        for si, svc in ipairs(services) do
            pcall(function()
                for _, obj in pairs(svc:GetDescendants()) do
                    if obj:IsA("LuaSourceContainer") then
                        table.insert(copiedData.Scripts, {
                            Name = obj.Name, ClassName = obj.ClassName,
                            Source = obj.Source,
                            Parent = obj.Parent and obj.Parent:GetFullName() or "Unknown",
                            Disabled = pcall(function() return obj.Disabled end) and obj.Disabled or false
                        })
                    end
                end
            end)
            pcall(function() ui.ProgFill:TweenSize(UDim2.new(si/#services,0,1,0),"Out","Quad",0.05,true) end)
            RunService.Heartbeat:Wait()
        end
        ui.Status.Text = "Building .rbxl BINARY..."
        RunService.Heartbeat:Wait()
        currentBinaryData = buildRbxlBinary(copiedData)
        currentFileName = "Lemming_"..game.PlaceId.."_"..os.time()
        local elapsed = math.floor((tick()-startTick)*100)/100
        local sizeKB = math.floor(#currentBinaryData/1024)
        ui.Status.Text = "DONE: "..sizeKB.."KB | "..elapsed.."s"
        ui.StartBtn.Text = "START\nCOPY"
        ui.StartBtn.BackgroundColor3 = SETTINGS.Accent
        ui.ExportBtn1.Visible = true
        ui.ExportBtn2.Visible = true
        ui.Info.Text = "Objects: "..#copiedData.Instances.."\nScripts: "..#copiedData.Scripts.."\nSize: "..sizeKB.."KB\nFormat: .rbxl BINARY"
        isRunning = false
    end)
end

local function exportToClipboard()
    if not currentBinaryData or #currentBinaryData == 0 then ui.Status.Text = "NO DATA"; return end
    ui.Status.Text = "Copying ALL to clipboard..."
    local n = copyAllAtOnce(currentBinaryData, currentFileName)
    ui.Status.Text = n == 1 and "COPIED! Single part." or "COPIED! "..n.." parts in ONE string."
end

local function showDecoder() setclipboard("Open LemmingDecoderV6.html. Paste. Decode. Download .rbxl. Open in Roblox Studio: FILE → OPEN."); ui.Status.Text = "Instructions copied" end

ui.StartBtn.MouseButton1Click:Connect(startCopyProcess)
ui.StartBtn.TouchTap:Connect(startCopyProcess)
ui.ExportBtn1.MouseButton1Click:Connect(exportToClipboard)
ui.ExportBtn1.TouchTap:Connect(exportToClipboard)
ui.ExportBtn2.MouseButton1Click:Connect(showDecoder)
ui.ExportBtn2.TouchTap:Connect(showDecoder)
game:GetService("CoreGui").ChildRemoved:Connect(function(c) if c.Name == "LemmingUI" then isRunning = false end end)
