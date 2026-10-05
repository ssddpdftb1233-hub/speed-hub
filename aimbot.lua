```lua
local function CreateESP(player)
	if player == LocalPlayer then return end

	local function Setup(character)
		local old = character:FindFirstChild("AdminESP")
		if old then old:Destroy() end

		local highlight = Instance.new("Highlight")
		highlight.Name = "AdminESP"
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = 0.45
		highlight.OutlineTransparency = 0
		highlight.Parent = character

		local tag = Instance.new("BillboardGui")
		tag.Name = "ESPTag"
		tag.Size = UDim2.fromOffset(180, 45)
		tag.StudsOffset = Vector3.new(0, 3, 0)
		tag.AlwaysOnTop = true
		tag.Parent = character

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextStrokeTransparency = 0.35
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.Parent = tag

		RunService.RenderStepped:Connect(function()
			if not character.Parent then return end

			local root = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")

			if root and humanoid and humanoid.Health > 0 then
				local distance = (Camera.CFrame.Position - root.Position).Magnitude
				local color = Color3.fromHSV((tick() % 5) / 5, 0.9, 1)

				highlight.FillColor = color
				highlight.OutlineColor = color

				label.Text =
					player.DisplayName ..
					"\n" ..
					math.floor(distance) ..
					" studs"

				label.TextColor3 = color

				highlight.Enabled = Settings.ESP.Enabled
				tag.Enabled = Settings.ESP.Enabled and distance <= Settings.ESP.MaxDistance
			end
		end)
	end

	if player.Character then
		Setup(player.Character)
	end

	player.CharacterAdded:Connect(function(character)
		task.wait(0.25)
		Setup(character)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	CreateESP(player)
end

Players.PlayerAdded:Connect(CreateESP)

local function GetTarget()
	local closest = nil
	local closestDistance = Settings.Aim.FOV

	local center = Vector2.new(
		Camera.ViewportSize.X / 2,
		Camera.ViewportSize.Y / 2
	)

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then

			local character = player.Character
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local target = character:FindFirstChild(Settings.Aim.TargetPart)

			if humanoid and humanoid.Health > 0 and target then

				if Settings.Aim.TeamCheck
					and LocalPlayer.Team
					and player.Team
					and LocalPlayer.Team == player.Team then
					continue
				end

				local position, visible =
					Camera:WorldToViewportPoint(target.Position)

				if visible then
					local distance = (
						Vector2.new(position.X, position.Y) - center
					).Magnitude

					if distance < closestDistance then
						closestDistance = distance
						closest = target
					end
				end
			end
		end
	end

	return closest
end

local function AimAt(target)
	if not target then return end

	local targetCFrame = CFrame.lookAt(
		Camera.CFrame.Position,
		target.Position
	)

	Camera.CFrame = Camera.CFrame:Lerp(
		targetCFrame,
		Settings.Aim.Smoothness
	)
end

local aimHolding = false
local aimToggle = false

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if Settings.Aim.Mode == "Hold" then
			aimHolding = true
		else
			aimToggle = not aimToggle
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		aimHolding = false
	end
end)

RunService.RenderStepped:Connect(function()
	local active = false

	if Settings.Aim.Enabled then
		if Settings.Aim.Mode == "Hold" then
			active = aimHolding
		elseif Settings.Aim.Mode == "Toggle" then
			active = aimToggle
		end
	end

	if active then
		AimAt(GetTarget())
	end
end)

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(330, 420)
Main.Position = UDim2.new(0, 30, 0.5, -210)
Main.BackgroundColor3 = Color3.fromRGB(13, 15, 20)
Main.BorderSizePixel = 0
Main.Parent = ScreenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = Main

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(45, 50, 65)
stroke.Parent = Main

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 55)
title.BackgroundTransparency = 1
title.Text = "ADMIN CONTROL"
title.TextColor3 = Color3.fromRGB(255,255,255)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.Parent = Main

local function Button(text, position)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -30, 0, 40)
	b.Position = position
	b.BackgroundColor3 = Color3.fromRGB(25,28,36)
	b.TextColor3 = Color3.fromRGB(235,235,240)
	b.TextSize = 13
	b.Font = Enum.Font.GothamMedium
	b.Text = text
	b.AutoButtonColor = false
	b.Parent = Main

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b

	return b
end

local espButton = Button(
	"ESP : " .. (Settings.ESP.Enabled and "ON" or "OFF"),
	UDim2.fromOffset(15, 70)
)

espButton.MouseButton1Click:Connect(function()
	Settings.ESP.Enabled = not Settings.ESP.Enabled
	espButton.Text = "ESP : " .. (Settings.ESP.Enabled and "ON" or "OFF")
end)

local rainbowButton = Button(
	"RAINBOW ESP : ON",
	UDim2.fromOffset(15, 120)
)

rainbowButton.MouseButton1Click:Connect(function()
	Settings.ESP.Rainbow = not Settings.ESP.Rainbow
	rainbowButton.Text =
		"RAINBOW ESP : " ..
		(Settings.ESP.Rainbow and "ON" or "OFF")
end)

local aimButton = Button(
	"AIM ASSIST : OFF",
	UDim2.fromOffset(15, 170)
)

aimButton.MouseButton1Click:Connect(function()
	Settings.Aim.Enabled = not Settings.Aim.Enabled
	aimButton.Text =
		"AIM ASSIST : " ..
		(Settings.Aim.Enabled and "ON" or "OFF")
end)

local modeButton = Button(
	"MODE : " .. string.upper(Settings.Aim.Mode),
	UDim2.fromOffset(15, 220)
)

modeButton.MouseButton1Click:Connect(function()
	if Settings.Aim.Mode == "Hold" then
		Settings.Aim.Mode = "Toggle"
	else
		Settings.Aim.Mode = "Hold"
	end

	modeButton.Text =
		"MODE : " ..
		string.upper(Settings.Aim.Mode)
end)

local targetButton = Button(
	"TARGET : HEAD",
	UDim2.fromOffset(15, 270)
)

targetButton.MouseButton1Click:Connect(function()
	if Settings.Aim.TargetPart == "Head" then
		Settings.Aim.TargetPart = "HumanoidRootPart"
		targetButton.Text = "TARGET : BODY"
	else
		Settings.Aim.TargetPart = "Head"
		targetButton.Text = "TARGET : HEAD"
	end
end)

local fovButton = Button(
	"FOV : " .. Settings.Aim.FOV,
	UDim2.fromOffset(15, 320)
)

fovButton.MouseButton1Click:Connect(function()
	local values = {100, 140, 180, 220, 280}
	local index = table.find(values, Settings.Aim.FOV) or 1
	index = index % #values + 1

	Settings.Aim.FOV = values[index]
	fovButton.Text = "FOV : " .. Settings.Aim.FOV
end)

local aimToggleButton = Instance.new("TextButton")
aimToggleButton.Size = UDim2.fromOffset(135, 42)
aimToggleButton.Position = UDim2.new(1, -160, 1, -80)
aimToggleButton.BackgroundColor3 = Color3.fromRGB(25,28,36)
aimToggleButton.TextColor3 = Color3.new(1,1,1)
aimToggleButton.Text = "AIM : OFF"
aimToggleButton.Font = Enum.Font.GothamBold
aimToggleButton.TextSize = 13
aimToggleButton.Parent = ScreenGui

local aimCorner = Instance.new("UICorner")
aimCorner.CornerRadius = UDim.new(0, 10)
aimCorner.Parent = aimToggleButton

aimToggleButton.MouseButton1Click:Connect(function()
	Settings.Aim.Enabled = not Settings.Aim.Enabled

	aimToggleButton.Text =
		"AIM : " ..
		(Settings.Aim.Enabled and "ON" or "OFF")

	aimButton.Text =
		"AIM ASSIST : " ..
		(Settings.Aim.Enabled and "ON" or "OFF")
end)

local dragging = false
local dragStart
local startPosition

aimToggleButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragStart = input.Position
		startPosition = aimToggleButton.Position

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Position - dragStart

		aimToggleButton.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.KeyCode == Enum.KeyCode.RightControl then
		Main.Visible = not Main.Visible
		aimToggleButton.Visible = Main.Visible
	end
end)
```
