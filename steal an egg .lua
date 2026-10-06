--[[
	EggCollectorTest - single LocalScript
	Put in: StarterPlayer > StarterPlayerScripts (as a LocalScript)
	For YOUR OWN test place with your own test eggs / NPCs / players.

	How eggs are detected (edit the DETECTION section if your test setup differs):
	  * Any Model/BasePart whose name contains "egg", or tagged "Egg" with CollectionService
	  * Rarity: Attribute "Rarity" on the egg (or up to 3 parents), otherwise a rarity word in the name
	  * Area:   Attribute "Area", otherwise the top-level folder/model under Workspace
	  * Size:   bounding box of the egg (or Attribute "Size" if you set one)
	  * Spawn:  time the script first saw the egg (or Attribute "SpawnTime" in os.clock-style seconds ignored)

	Features: fly with a free speed slider, rarity selection (10 rarities), auto search/collect
	ranked by rarity / size / newness / distance / area, draggable smooth UI, RightShift toggle.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local function cam()
	return Workspace.CurrentCamera
end

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Cosmic", "Eternal", "Secret", "Divine" }
local RANK = {}
for i, r in RARITIES do
	RANK[r] = i
end

local RARITY_COLORS = {
	Common = Color3.fromRGB(190, 190, 190),
	Uncommon = Color3.fromRGB(110, 220, 110),
	Rare = Color3.fromRGB(80, 150, 255),
	Epic = Color3.fromRGB(180, 100, 255),
	Legendary = Color3.fromRGB(255, 190, 50),
	Mythic = Color3.fromRGB(255, 80, 120),
	Cosmic = Color3.fromRGB(90, 220, 255),
	Eternal = Color3.fromRGB(255, 255, 140),
	Secret = Color3.fromRGB(150, 150, 170),
	Divine = Color3.fromRGB(255, 240, 200),
}

local CFG = {
	-- Fly
	Fly = false,
	FlySpeed = 60, -- free slider 1..1000
	FlyKey = Enum.KeyCode.F,

	-- Auto search / collect
	Auto = false,
	AutoKey = Enum.KeyCode.G,
	Rarities = {
		Common = false,
		Uncommon = false,
		Rare = false,
		Epic = false,
		Legendary = true,
		Mythic = true,
		Cosmic = true,
		Eternal = true,
		Secret = true,
		Divine = true,
	},
	IncludeUnknown = false, -- eggs whose rarity couldn't be detected
	StrictRarest = true, -- always go for the rarest selected egg first
	Area = "Any",
	WRarity = 10,
	WSize = 3,
	WNewest = 2,
	WDistance = 1,

	-- Movement
	WalkSpeedOn = false,
	WalkSpeed = 32,

	-- Menu
	MenuKey = Enum.KeyCode.RightShift,
}

------------------------------------------------------------------------
-- Cleanup of previous runs
------------------------------------------------------------------------
local old = PlayerGui:FindFirstChild("EggCollectorGui")
if old then
	old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "EggCollectorGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 100
gui.Parent = PlayerGui

------------------------------------------------------------------------
-- DETECTION: egg registry
------------------------------------------------------------------------
local eggs = {} -- [instance] = data
local areas = { Any = true }
local blacklist = {} -- [instance] = os.clock() until which it's ignored

local function lowerFind(str, sub)
	return string.find(string.lower(str), string.lower(sub), 1, true) ~= nil
end

local function isEggInst(inst)
	if not (inst:IsA("Model") or inst:IsA("BasePart")) then
		return false
	end
	if not (lowerFind(inst.Name, "egg") or CollectionService:HasTag(inst, "Egg")) then
		return false
	end
	-- skip parts that are just pieces of an egg model
	local p = inst.Parent
	if p and p:IsA("Model") and (lowerFind(p.Name, "egg") or CollectionService:HasTag(p, "Egg")) then
		return false
	end
	-- skip characters
	if inst:FindFirstChildOfClass("Humanoid") or (p and p:FindFirstChildOfClass("Humanoid")) then
		return false
	end
	return true
end

local function detectRarity(inst)
	local cur = inst
	for _ = 1, 4 do
		if not cur or cur == Workspace then
			break
		end
		local a = cur:GetAttribute("Rarity")
		if type(a) == "string" then
			for _, r in RARITIES do
				if string.lower(a) == string.lower(r) then
					return r
				end
			end
		end
		cur = cur.Parent
	end
	cur = inst
	for _ = 1, 4 do
		if not cur or cur == Workspace then
			break
		end
		-- reverse order so "Uncommon" is matched before "Common"
		for i = #RARITIES, 1, -1 do
			if lowerFind(cur.Name, RARITIES[i]) then
				return RARITIES[i]
			end
		end
		cur = cur.Parent
	end
	return nil
end

local function detectArea(inst)
	local a = inst:GetAttribute("Area")
	if type(a) == "string" then
		return a
	end
	local cur = inst
	while cur.Parent and cur.Parent ~= Workspace do
		cur = cur.Parent
	end
	if cur == inst then
		return "World"
	end
	return cur.Name
end

local function getPart(inst)
	if inst:IsA("BasePart") then
		return inst
	end
	return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
end

local function detectSize(inst)
	local a = inst:GetAttribute("Size")
	if type(a) == "number" then
		return a
	end
	if inst:IsA("Model") then
		local ok, s = pcall(function()
			return inst:GetExtentsSize()
		end)
		if ok then
			return s.Magnitude
		end
	elseif inst:IsA("BasePart") then
		return inst.Size.Magnitude
	end
	return 1
end

local function refresh(e)
	e.rarity = detectRarity(e.inst)
	e.area = detectArea(e.inst)
	e.size = detectSize(e.inst)
	e.part = getPart(e.inst)
	areas[e.area] = true
end

local function addEgg(inst)
	if eggs[inst] or not isEggInst(inst) then
		return
	end
	local e = { inst = inst, seen = os.clock() }
	refresh(e)
	eggs[inst] = e
	inst.AncestryChanged:Connect(function()
		if not inst:IsDescendantOf(Workspace) then
			eggs[inst] = nil
		end
	end)
end

Workspace.DescendantAdded:Connect(function(inst)
	task.defer(addEgg, inst)
end)
for _, inst in Workspace:GetDescendants() do
	addEgg(inst)
end

------------------------------------------------------------------------
-- Targeting
------------------------------------------------------------------------
local function getChar()
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return char, hum, root
end

local function usable(e)
	if not e.part or not e.part.Parent then
		return false
	end
	if blacklist[e.inst] and blacklist[e.inst] > os.clock() then
		return false
	end
	if e.rarity then
		if not CFG.Rarities[e.rarity] then
			return false
		end
	elseif not CFG.IncludeUnknown then
		return false
	end
	if CFG.Area ~= "Any" and e.area ~= CFG.Area then
		return false
	end
	return true
end

local function score(e, rootPos)
	local rank = e.rarity and RANK[e.rarity] or 0
	local sizeN = math.clamp(e.size / 10, 0, 5)
	local fresh = math.clamp(1 - (os.clock() - e.seen) / 60, 0, 1)
	local dist = (e.part.Position - rootPos).Magnitude
	local s = rank * CFG.WRarity + sizeN * CFG.WSize + fresh * CFG.WNewest - dist * 0.02 * CFG.WDistance
	if CFG.StrictRarest then
		s += rank * 100000
	end
	return s
end

local currentTarget = nil
local collecting = false
local statusLabel
local lastStatus = ""

local function setStatus(t)
	if statusLabel and t ~= lastStatus then
		lastStatus = t
		statusLabel.Text = t
	end
end

local function pickBest()
	local _, _, root = getChar()
	if not root then
		return nil
	end
	local best, bestScore
	for _, e in eggs do
		if usable(e) then
			local s = score(e, root.Position)
			if not bestScore or s > bestScore then
				best, bestScore = e, s
			end
		end
	end
	return best
end

local function collect(e)
	if collecting then
		return
	end
	collecting = true
	task.spawn(function()
		local _, _, root = getChar()
		if root and e.part and e.part.Parent then
			-- touch-based eggs
			root.CFrame = CFrame.new(e.part.Position + Vector3.new(0, 2, 0))
		end
		-- proximity-prompt based eggs
		local prompts = {}
		for _, d in e.inst:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				table.insert(prompts, d)
			end
		end
		if e.inst:IsA("ProximityPrompt") then
			table.insert(prompts, e.inst)
		end
		for _, p in prompts do
			pcall(function()
				p:InputHoldBegin()
				task.wait(p.HoldDuration + 0.1)
				p:InputHoldEnd()
			end)
		end
		blacklist[e.inst] = os.clock() + 10
		collecting = false
	end)
end

-- Re-pick targets and update status text
task.spawn(function()
	while gui.Parent do
		task.wait(0.4)
		for _, e in eggs do
			if e.inst.Parent then
				refresh(e)
			end
		end
		if CFG.Auto then
			local keep = false
			if currentTarget and usable(currentTarget) then
				local _, _, root = getChar()
				if root and (currentTarget.part.Position - root.Position).Magnitude < 12 then
					keep = true
				end
			end
			if not keep then
				currentTarget = pickBest()
			end
		else
			currentTarget = nil
		end

		local count = 0
		for _, e in eggs do
			if usable(e) then
				count += 1
			end
		end
		if currentTarget then
			setStatus(("Matching eggs: %d  |  Going for: %s (%s)"):format(count, currentTarget.rarity or "Unknown", currentTarget.area))
		else
			setStatus(("Matching eggs: %d  |  Target: none"):format(count))
		end
	end
end)

------------------------------------------------------------------------
-- Fly / auto movement + WalkSpeed
------------------------------------------------------------------------
local bv = nil
local wsApplied = false

local function stopFly()
	if bv then
		bv:Destroy()
		bv = nil
	end
	local _, hum = getChar()
	if hum then
		hum.PlatformStand = false
	end
end

RunService.Heartbeat:Connect(function()
	local _, hum, root = getChar()
	if not hum or not root then
		return
	end

	-- walk speed
	if CFG.WalkSpeedOn then
		hum.WalkSpeed = CFG.WalkSpeed
		wsApplied = true
	elseif wsApplied then
		hum.WalkSpeed = 16
		wsApplied = false
	end

	if not (CFG.Fly or CFG.Auto) then
		if bv then
			stopFly()
		end
		return
	end

	if not bv or bv.Parent ~= root then
		if bv then
			bv:Destroy()
		end
		bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
		bv.Velocity = Vector3.zero
		bv.Parent = root
	end
	hum.PlatformStand = true

	local vel = Vector3.zero
	if CFG.Auto then
		if currentTarget and currentTarget.part and currentTarget.part.Parent and not collecting then
			local delta = currentTarget.part.Position - root.Position
			local dist = delta.Magnitude
			if dist < 5 then
				collect(currentTarget)
			else
				local speed = math.min(CFG.FlySpeed, dist * 8)
				vel = delta.Unit * speed
			end
		end
	else
		local c = cam()
		local dir = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			dir += c.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			dir -= c.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			dir += c.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			dir -= c.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then
			dir += Vector3.yAxis
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
			dir -= Vector3.yAxis
		end
		if dir.Magnitude > 0 then
			vel = dir.Unit * CFG.FlySpeed
		end
	end
	bv.Velocity = vel
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
main.Size = UDim2.fromOffset(360, 520)
main.BackgroundColor3 = BG
main.GroupTransparency = 1
main.BorderSizePixel = 0
main.Parent = gui
corner(main, 12)
local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(60, 60, 78)
mainStroke.Parent = main
local scale = Instance.new("UIScale")
scale.Scale = 0.92
scale.Parent = main

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
title.RichText = true
title.Text = 'Egg Collector (Test)   <font color="rgb(150,150,170)" size="11">drag me - RightShift hides</font>'
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

local function rowLabel(row, text, color)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(12, 0)
	l.Size = UDim2.new(0.62, 0, 1, 0)
	l.Font = Enum.Font.Gotham
	l.TextSize = 13
	l.TextColor3 = color or TEXT
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

local toggleRenderers = {}

local function addToggle(text, tbl, key, color, onChange)
	local row = newRow(34)
	rowLabel(row, text, color)

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
		local on = tbl[key]
		local bgc = on and ACCENT or OFF
		local pos = on and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
		if instant then
			track.BackgroundColor3 = bgc
			knob.Position = pos
		else
			tween(track, 0.2, { BackgroundColor3 = bgc })
			tween(knob, 0.2, { Position = pos })
		end
	end
	render(true)
	table.insert(toggleRenderers, render)

	local btn = Instance.new("TextButton")
	btn.BackgroundTransparency = 1
	btn.Size = UDim2.fromScale(1, 1)
	btn.Text = ""
	btn.Parent = row
	hover(row, btn)
	btn.MouseButton1Click:Connect(function()
		tbl[key] = not tbl[key]
		render(false)
		if onChange then
			onChange(tbl[key])
		end
	end)
	return render
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

local listening = nil

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

local function addCycle(text, key, getOptions)
	local row = newRow(34)
	rowLabel(row, text)

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -12, 0.5, 0)
	btn.Size = UDim2.fromOffset(140, 22)
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
		local options = getOptions()
		local idx = table.find(options, CFG[key]) or 0
		CFG[key] = options[(idx % #options) + 1]
		btn.Text = CFG[key]
	end)
	hover(row, btn)
end

local function addButton(text, callback)
	local row = newRow(30)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundTransparency = 1
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 13
	btn.TextColor3 = TEXT
	btn.Text = text
	btn.Parent = row
	hover(row, btn)
	btn.MouseButton1Click:Connect(callback)
end

local function addInfo()
	local row = newRow(44)
	statusLabel = rowLabel(row, "Matching eggs: 0  |  Target: none", Color3.fromRGB(90, 255, 140))
	statusLabel.Size = UDim2.new(1, -24, 1, 0)
	statusLabel.TextWrapped = true
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextSize = 12
end

local function areaOptions()
	local out = { "Any" }
	for a in areas do
		if a ~= "Any" then
			table.insert(out, a)
		end
	end
	table.sort(out, function(a, b)
		if a == "Any" then
			return true
		elseif b == "Any" then
			return false
		end
		return a < b
	end)
	return out
end

-- Build the menu
addSection("Status")
addInfo()

addSection("Fly  (WASD + Space/E up, Ctrl/Q down)")
addToggle("Fly", CFG, "Fly", nil, function(on)
	if not on and not CFG.Auto then
		stopFly()
	end
end)
addSlider("Fly speed (free)", "FlySpeed", 1, 1000, 1, 0)
addKeybind("Fly key", "FlyKey")

addSection("Egg rarities to search for")
local rarityRenderers = {}
for _, r in RARITIES do
	rarityRenderers[r] = addToggle(r, CFG.Rarities, r, RARITY_COLORS[r])
end
addButton("Select all", function()
	for _, r in RARITIES do
		CFG.Rarities[r] = true
		rarityRenderers[r](false)
	end
end)
addButton("Select none", function()
	for _, r in RARITIES do
		CFG.Rarities[r] = false
		rarityRenderers[r](false)
	end
end)
addToggle("Include unknown rarity", CFG, "IncludeUnknown")

addSection("Auto search / collect")
local autoRender
autoRender = addToggle("Auto search & collect", CFG, "Auto", nil, function(on)
	if not on and not CFG.Fly then
		stopFly()
	end
end)
addToggle("Rarest selected first (strict)", CFG, "StrictRarest")
addCycle("Area", "Area", areaOptions)
addSlider("Rarity weight", "WRarity", 0, 20, 1, 0)
addSlider("Size weight", "WSize", 0, 20, 1, 0)
addSlider("Newest-spawn weight", "WNewest", 0, 20, 1, 0)
addSlider("Distance penalty", "WDistance", 0, 20, 1, 0)
addKeybind("Auto key", "AutoKey")

addSection("Movement")
addToggle("WalkSpeed", CFG, "WalkSpeedOn")
addSlider("WalkSpeed value", "WalkSpeed", 16, 250, 1, 0)

addSection("Menu")
addKeybind("Menu key", "MenuKey")

-- Dragging (smooth)
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
			TweenService:Create(main, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
				Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y),
			}):Play()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- Keep toggle visuals in sync when Fly/Auto are changed with their hotkeys
task.spawn(function()
	while gui.Parent do
		task.wait(0.3)
		for _, render in toggleRenderers do
			render(false)
		end
	end
end)

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

	if matches(CFG.FlyKey, input) then
		CFG.Fly = not CFG.Fly
		if not CFG.Fly and not CFG.Auto then
			stopFly()
		end
	elseif matches(CFG.AutoKey, input) then
		CFG.Auto = not CFG.Auto
		if not CFG.Auto and not CFG.Fly then
			stopFly()
		end
	end
end)
