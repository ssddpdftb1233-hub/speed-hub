--[[
	EggCollectorLite - lightweight single LocalScript for YOUR OWN test place.
	Put in: StarterPlayer > StarterPlayerScripts

	Egg source (cheap, no workspace-wide scanning):
	  * Instances tagged "Egg" (CollectionService), and/or
	  * Children of a Workspace folder named EGG_FOLDER below
	Per egg: Attribute "Rarity" (or a rarity word in its name), Attribute "Area" (or parent name).

	Keys: F = fly, G = auto collect, RightShift = hide/show menu.
	Fly: WASD, Space/E up, Ctrl/Q down.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local EGG_FOLDER = "Eggs" -- change to the folder your test eggs live in

local lp = Players.LocalPlayer
local playerGui = lp:WaitForChild("PlayerGui")

local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Cosmic", "Eternal", "Secret", "Divine" }
local RANK = {}
for i, r in RARITIES do
	RANK[r] = i
end

local CFG = {
	Fly = false,
	Speed = 60,
	Auto = false,
	Area = "Any",
	Sel = {
		Legendary = true, Mythic = true, Cosmic = true, Eternal = true, Secret = true, Divine = true,
	},
}

local gui -- created in the UI section below

local old = playerGui:FindFirstChild("EggLiteGui")
if old then
	old:Destroy()
end

------------------------------------------------------------------------
-- Egg registry (computed once per egg)
------------------------------------------------------------------------
local eggs = {}
local areaList = { "Any" }
local areaSeen = { Any = true }
local blacklist = {}

local function detectRarity(inst)
	local a = inst:GetAttribute("Rarity")
	if type(a) == "string" then
		for _, r in RARITIES do
			if a:lower() == r:lower() then
				return r
			end
		end
	end
	local n = inst.Name:lower()
	for i = #RARITIES, 1, -1 do -- reverse so "Uncommon" wins over "Common"
		if n:find(RARITIES[i]:lower(), 1, true) then
			return RARITIES[i]
		end
	end
end

local function addEgg(inst)
	if eggs[inst] then
		return
	end
	local part = inst:IsA("BasePart") and inst or (inst:IsA("Model") and (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)))
	if not part then
		return
	end
	local size = 1
	if inst:IsA("Model") then
		size = inst:GetExtentsSize().Magnitude
	else
		size = inst.Size.Magnitude
	end
	local area = inst:GetAttribute("Area")
	if type(area) ~= "string" then
		area = inst.Parent and inst.Parent.Name or "World"
	end
	if not areaSeen[area] then
		areaSeen[area] = true
		table.insert(areaList, area)
	end
	local rarity = detectRarity(inst)
	eggs[inst] = {
		inst = inst,
		part = part,
		rarity = rarity,
		rank = rarity and RANK[rarity] or 0,
		area = area,
		size = size,
		born = os.clock(),
	}
	inst.AncestryChanged:Connect(function(_, parent)
		if not parent then
			eggs[inst] = nil
		end
	end)
end

for _, inst in CollectionService:GetTagged("Egg") do
	addEgg(inst)
end
CollectionService:GetInstanceAddedSignal("Egg"):Connect(addEgg)

local folder = workspace:FindFirstChild(EGG_FOLDER)
if folder then
	for _, inst in folder:GetChildren() do
		addEgg(inst)
	end
	folder.ChildAdded:Connect(function(inst)
		task.defer(addEgg, inst)
	end)
end

------------------------------------------------------------------------
-- Target selection
------------------------------------------------------------------------
local function getRoot()
	local c = lp.Character
	return c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
end

local target, collecting = nil, false
local statusLabel

local function setStatus(text)
	if statusLabel then
		statusLabel.Text = text
	end
end

local function pickBest()
	local root = getRoot()
	if not root then
		return nil
	end
	local now = os.clock()
	local best, bestScore
	for _, e in eggs do
		local okRarity = e.rarity and CFG.Sel[e.rarity]
		local okArea = CFG.Area == "Any" or e.area == CFG.Area
		local free = not blacklist[e.inst] or blacklist[e.inst] < now
		if okRarity and okArea and free and e.part.Parent then
			local fresh = math.clamp(30 - (now - e.born) / 2, 0, 30)
			local s = e.rank * 1000 + math.min(e.size, 50) + fresh - (e.part.Position - root.Position).Magnitude * 0.1
			if not bestScore or s > bestScore then
				best, bestScore = e, s
			end
		end
	end
	return best
end

local function collect(e)
	collecting = true
	task.spawn(function()
		local root = getRoot()
		if root and e.part.Parent then
			root.CFrame = CFrame.new(e.part.Position + Vector3.new(0, 2, 0))
		end
		for _, d in e.inst:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				pcall(function()
					d:InputHoldBegin()
					task.wait(d.HoldDuration + 0.1)
					d:InputHoldEnd()
				end)
			end
		end
		blacklist[e.inst] = os.clock() + 10
		target = nil
		collecting = false
	end)
end

task.spawn(function()
	while gui == nil or gui.Parent do
		task.wait(0.5)
		if CFG.Auto and not collecting then
			local best = pickBest()
			if best ~= target then
				target = best
				setStatus(best and ("Going for: " .. (best.rarity or "?") .. " (" .. best.area .. ")") or "No matching egg")
			end
		end
	end
end)

------------------------------------------------------------------------
-- Fly / auto movement (only runs while needed)
------------------------------------------------------------------------
local hbConn, bv

local function stopMove()
	if hbConn then
		hbConn:Disconnect()
		hbConn = nil
	end
	if bv then
		bv:Destroy()
		bv = nil
	end
	local _, hum = getRoot()
	if hum then
		hum.PlatformStand = false
	end
end

local function step()
	local root, hum = getRoot()
	if not root or not hum then
		return
	end
	if not bv or bv.Parent ~= root then
		if bv then
			bv:Destroy()
		end
		bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
		bv.Parent = root
	end
	hum.PlatformStand = true

	local vel = Vector3.zero
	if CFG.Auto then
		if target and target.part.Parent and not collecting then
			local delta = target.part.Position - root.Position
			local dist = delta.Magnitude
			if dist < 5 then
				collect(target)
			else
				vel = delta.Unit * math.min(CFG.Speed, dist * 8)
			end
		end
	else
		local cf = workspace.CurrentCamera.CFrame
		local dir = Vector3.zero
		local down = UserInputService.IsKeyDown
		if down(UserInputService, Enum.KeyCode.W) then dir += cf.LookVector end
		if down(UserInputService, Enum.KeyCode.S) then dir -= cf.LookVector end
		if down(UserInputService, Enum.KeyCode.D) then dir += cf.RightVector end
		if down(UserInputService, Enum.KeyCode.A) then dir -= cf.RightVector end
		if down(UserInputService, Enum.KeyCode.Space) or down(UserInputService, Enum.KeyCode.E) then dir += Vector3.yAxis end
		if down(UserInputService, Enum.KeyCode.LeftControl) or down(UserInputService, Enum.KeyCode.Q) then dir -= Vector3.yAxis end
		if dir.Magnitude > 0 then
			vel = dir.Unit * CFG.Speed
		end
	end
	bv.Velocity = vel
end

local function updateMove()
	if CFG.Fly or CFG.Auto then
		if not hbConn then
			hbConn = RunService.Heartbeat:Connect(step)
		end
	else
		stopMove()
	end
end

------------------------------------------------------------------------
-- UI (plain and light)
------------------------------------------------------------------------
gui = Instance.new("ScreenGui")
gui.Name = "EggLiteGui"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local BG = Color3.fromRGB(24, 24, 32)
local OFF = Color3.fromRGB(60, 60, 75)
local ON = Color3.fromRGB(110, 85, 240)
local WHITE = Color3.new(1, 1, 1)

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(250, 0)
main.AutomaticSize = Enum.AutomaticSize.Y
main.Position = UDim2.new(0, 30, 0.5, -200)
main.BackgroundColor3 = BG
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

local pad = Instance.new("UIPadding", main)
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)

