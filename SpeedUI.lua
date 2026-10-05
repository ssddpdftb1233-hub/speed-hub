--[[
	TestToolkit - single LocalScript
	Put in: StarterPlayer > StarterPlayerScripts (as a LocalScript)
	For use in YOUR OWN place / Studio testing with your own NPCs and test players.

	Features: ESP (names/health), Rainbow ESP, Wallhack toggle, FOV circle + FOV limit on/off,
	aim-lock with rebindable key, target switching, WalkSpeed toggle, smooth draggable UI,
	RightShift to open/close the menu.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local function cam()
	return Workspace.CurrentCamera
end

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
local CFG = {
	-- ESP
	ESP = true,
	Names = true,
	Health = true,
	Rainbow = false,
	RainbowSpeed = 0.4,
	ESPColor = Color3.fromRGB(255, 70, 70),
	Wallhack = true, -- true = ESP visible through walls
	TargetPlayers = true,
	TargetNPCs = true,
	TeamCheck = false,

	-- FOV
	FOVEnabled = true, -- limit aiming to the circle (off = whole screen)
	ShowFOV = true, -- draw the circle
	FOVRadius = 160,

	-- Aim lock
	Aim = true,
	HoldToAim = true,
	AimKey = Enum.UserInputType.MouseButton2,
	SwitchKey = Enum.KeyCode.Q,
	AimPart = "Head",
	AimSpeed = 0.35, -- 1 = instant snap
	WallCheck = false, -- true = don't lock onto targets behind walls

	-- Movement
	WalkSpeedOn = false,
	WalkSpeed = 32,

	-- Menu
	MenuKey = Enum.KeyCode.RightShift,
}

local AIM_PARTS = { "Head", "UpperTorso", "HumanoidRootPart" }

------------------------------------------------------------------------
-- Cleanup of previous runs
------------------------------------------------------------------------
pcall(function()
	RunService:UnbindFromRenderStep("TestToolkitAim")
end)
local old = PlayerGui:FindFirstChild("TestToolkitGui")
if old then
	old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "TestToolkitGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 100
gui.Parent = PlayerGui

------------------------------------------------------------------------
-- ESP tracking
------------------------------------------------------------------------
local entries = {}
local pending = {}

local function removeEntry(model)
	local e = entries[model]
	if not e then
		return
	end
	entries[model] = nil
	for _, c in e.conns do
		c:Disconnect()
	end
	if e.hl then
		e.hl:Destroy()
	end
	if e.bb then
		e.bb:Destroy()
	end
end

local function addModel(model)
	if entries[model] or pending[model] then
		return
	end
	if model == LocalPlayer.Character then
		return
	end
	pending[model] = true
	task.spawn(function()
		local hum = model:WaitForChild("Humanoid", 5)
		local root = model:WaitForChild("HumanoidRootPart", 5)
		pending[model] = nil
		if not hum or not root or not hum:IsA("Humanoid") then
			return
		end
		if entries[model] or not model:IsDescendantOf(Workspace) then
			return
		end
		local plr = Players:GetPlayerFromCharacter(model)
		if plr == LocalPlayer then
			return
		end

		local hl = Instance.new("Highlight")
		hl.Name = "TT_Highlight"
		hl.Adornee = model
		hl.FillTransparency = 0.6
		hl.OutlineTransparency = 0
		hl.Parent = model

		local bb = Instance.new("BillboardGui")
		bb.Name = "TT_Billboard"
		bb.Adornee = root
		bb.Size = UDim2.fromOffset(140, 34)
		bb.StudsOffset = Vector3.new(0, 3.4, 0)
		bb.ResetOnSpawn = false
		bb.Parent = gui

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextStrokeTransparency = 0.4
		label.TextColor3 = CFG.ESPColor
		label.Parent = bb

		local e = {
			model = model,
			hum = hum,
			root = root,
			plr = plr,
			hl = hl,
			bb = bb,
			label = label,
			conns = {},
		}
		table.insert(e.conns, model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(Workspace) then
				removeEntry(model)
			end
		end))
		entries[model] = e
	end)
end

Workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Humanoid") and inst.Parent and inst.Parent:IsA("Model") then
		addModel(inst.Parent)
	end
end)
for _, inst in Workspace:GetDescendants() do
	if inst:IsA("Humanoid") and inst.Parent and inst.Parent:IsA("Model") then
		addModel(inst.Parent)
	end
