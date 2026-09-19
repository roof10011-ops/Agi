--[[
    Rayfield-based Aimbot / ESP
    Mobile-first, touch-compatible, fully wired.
--]]

--============================================================
-- SERVICES
--============================================================
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local Workspace         = game:GetService("Workspace")
local TweenService      = game:GetService("TweenService")
local CoreGui           = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

--============================================================
-- CLEAN PRIOR RAYFIELD INSTANCE
--============================================================
pcall(function()
    if CoreGui:FindFirstChild("Rayfield") then
        CoreGui.Rayfield:Destroy()
    end
end)
pcall(function()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg and pg:FindFirstChild("Rayfield") then
        pg.Rayfield:Destroy()
    end
end)

--============================================================
-- RAYFIELD
--============================================================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "AGI",
    LoadingTitle = "loading...",
    LoadingSubtitle = "for pros",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "pro",
        FileName = "config"
    },
    KeySystem = false
})

--============================================================
-- STATE
--============================================================
local State = {
    -- Aim
    AimbotEnabled     = false,
    FOVSize           = 120,
    FOVColor          = Color3.fromRGB(255, 255, 255),
    AimMagnetism      = 0.35,
    AimRange          = 500,
    AimBodyPart       = "Head",
    WallCheck         = false,
    IgnoreTeammates   = true,
    IgnoreDead        = true,
    AimNearest        = false,
    StickyBreak       = 120,   -- total touch px to break lock
    BreakCooldown     = 0.40,  -- seconds locked out after break

    -- ESP
    ESPEnabled        = false,
    Chams             = false,
    ChamsFill         = Color3.fromRGB(255, 0, 0),
    ChamsOutline      = Color3.fromRGB(255, 255, 255),
    Skeleton          = false,
    SkeletonColor     = Color3.fromRGB(255, 255, 255),
    Box               = false,
    BoxColor          = Color3.fromRGB(255, 255, 255),
    TeamColor         = false,
}

--============================================================
-- DRAWING
--============================================================
local function newDrawing(class, props)
    local ok, d = pcall(Drawing.new, class)
    if not ok or not d then return nil end
    for k, v in pairs(props or {}) do
        pcall(function() d[k] = v end)
    end
    return d
end

local FOVCircle = newDrawing("Circle", {
    Thickness = 1.5,
    Filled = false,
    Color = State.FOVColor,
    Transparency = 0.4,
    Visible = false,
    ZIndex = 2
})

--============================================================
-- ESP CACHE
--============================================================
local ESPCache = {}

local function cleanupESP(player)
    local c = ESPCache[player]
    if not c then return end
    if c.highlight then pcall(function() c.highlight:Destroy() end) end
    if c.box then
        for _, d in pairs(c.box) do pcall(function() d:Remove() end) end
    end
    if c.skeleton then
        for _, d in pairs(c.skeleton) do pcall(function() d:Remove() end) end
    end
    ESPCache[player] = nil
end

--============================================================
-- TARGET HELPERS
--============================================================
local function isTeammate(plr)
    if not State.IgnoreTeammates then return false end
    if not plr.Team or not LocalPlayer.Team then return false end
    return plr.Team == LocalPlayer.Team
end

local function isAlive(plr)
    local char = plr.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    if hum.Health <= 0 then return false end
    return true
end

local function isValidTarget(plr)
    if plr == LocalPlayer then return false end
    if State.IgnoreTeammates and isTeammate(plr) then return false end
    if State.IgnoreDead and not isAlive(plr) then return false end
    if not plr.Character then return false end
    if not plr.Character.Parent then return false end
    return true
end

--============================================================
-- WALL CHECK
--============================================================
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.IgnoreWater = true

local function hasLineOfSight(plr)
    if not State.WallCheck then return true end
    local char = plr.Character
    if not char then return false end
    local part = char:FindFirstChild(State.AimBodyPart) or char:FindFirstChild("Head")
    if not part then return false end

    local origin = Camera.CFrame.Position
    local dir = (part.Position - origin)

    local exclude = {}
    if LocalPlayer.Character then table.insert(exclude, LocalPlayer.Character) end
    table.insert(exclude, char)
    wallParams.FilterDescendantsInstances = exclude

    local hit = Workspace:Raycast(origin, dir, wallParams)
    return hit == nil
end