local layout = Instance.new("UIListLayout", main)
layout.Padding = UDim.new(0, 5)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local function mkButton(text, order, callback)
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, 26)
	b.BackgroundColor3 = OFF
	b.TextColor3 = WHITE
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.Text = text
	b.BorderSizePixel = 0
	b.Parent = main
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	b.MouseButton1Click:Connect(callback)
	return b
end

local function mkLabel(text, order, color)
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.new(1, 0, 0, 20)
	l.BackgroundTransparency = 1
	l.TextColor3 = color or WHITE
	l.Font = Enum.Font.GothamBold
	l.TextSize = 12
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = main
	return l
end

-- Title (drag handle)
local titleBar = mkLabel("Egg Collector Lite  (drag)", 1)
titleBar.Active = true
titleBar.TextSize = 14
do
	local dragging, startMouse, startPos, moveConn, endConn
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragging = true
		startMouse = input.Position
		startPos = main.Position
		moveConn = UserInputService.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				local d = i.Position - startMouse
				main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end)
		endConn = UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = false
				moveConn:Disconnect()
				endConn:Disconnect()
			end
		end)
	end)
end

statusLabel = mkLabel("Auto is off", 2, Color3.fromRGB(90, 255, 140))

-- Fly + Auto
local flyBtn, autoBtn
local function render()
	flyBtn.Text = "Fly (F): " .. (CFG.Fly and "ON" or "OFF")
	flyBtn.BackgroundColor3 = CFG.Fly and ON or OFF
	autoBtn.Text = "Auto collect (G): " .. (CFG.Auto and "ON" or "OFF")
	autoBtn.BackgroundColor3 = CFG.Auto and ON or OFF