end

local function isAllowed(e)
	if e.plr then
		if not CFG.TargetPlayers then
			return false
		end
		if CFG.TeamCheck and e.plr.Team ~= nil and e.plr.Team == LocalPlayer.Team then
			return false
		end
		return true
	end
	return CFG.TargetNPCs
end

------------------------------------------------------------------------
-- Aim helpers
------------------------------------------------------------------------
local function getAimPart(e)
	return e.model:FindFirstChild(CFG.AimPart) or e.root
end

local function wallBlocked(e, part)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { e.model }
	if LocalPlayer.Character then
		table.insert(ignore, LocalPlayer.Character)
	end
	params.FilterDescendantsInstances = ignore
	local origin = cam().CFrame.Position
	return Workspace:Raycast(origin, part.Position - origin, params) ~= nil
end

local function candidates()
	local out = {}
	local c = cam()
	if not c then
		return out
	end
	local center = c.ViewportSize / 2
	for _, e in entries do
		if isAllowed(e) and e.hum.Health > 0 then
			local part = getAimPart(e)
			if part then
				local v, on = c:WorldToViewportPoint(part.Position)
				if on then
					local sp = Vector2.new(v.X, v.Y)
					local d = (sp - center).Magnitude
					if (not CFG.FOVEnabled or d <= CFG.FOVRadius) and (not CFG.WallCheck or not wallBlocked(e, part)) then
						table.insert(out, { e = e, part = part, dist = d, x = sp.X })
					end
				end
			end
		end
	end
	return out
end

local aiming = false
local lockedEntry = nil
local switchRequested = false
local statusLabel -- set by UI

local function displayName(e)
	return e.plr and e.plr.DisplayName or e.model.Name
end

local lastStatus = ""
local function setStatus(text)
	if statusLabel and text ~= lastStatus then
		lastStatus = text
		statusLabel.Text = text
	end
end