--============================================================
-- SCREEN MATH
--============================================================
local function worldToScreen(pos)
    local sp, onScreen = Camera:WorldToViewportPoint(pos)
    if sp.Z <= 0 then return nil end
    return Vector2.new(sp.X, sp.Y), onScreen
end

local function getScreenCenter()
    local vp = Camera.ViewportSize
    return Vector2.new(vp.X / 2, vp.Y / 2)
end

--============================================================
-- BODY PART SELECTION
--============================================================
local BODYPART_FALLBACKS = {
    ["Head"]             = {"Head", "UpperTorso", "Torso", "HumanoidRootPart"},
    ["UpperTorso"]       = {"UpperTorso", "Torso", "HumanoidRootPart", "Head"},
    ["LowerTorso"]       = {"LowerTorso", "Torso", "HumanoidRootPart"},
    ["HumanoidRootPart"] = {"HumanoidRootPart", "UpperTorso", "Torso", "Head"},
    ["Torso"]            = {"Torso", "UpperTorso", "HumanoidRootPart", "Head"},
    ["LeftUpperArm"]     = {"LeftUpperArm", "Left Arm", "UpperTorso", "Torso", "HumanoidRootPart"},
    ["RightUpperArm"]    = {"RightUpperArm", "Right Arm", "UpperTorso", "Torso", "HumanoidRootPart"},
    ["LeftLowerArm"]     = {"LeftLowerArm", "Left Arm", "UpperTorso", "Torso", "HumanoidRootPart"},
    ["RightLowerArm"]    = {"RightLowerArm", "Right Arm", "UpperTorso", "Torso", "HumanoidRootPart"},
    ["LeftUpperLeg"]     = {"LeftUpperLeg", "Left Leg", "LowerTorso", "Torso", "HumanoidRootPart"},
    ["RightUpperLeg"]    = {"RightUpperLeg", "Right Leg", "LowerTorso", "Torso", "HumanoidRootPart"},
    ["LeftLowerLeg"]     = {"LeftLowerLeg", "Left Leg", "LowerTorso", "Torso", "HumanoidRootPart"},
    ["RightLowerLeg"]    = {"RightLowerLeg", "Right Leg", "LowerTorso", "Torso", "HumanoidRootPart"},
}

local function getTargetPoint(plr)
    local char = plr.Character
    if not char then return nil end
    local names = BODYPART_FALLBACKS[State.AimBodyPart] or {"Head", "HumanoidRootPart"}
    for _, name in ipairs(names) do
        local p = char:FindFirstChild(name)
        if p and p:IsA("BasePart") then
            return p.Position
        end
    end
    return nil
end

--============================================================
-- STICKY ESCAPE STATE
--============================================================
local currentAimTarget = nil
local swipeAccum      = 0
local swipeLastAt     = 0
local escapedUntil    = 0

-- rolling swipe accumulator
UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.Touch then return end
    -- ignore touches that belong to other gui (trigger button not present here, but safe)
    local d = input.Delta
    local mag = math.sqrt(d.X * d.X + d.Y * d.Y)
    local now = tick()
    if now - swipeLastAt > 0.12 then
        swipeAccum = mag
    else
        swipeAccum = swipeAccum + mag
    end
    swipeLastAt = now

    if swipeAccum >= State.StickyBreak and now >= escapedUntil then
        escapedUntil   = now + State.BreakCooldown
        swipeAccum     = 0
        currentAimTarget = nil
    end
end)

--============================================================
-- TARGET ACQUISITION
--============================================================
local function getBestTarget()
    local myPos = nil
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        myPos = LocalPlayer.Character.HumanoidRootPart.Position
    elseif Camera then
        myPos = Camera.CFrame.Position
    end
    if not myPos then return nil end

    local center = getScreenCenter()
    local fovR = State.FOVSize
    local best, bestScore = nil, math.huge

    for _, plr in ipairs(Players:GetPlayers()) do
        if isValidTarget(plr) then
            local worldPos = getTargetPoint(plr)
            if worldPos then
                local dist = (worldPos - myPos).Magnitude
                if dist <= State.AimRange then
                    local screen, onScreen = worldToScreen(worldPos)
                    if screen and onScreen then
                        local d2center = (screen - center).Magnitude
                        if d2center <= fovR then
                            if hasLineOfSight(plr) then
                                local score = State.AimNearest and dist or d2center
                                if score < bestScore then
                                    bestScore = score
                                    best = plr
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