end

flyBtn = mkButton("", 3, function()
	CFG.Fly = not CFG.Fly
	render()
	updateMove()
end)
autoBtn = mkButton("", 5, function()
	CFG.Auto = not CFG.Auto
	target = nil
	setStatus(CFG.Auto and "Searching..." or "Auto is off")
	render()
	updateMove()
end)

-- Speed slider (1 - 1000)
local sliderLabel = mkLabel("Fly speed: " .. CFG.Speed, 4)
do
	local bar = Instance.new("Frame")
	bar.LayoutOrder = 4
	bar.Size = UDim2.new(1, 0, 0, 8)
	bar.BackgroundColor3 = OFF
	bar.BorderSizePixel = 0
	bar.Parent = main
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 4)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(CFG.Speed / 1000, 1)
	fill.BackgroundColor3 = ON
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

	-- order: label (4) then bar (4) then buttons; keep label above bar
	sliderLabel.LayoutOrder = 4
	bar.LayoutOrder = 4

	local function setFromX(x)
		local a = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		CFG.Speed = math.max(1, math.floor(a * 1000 + 0.5))
		fill.Size = UDim2.fromScale(CFG.Speed / 1000, 1)
		sliderLabel.Text = "Fly speed: " .. CFG.Speed
	end

	bar.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		setFromX(input.Position.X)
		local moveConn, endConn
		moveConn = UserInputService.InputChanged:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
				setFromX(i.Position.X)
			end
		end)
		endConn = UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				moveConn:Disconnect()
				endConn:Disconnect()
			end
		end)
	end)
end

-- Area cycle
local areaBtn
areaBtn = mkButton("Area: Any", 6, function()
	local idx = table.find(areaList, CFG.Area) or 1
	CFG.Area = areaList[(idx % #areaList) + 1]
	areaBtn.Text = "Area: " .. CFG.Area
	target = nil
end)

-- Rarity buttons (2 per row)
mkLabel("Rarities to search for:", 7)
local grid = Instance.new("Frame")
grid.LayoutOrder = 8
grid.Size = UDim2.new(1, 0, 0, 5 * 28)
grid.BackgroundTransparency = 1
grid.Parent = main
local gl = Instance.new("UIGridLayout", grid)
gl.CellSize = UDim2.new(0.5, -3, 0, 24)
gl.CellPadding = UDim2.fromOffset(6, 4)
gl.SortOrder = Enum.SortOrder.LayoutOrder

local rarityButtons = {}
local function renderRarity(r)
	rarityButtons[r].BackgroundColor3 = CFG.Sel[r] and ON or OFF
end
for i, r in RARITIES do
	local b = Instance.new("TextButton")
	b.LayoutOrder = i
	b.BackgroundColor3 = OFF
	b.TextColor3 = WHITE
	b.Font = Enum.Font.Gotham
	b.TextSize = 12
	b.Text = r
	b.BorderSizePixel = 0
	b.Parent = grid
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	rarityButtons[r] = b
	b.MouseButton1Click:Connect(function()
		CFG.Sel[r] = not CFG.Sel[r]
		renderRarity(r)
		target = nil
	end)
	renderRarity(r)
end

mkButton("Select all / none", 9, function()
	local anyOff = false
	for _, r in RARITIES do
		if not CFG.Sel[r] then
			anyOff = true
		end
	end
	for _, r in RARITIES do
		CFG.Sel[r] = anyOff
		renderRarity(r)
	end
	target = nil
end)

render()

------------------------------------------------------------------------
-- Hotkeys
------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gpe)
	if input.KeyCode == Enum.KeyCode.RightShift then
		main.Visible = not main.Visible
		return
	end
	if gpe then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		CFG.Fly = not CFG.Fly
		render()
		updateMove()
	elseif input.KeyCode == Enum.KeyCode.G then
		CFG.Auto = not CFG.Auto
		target = nil
		setStatus(CFG.Auto and "Searching..." or "Auto is off")
		render()
		updateMove()
	end
end)