RunService:BindToRenderStep("TestToolkitAim", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not (CFG.Aim and aiming) then
		lockedEntry = nil
		switchRequested = false
		setStatus("Target: none")
		return
	end

	local list = candidates()
	local cur

	if switchRequested then
		switchRequested = false
		if #list > 0 then
			table.sort(list, function(a, b)
				return a.x < b.x
			end)
			local idx = 0
			for i, c in list do
				if c.e == lockedEntry then
					idx = i
					break
				end
			end
			cur = list[(idx % #list) + 1]
			lockedEntry = cur.e
		end
	end

	if not cur and lockedEntry then
		for _, c in list do
			if c.e == lockedEntry then
				cur = c
				break
			end
		end
	end

	if not cur then
		table.sort(list, function(a, b)
			return a.dist < b.dist
		end)
		cur = list[1]
		lockedEntry = cur and cur.e or nil
	end

	if not cur then
		setStatus("Target: none")
		return
	end

	setStatus("Target: " .. displayName(cur.e))

	local c = cam()
	local goal = CFrame.lookAt(c.CFrame.Position, cur.part.Position)
	local alpha = 1 - (1 - math.clamp(CFG.AimSpeed, 0.01, 1)) ^ (math.min(dt, 0.1) * 60)
	c.CFrame = c.CFrame:Lerp(goal, alpha)
end)

------------------------------------------------------------------------
-- ESP + FOV circle + WalkSpeed update
------------------------------------------------------------------------
local fov = Instance.new("Frame")
fov.Name = "FOVCircle"
fov.AnchorPoint = Vector2.new(0.5, 0.5)
fov.Position = UDim2.fromScale(0.5, 0.5)
fov.BackgroundTransparency = 1
fov.Parent = gui
local fovCorner = Instance.new("UICorner")
fovCorner.CornerRadius = UDim.new(1, 0)
fovCorner.Parent = fov
local fovStroke = Instance.new("UIStroke")
fovStroke.Thickness = 1.5
fovStroke.Color = Color3.new(1, 1, 1)
fovStroke.Parent = fov

RunService.RenderStepped:Connect(function()
	local rainbow = Color3.fromHSV((os.clock() * CFG.RainbowSpeed) % 1, 1, 1)
	local col = CFG.Rainbow and rainbow or CFG.ESPColor

	for _, e in entries do
		local show = CFG.ESP and e.hum.Health > 0 and isAllowed(e)
		e.hl.Enabled = show
		e.bb.Enabled = show and (CFG.Names or CFG.Health)
		if show then
			e.hl.FillColor = col
			e.hl.OutlineColor = col
			e.hl.DepthMode = CFG.Wallhack and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
			e.bb.AlwaysOnTop = CFG.Wallhack
			e.label.TextColor3 = col
			local text = ""
			if CFG.Names then
				text = displayName(e)
			end
			if CFG.Health then
				local hp = ("%d/%d HP"):format(math.floor(e.hum.Health), math.floor(e.hum.MaxHealth))
				text = text == "" and hp or (text .. "\n" .. hp)
			end
			e.label.Text = text
		end
	end

	fov.Visible = CFG.ShowFOV
	fov.Size = UDim2.fromOffset(CFG.FOVRadius * 2, CFG.FOVRadius * 2)
	fovStroke.Color = CFG.Rainbow and rainbow or (lockedEntry and Color3.fromRGB(90, 255, 140) or Color3.new(1, 1, 1))
end)

local wsApplied = false
RunService.Heartbeat:Connect(function()
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	if CFG.WalkSpeedOn then
		hum.WalkSpeed = CFG.WalkSpeed
		wsApplied = true
	elseif wsApplied then
		hum.WalkSpeed = 16
		wsApplied = false
	end
end)

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
local BG = Color3.fromRGB(22, 22, 29)
local ROW = Color3.fromRGB(33, 33, 43)
local ROW_HOVER = Color3.fromRGB(42, 42, 54)
local OFF = Color3.fromRGB(64, 64, 78)
local ACCENT = Color3.fromRGB(124, 92, 255)
local TEXT = Color3.fromRGB(235, 235, 245)
local SUBTEXT = Color3.fromRGB(150, 150, 170)

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
	return c
end

local function tween(obj, t, props)
	TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play()
end

local main = Instance.new("CanvasGroup")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.fromScale(0.5, 0.5)
main.Size = UDim2.fromOffset(340, 470)
main.BackgroundColor3 = BG
main.GroupTransparency = 1
main.BorderSizePixel = 0
main.Parent = gui
corner(main, 12)
local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(60, 60, 78)
mainStroke.Thickness = 1
mainStroke.Parent = main
local scale = Instance.new("UIScale")
scale.Scale = 0.92
scale.Parent = main

-- Lets the cursor move even if the game locks the mouse (first person)
local modal = Instance.new("TextButton")
modal.BackgroundTransparency = 1
modal.Size = UDim2.fromOffset(0, 0)
modal.Text = ""
modal.Modal = true
modal.Parent = main

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 42)
header.BackgroundColor3 = Color3.fromRGB(28, 28, 37)
header.BorderSizePixel = 0
header.Parent = main

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(14, 0)
title.Size = UDim2.new(1, -28, 1, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = TEXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Test Toolkit   <font color=\"rgb(150,150,170)\" size=\"11\">RightShift to hide</font>"
title.RichText = true
title.Parent = header

local content = Instance.new("ScrollingFrame")
content.Position = UDim2.fromOffset(0, 42)
content.Size = UDim2.new(1, 0, 1, -42)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 3
content.ScrollBarImageColor3 = ACCENT
content.CanvasSize = UDim2.new()
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.Parent = main

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = content
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 10)
pad.PaddingBottom = UDim.new(0, 10)
pad.PaddingLeft = UDim.new(0, 10)
pad.PaddingRight = UDim.new(0, 13)
pad.Parent = content

local order = 0
local function newRow(height)
	order += 1
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, height)
	row.BackgroundColor3 = ROW
	row.BorderSizePixel = 0
	row.Parent = content
	corner(row, 8)
	return row
end

local function rowLabel(row, text)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(12, 0)
	l.Size = UDim2.new(0.6, 0, 1, 0)
	l.Font = Enum.Font.Gotham
	l.TextSize = 13
	l.TextColor3 = TEXT
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = row
	return l
end

