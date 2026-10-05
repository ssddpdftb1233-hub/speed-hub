local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SpeedUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = player:WaitForChild("PlayerGui")

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 250, 0, 180)
Frame.Position = UDim2.new(0.5, -125, 0.5, -90)
Frame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
Frame.Parent = ScreenGui

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 30)
Title.Text = "Speed Changer"
Title.TextColor3 = Color3.new(1, 1, 1)
Title.BackgroundTransparency = 1
Title.Parent = Frame

local TextBox = Instance.new("TextBox")
TextBox.Size = UDim2.new(0.8, 0, 0, 35)
TextBox.Position = UDim2.new(0.1, 0, 0.3, 0)
TextBox.PlaceholderText = "Enter Speed"
TextBox.Text = ""
TextBox.Parent = Frame

local ApplyButton = Instance.new("TextButton")
ApplyButton.Size = UDim2.new(0.8, 0, 0, 35)
ApplyButton.Position = UDim2.new(0.1, 0, 0.55, 0)
ApplyButton.Text = "Apply Speed"
ApplyButton.Parent = Frame

local ResetButton = Instance.new("TextButton")
ResetButton.Size = UDim2.new(0.8, 0, 0, 35)
ResetButton.Position = UDim2.new(0.1, 0, 0.78, 0)
ResetButton.Text = "Reset (16)"
ResetButton.Parent = Frame

local function SetSpeed(speed)
    local character = player.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = speed
        end
    end
end

ApplyButton.MouseButton1Click:Connect(function()
    local speed = tonumber(TextBox.Text)
    if speed then
        SetSpeed(speed)
    end
end)

ResetButton.MouseButton1Click:Connect(function()
    SetSpeed(16)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        Frame.Visible = not Frame.Visible
    end
end)