--============================================================
-- AIMBOT LOOP (bound AFTER the game's camera script)
--============================================================
local AIM_BIND = "AGI_AimbotCamera"

local function aimUpdate(dt)
    if FOVCircle then
        local center = getScreenCenter()
        FOVCircle.Position = center
        FOVCircle.Radius = State.FOVSize
        FOVCircle.Color = State.FOVColor
        FOVCircle.Visible = State.AimbotEnabled
    end

    if not State.AimbotEnabled then
        currentAimTarget = nil
        return
    end

    -- sticky escape: he broke free with a hard swipe
    if tick() < escapedUntil then
        return
    end

    if currentAimTarget and not isValidTarget(currentAimTarget) then
        currentAimTarget = nil
    end
    if currentAimTarget and not hasLineOfSight(currentAimTarget) then
        currentAimTarget = nil
    end

    -- only re-acquire if we don't already hold a target (sticky)
    if not currentAimTarget then
        local target = getBestTarget()
        if target then currentAimTarget = target end
    end

    if currentAimTarget then
        local worldPos = getTargetPoint(currentAimTarget)
        if worldPos then
            local camPos = Camera.CFrame.Position
            local desired = CFrame.new(camPos, worldPos)
            local alpha = math.clamp(State.AimMagnetism, 0, 1)
            Camera.CFrame = Camera.CFrame:Lerp(desired, alpha)

            local char = LocalPlayer.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local flatLook = Vector3.new(worldPos.X - hrp.Position.X, 0, worldPos.Z - hrp.Position.Z)
                    if flatLook.Magnitude > 0.1 then
                        local targetCF = CFrame.lookAt(hrp.Position, hrp.Position + flatLook.Unit)
                        hrp.CFrame = hrp.CFrame:Lerp(
                            CFrame.new(hrp.Position) * (targetCF - targetCF.Position),
                            alpha
                        )
                    end
                end
            end
        end
    end
end

pcall(function() RunService:UnbindFromRenderStep(AIM_BIND) end)
RunService:BindToRenderStep(AIM_BIND, Enum.RenderPriority.Camera.Value + 1, aimUpdate)

--============================================================
-- ESP RENDERING
--============================================================
local SKELETON_R15 = {
    {"Head","UpperTorso"}, {"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"}, {"LeftUpperArm","LeftLowerArm"}, {"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"}, {"RightUpperArm","RightLowerArm"}, {"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"}, {"LeftUpperLeg","LeftLowerLeg"}, {"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"}, {"RightUpperLeg","RightLowerLeg"}, {"RightLowerLeg","RightFoot"},
}
local SKELETON_R6 = {
    {"Head","Torso"}, {"Torso","Left Arm"}, {"Torso","Right Arm"},
    {"Torso","Left Leg"}, {"Torso","Right Leg"},
}

local function getSkeletonPairs(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    local rig = "R15"
    if hum and hum.RigType == Enum.HumanoidRigType.R6 then rig = "R6" end
    return rig == "R6" and SKELETON_R6 or SKELETON_R15
end

local function newLine()
    return newDrawing("Line", {Thickness=1, Transparency=0.2, Color=State.SkeletonColor})
end

local function updatePlayerESP(plr)
    local char = plr.Character
    local valid = isValidTarget(plr) and char and char.Parent

    local cache = ESPCache[plr]
    if not valid then
        if cache then cleanupESP(plr) end
        return
    end

    if not cache then
        cache = { skeleton = {}, box = nil }
        ESPCache[plr] = cache
    end

    local boxColor      = State.TeamColor and plr.Team and plr.Team.TeamColor.Color or State.BoxColor
    local skelColor     = State.TeamColor and plr.Team and plr.Team.TeamColor.Color or State.SkeletonColor
    local chamsFill     = State.TeamColor and plr.Team and plr.Team.TeamColor.Color or State.ChamsFill
    local chamsOutline  = State.TeamColor and plr.Team and plr.Team.TeamColor.Color or State.ChamsOutline

    -- Chams
    if State.ESPEnabled and State.Chams then
        if not cache.highlight or not cache.highlight.Parent then
            local h = Instance.new("Highlight")
            h.Name = "AGIChams"
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Parent = char
            cache.highlight = h
        end
        cache.highlight.FillColor = chamsFill
        cache.highlight.OutlineColor = chamsOutline
        cache.highlight.FillTransparency = 0.5
        cache.highlight.OutlineTransparency = 0
        cache.highlight.Adornee = char
    else
        if cache.highlight then
            pcall(function() cache.highlight:Destroy() end)
            cache.highlight = nil
        end
    end

    -- Skeleton
    if State.ESPEnabled and State.Skeleton then
        local pairsList = getSkeletonPairs(char)
        for i, pair in ipairs(pairsList) do
            local a = char:FindFirstChild(pair[1])
            local b = char:FindFirstChild(pair[2])
            if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
                local sp1, on1 = worldToScreen(a.Position)
                local sp2, on2 = worldToScreen(b.Position)
                if sp1 and sp2 and on1 and on2 then
                    if not cache.skeleton[i] then
                        cache.skeleton[i] = newLine()
                    end
                    local line = cache.skeleton[i]
                    if line then
                        line.From = sp1
                        line.To = sp2
                        line.Color = skelColor
                        line.Visible = true
                    end
                else
                    if cache.skeleton[i] then cache.skeleton[i].Visible = false end
                end
            else
                if cache.skeleton[i] then cache.skeleton[i].Visible = false end
            end
        end
    else
        for i, line in pairs(cache.skeleton) do
            if line then pcall(function() line:Remove() end) end
            cache.skeleton[i] = nil
        end
    end

    -- Box
    if State.ESPEnabled and State.Box then
        local head = char:FindFirstChild("Head")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if head and hrp then
            local headPos = head.Position + Vector3.new(0, 0.5, 0)
            local feetPos = hrp.Position - Vector3.new(0, 3, 0)
            local tl, tOn = worldToScreen(headPos)
            local bl, bOn = worldToScreen(feetPos)
            if tl and bl and tOn and bOn then
                local height = math.abs(bl.Y - tl.Y)
                local width = height * 0.6
                local centerX = (tl.X + bl.X) / 2
                local topY = math.min(tl.Y, bl.Y)
                local bottomY = math.max(tl.Y, bl.Y)
                local leftX = centerX - width / 2
                local rightX = centerX + width / 2

                if not cache.box then
                    cache.box = {
                        top    = newDrawing("Line", {}),
                        bottom = newDrawing("Line", {}),
                        left   = newDrawing("Line", {}),
                        right  = newDrawing("Line", {}),
                    }
                end

                local box = cache.box
                local function setLine(l, a, b)
                    if l then
                        l.From = a
                        l.To = b
                        l.Color = boxColor
                        l.Thickness = 1.5
                        l.Transparency = 0.2
                        l.Visible = true
                    end
                end
                local tlV = Vector2.new(leftX, topY)
                local trV = Vector2.new(rightX, topY)
                local blV = Vector2.new(leftX, bottomY)
                local brV = Vector2.new(rightX, bottomY)
                setLine(box.top, tlV, trV)
                setLine(box.bottom, blV, brV)
                setLine(box.left, tlV, blV)
                setLine(box.right, trV, brV)
            else
                if cache.box then
                    for _, l in pairs(cache.box) do
                        if l then l.Visible = false end
                    end
                end
            end
        end
    else
        if cache.box then
            for _, l in pairs(cache.box) do
                if l then pcall(function() l:Remove() end) end
            end
            cache.box = nil
        end
    end
end

RunService.RenderStepped:Connect(function()
    if not State.ESPEnabled then
        for plr, _ in pairs(ESPCache) do
            cleanupESP(plr)
        end
        return
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            pcall(updatePlayerESP, plr)
        end
    end
end)

Players.PlayerRemoving:Connect(function(plr)
    cleanupESP(plr)
end)

--============================================================
-- UI — AIM
--============================================================
local AimTab = Window:CreateTab("Aim", 4483362458)

AimTab:CreateSection("Aimbot")

AimTab:CreateToggle({
    Name = "Enable Aimbot",
    CurrentValue = false,
    Flag = "AimbotEnabled",
    Callback = function(v) State.AimbotEnabled = v end,
})

AimTab:CreateSlider({
    Name = "FOV Size",
    Range = {20, 600},
    Increment = 1,
    Suffix = "px",
    CurrentValue = 120,
    Flag = "FOVSize",
    Callback = function(v) State.FOVSize = v end,
})

AimTab:CreateColorPicker({
    Name = "FOV Color",
    Color = State.FOVColor,
    Flag = "FOVColor",
    Callback = function(c)
        State.FOVColor = c
        if FOVCircle then FOVCircle.Color = c end
    end,
})

AimTab:CreateDropdown({
    Name = "Aim Body Part",
    Options = {
        "Head", "UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart",
        "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
        "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg"
    },
    CurrentOption = {"Head"},
    Flag = "AimBodyPart",
    Callback = function(opt)
        if type(opt) == "table" then opt = opt[1] end
        State.AimBodyPart = opt
    end,
})

AimTab:CreateSlider({
    Name = "Aim Magnetism",
    Range = {0, 100},
    Increment = 1,
    Suffix = "%",
    CurrentValue = 35,
    Flag = "AimMagnetism",
    Callback = function(v) State.AimMagnetism = v / 100 end,
})

AimTab:CreateSlider({
    Name = "Sticky Break Force",
    Range = {20, 800},
    Increment = 5,
    Suffix = "px",
    CurrentValue = 120,
    Flag = "StickyBreak",
    Callback = function(v) State.StickyBreak = v end,
})

AimTab:CreateSlider({
    Name = "Re-Lock Delay",
    Range = {0, 2000},
    Increment = 10,
    Suffix = "ms",
    CurrentValue = 400,
    Flag = "BreakCooldown",
    Callback = function(v) State.BreakCooldown = v / 1000 end,
})

AimTab:CreateSlider({
    Name = "Aim Range",
    Range = {50, 2000},
    Increment = 10,
    Suffix = " studs",
    CurrentValue = 500,
    Flag = "AimRange",
    Callback = function(v) State.AimRange = v end,
})

AimTab:CreateToggle({
    Name = "Wall Check",
    CurrentValue = false,
    Flag = "WallCheck",
    Callback = function(v) State.WallCheck = v end,
})

AimTab:CreateToggle({
    Name = "Ignore Teammates",
    CurrentValue = true,
    Flag = "IgnoreTeammates",
    Callback = function(v) State.IgnoreTeammates = v end,
})

AimTab:CreateToggle({
    Name = "Ignore Dead Players",
    CurrentValue = true,
    Flag = "IgnoreDead",
    Callback = function(v) State.IgnoreDead = v end,
})

AimTab:CreateToggle({
    Name = "Aim to Nearest Player",
    CurrentValue = false,
    Flag = "AimNearest",
    Callback = function(v) State.AimNearest = v end,
})

--============================================================
-- UI — ESP
--============================================================
local ESPTab = Window:CreateTab("ESP", 4483362458)

ESPTab:CreateSection("ESP")

ESPTab:CreateToggle({
    Name = "Enable ESP",
    CurrentValue = false,
    Flag = "ESPEnabled",
    Callback = function(v) State.ESPEnabled = v end,
})

ESPTab:CreateToggle({
    Name = "Chams",
    CurrentValue = false,
    Flag = "Chams",
    Callback = function(v) State.Chams = v end,
})

ESPTab:CreateColorPicker({
    Name = "Chams Fill Color",
    Color = State.ChamsFill,
    Flag = "ChamsFill",
    Callback = function(c) State.ChamsFill = c end,
})

ESPTab:CreateColorPicker({
    Name = "Chams Outline Color",
    Color = State.ChamsOutline,
    Flag = "ChamsOutline",
    Callback = function(c) State.ChamsOutline = c end,
})

ESPTab:CreateToggle({
    Name = "Skeleton",
    CurrentValue = false,
    Flag = "Skeleton",
    Callback = function(v) State.Skeleton = v end,
})

ESPTab:CreateColorPicker({
    Name = "Skeleton Color",
    Color = State.SkeletonColor,
    Flag = "SkeletonColor",
    Callback = function(c) State.SkeletonColor = c end,
})

ESPTab:CreateToggle({
    Name = "Box",
    CurrentValue = false,
    Flag = "Box",
    Callback = function(v) State.Box = v end,
})

ESPTab:CreateColorPicker({
    Name = "Box Color",
    Color = State.BoxColor,
    Flag = "BoxColor",
    Callback = function(c) State.BoxColor = c end,
})

ESPTab:CreateToggle({
    Name = "Team Color",
    CurrentValue = false,
    Flag = "TeamColor",
    Callback = function(v) State.TeamColor = v end,
})

--============================================================
-- INIT
--============================================================
pcall(function() Rayfield:LoadConfiguration() end)

pcall(function()
    Rayfield:Notify({
        Title = "AGI",
        Content = "loaded. for pros.",
        Duration = 4,
    })
end)