local function hover(row, btn)
	btn.MouseEnter:Connect(function()
		tween(row, 0.15, { BackgroundColor3 = ROW_HOVER })
	end)
	btn.MouseLeave:Connect(function()
		tween(row, 0.15, { BackgroundColor3 = ROW })
	end)
end

local function addSection(text)
	order += 1
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 22)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 11
	l.TextColor3 = ACCENT
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = "  " .. string.upper(text)
	l.Parent = content
end

local function addToggle(text, key)
	local row = newRow(34)
	rowLabel(row, text)

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -12, 0.5, 0)
	track.Size = UDim2.fromOffset(40, 20)
	track.BackgroundColor3 = OFF
	track.BorderSizePixel = 0
	track.Parent = row
	corner(track, 10)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = UDim2.new(0, 2, 0.5, 0)
	knob.Size = UDim2.fromOffset(16, 16)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.Parent = track
	corner(knob, 8)

	local function render(instant)
		local on = CFG[key]
		local goalTrack = { BackgroundColor3 = on and ACCENT or OFF }
		local goalKnob = { Position = on and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0) }
		if instant then
			track.BackgroundColor3 = goalTrack.BackgroundColor3
			knob.Position = goalKnob.Position
		else
			tween(track, 0.2, goalTrack)
			tween(knob, 0.2, goalKnob)
		end
	end
	render(true)

	local btn = Instance.new("TextButton")
	btn.BackgroundTransparency = 1
	btn.Size = UDim2.fromScale(1, 1)
	btn.Text = ""
	btn.Parent = row
	hover(row, btn)
	btn.MouseButton1Click:Connect(function()
		CFG[key] = not CFG[key]
		render(false)
		if key == "Aim" or key == "HoldToAim" then
			aiming = false
			lockedEntry = nil
		end
	end)
end

local function addSlider(text, key, min, max, step, decimals)
	local row = newRow(48)
	local label = rowLabel(row, text)
	label.Position = UDim2.fromOffset(12, -6)

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.AnchorPoint = Vector2.new(1, 0)
	valueLabel.Position = UDim2.new(1, -12, 0, 6)
	valueLabel.Size = UDim2.fromOffset(80, 18)
	valueLabel.Font = Enum.Font.GothamMedium
	valueLabel.TextSize = 12
	valueLabel.TextColor3 = SUBTEXT
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Parent = row

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 12, 1, -16)
	track.Size = UDim2.new(1, -24, 0, 6)
	track.BackgroundColor3 = OFF
	track.BorderSizePixel = 0
	track.Parent = row
	corner(track, 3)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = ACCENT
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	corner(fill, 3)

	local function render(instant)
		local a = (CFG[key] - min) / (max - min)
		valueLabel.Text = string.format("%." .. (decimals or 0) .. "f", CFG[key])
		if instant then
			fill.Size = UDim2.fromScale(a, 1)
		else
			tween(fill, 0.08, { Size = UDim2.fromScale(a, 1) })
		end
	end
	render(true)

	local dragging = false
	local function setFromX(x)
		local a = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local v = min + (max - min) * a
		v = math.floor(v / step + 0.5) * step
		CFG[key] = math.clamp(v, min, max)
		render(false)
	end

	local btn = Instance.new("TextButton")
	btn.BackgroundTransparency = 1
	btn.Size = UDim2.fromScale(1, 1)
	btn.Text = ""
	btn.Parent = row
	hover(row, btn)
	btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local listening = nil -- callback waiting for a key press

local function addKeybind(text, key)
	local row = newRow(34)
	rowLabel(row, text)

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -12, 0.5, 0)
	btn.Size = UDim2.fromOffset(110, 22)
	btn.BackgroundColor3 = OFF
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 12
	btn.TextColor3 = TEXT
	btn.Text = CFG[key].Name
	btn.AutoButtonColor = false
	btn.Parent = row
	corner(btn, 6)

	btn.MouseButton1Click:Connect(function()
		btn.Text = "press a key..."
		tween(btn, 0.15, { BackgroundColor3 = ACCENT })
		listening = function(bind)
			if bind then
				CFG[key] = bind
			end
			btn.Text = CFG[key].Name
			tween(btn, 0.15, { BackgroundColor3 = OFF })
		end
	end)
	hover(row, btn)
end

