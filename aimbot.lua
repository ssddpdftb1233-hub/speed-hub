```lua
-- Speed UI - LocalScript
-- ضع السكربت داخل StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local NORMAL_SPEED = 16
local speedValue = 50
local enabled = false

--// GUI
local gui = Instance.new("ScreenGui")
gui.Name = "SpeedUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

--// Main Frame
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 260, 0, 180)
frame.Position = UDim2.new(0.5, -130, 0.5, -90)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

--// Title / Drag Area
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
title.Text = "⚡ Speed Controller"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.Parent = frame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 10)
titleCorner.Parent = title

--// Speed Input
local speedBox = Instance.new("TextBox")
speedBox.Size = UDim2.new(0, 210, 0, 38)
speedBox.Position = UDim2.new(0.5, -105, 0, 55)
speedBox.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
speedBox.TextColor3 = Color3.fromRGB(255, 255, 255)
speedBox.PlaceholderText = "Speed"
speedBox.Text = tostring(speedValue)
speedBox.TextSize = 16
speedBox.Font = Enum.Font.Gotham
speedBox.ClearTextOnFocus = false
speedBox.Parent = frame

local boxCorner = Instance.new("UICorner")
boxCorner.CornerRadius = UDim.new(0, 7)
boxCorner.Parent = speedBox

--// Toggle Button
local toggle = Instance.new("TextButton")
toggle.Size = UDim2.new(0, 210, 0, 42)
toggle.Position = UDim2.new(0.5, -105, 0, 105)
toggle.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
toggle.Text = "Speed: OFF"
toggle.TextSize = 17
toggle.Font = Enum.Font.GothamBold
toggle.Parent = frame

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 7)
toggleCorner.Parent = toggle

--// Get Character / Humanoid
local function getHumanoid()
	local character = player.Character or player.CharacterAdded:Wait()
	return character:FindFirstChildOfClass("Humanoid")
end

local function updateSpeed()
	local humanoid = getHumanoid()
	if not humanoid then
		return
	end

	if enabled then
		humanoid.WalkSpeed = speedValue
		toggle.Text = "Speed: ON (" .. speedValue .. ")"
		toggle.BackgroundColor3 = Color3.fromRGB(50, 170, 80)
	else
		humanoid.WalkSpeed = NORMAL_SPEED
		toggle.Text = "Speed: OFF"
		toggle.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
	end
end

--// Toggle Speed
toggle.MouseButton1Click:Connect(function()
	local number = tonumber(speedBox.Text)

	if number then
		speedValue = math.clamp(number, 1, 500)
		speedBox.Text = tostring(speedValue)
	end

	enabled = not enabled
	updateSpeed()
end)

--// Change speed while enabled
speedBox.FocusLost:Connect(function()
	local number = tonumber(speedBox.Text)

	if number then
		speedValue = math.clamp(number, 1, 500)
		speedBox.Text = tostring(speedValue)

		if enabled then
			updateSpeed()
		end
	else
		speedBox.Text = tostring(speedValue)
	end
end)

--// Respawn support
player.CharacterAdded:Connect(function()
	task.wait(0.5)

	if enabled then
		updateSpeed()
	end
end)

--// Right Ctrl = Show / Hide UI
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.RightControl then
		frame.Visible = not frame.Visible
	end
end)

--// Drag UI with mouse
local dragging = false
local dragStart
local startPosition

title.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragStart = input.Position
		startPosition = frame.Position
	end
end)

title.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Position - dragStart

		frame.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end
end)
```