local function addCycle(text, key, options)
	local row = newRow(34)
	rowLabel(row, text)

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -12, 0.5, 0)
	btn.Size = UDim2.fromOffset(130, 22)
	btn.BackgroundColor3 = OFF
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 12
	btn.TextColor3 = TEXT
	btn.Text = CFG[key]
	btn.AutoButtonColor = false
	btn.Parent = row
	corner(btn, 6)

	btn.MouseButton1Click:Connect(function()
		local idx = table.find(options, CFG[key]) or 0
		CFG[key] = options[(idx % #options) + 1]
		btn.Text = CFG[key]
	end)
	hover(row, btn)
end

local function addInfo()
	local row = newRow(30)
	statusLabel = rowLabel(row, "Target: none")
	statusLabel.Size = UDim2.new(1, -24, 1, 0)
	statusLabel.TextColor3 = Color3.fromRGB(90, 255, 140)
	statusLabel.Font = Enum.Font.GothamMedium
end

-- Build the menu
addSection("Status")
addInfo()

addSection("ESP")
addToggle("ESP", "ESP")
addToggle("Names", "Names")
addToggle("Health", "Health")
addToggle("Rainbow ESP", "Rainbow")
addSlider("Rainbow speed", "RainbowSpeed", 0.1, 2, 0.1, 1)
addToggle("Wallhack (see through walls)", "Wallhack")
addToggle("Show players", "TargetPlayers")
addToggle("Show NPCs", "TargetNPCs")
addToggle("Team check", "TeamCheck")

addSection("FOV")
addToggle("Show FOV circle", "ShowFOV")
addToggle("FOV limit (off = whole screen)", "FOVEnabled")
addSlider("FOV radius", "FOVRadius", 40, 500, 5, 0)

addSection("Aim lock")
addToggle("Aim lock", "Aim")
addToggle("Hold to aim (off = toggle)", "HoldToAim")
addKeybind("Aim key", "AimKey")
addKeybind("Switch target key", "SwitchKey")
addCycle("Aim part", "AimPart", AIM_PARTS)
addSlider("Aim speed", "AimSpeed", 0.05, 1, 0.05, 2)
addToggle("Wall check (no lock behind walls)", "WallCheck")

addSection("Movement")
addToggle("WalkSpeed", "WalkSpeedOn")
addSlider("WalkSpeed value", "WalkSpeed", 16, 150, 1, 0)

addSection("Menu")
addKeybind("Menu key", "MenuKey")

-- Dragging
do
	local dragging, dragStart, startPos = false, nil, nil
	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			TweenService
				:Create(main, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
					Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y),
				})
				:Play()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- Open / close animation
local menuOpen = false
local function setMenu(open)
	menuOpen = open
	modal.Modal = open
	if open then
		main.Visible = true
	end
	tween(main, 0.25, { GroupTransparency = open and 0 or 1 })
	tween(scale, 0.25, { Scale = open and 1 or 0.92 })
	if not open then
		task.delay(0.27, function()
			if not menuOpen then
				main.Visible = false
			end
		end)
	end
end
setMenu(true)

------------------------------------------------------------------------
-- Input
------------------------------------------------------------------------
local function matches(bind, input)
	if bind.EnumType == Enum.KeyCode then
		return input.KeyCode == bind
	end
	return input.UserInputType == bind
end

UserInputService.InputBegan:Connect(function(input, gpe)
	-- rebinding
	if listening then
		local bind
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode ~= Enum.KeyCode.Escape then
				bind = input.KeyCode
			end
		elseif
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.MouseButton3
		then
			bind = input.UserInputType
		else
			return
		end
		local cb = listening
		listening = nil
		cb(bind)
		return
	end

	if matches(CFG.MenuKey, input) then
		setMenu(not menuOpen)
		return
	end

	if gpe then
		return
	end

	if CFG.Aim and matches(CFG.AimKey, input) then
		if CFG.HoldToAim then
			aiming = true
		else
			aiming = not aiming
		end
		if not aiming then
			lockedEntry = nil
		end
	elseif matches(CFG.SwitchKey, input) and aiming then
		switchRequested = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if CFG.HoldToAim and matches(CFG.AimKey, input) then
		aiming = false
		lockedEntry = nil
	end
end)
