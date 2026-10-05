local a=game:GetService("Players")
local b=game:GetService("UserInputService")
local c=a.LocalPlayer

local d=Instance.new("ScreenGui")
d.Name="SpeedUI"
d.ResetOnSpawn=false
d.Parent=c:WaitForChild("PlayerGui")

local e=Instance.new("Frame")
e.Size=UDim2.new(0,250,0,180)
e.Position=UDim2.new(0.5,-125,0.5,-90)
e.BackgroundColor3=Color3.fromRGB(35,35,35)
e.Active=true
e.Parent=d

local f=Instance.new("TextLabel")
f.Size=UDim2.new(1,0,0,30)
f.Text="Speed Changer"
f.TextColor3=Color3.new(1,1,1)
f.BackgroundTransparency=1
f.Parent=e

local g=Instance.new("TextBox")
g.Size=UDim2.new(0.8,0,0,35)
g.Position=UDim2.new(0.1,0,0.3,0)
g.PlaceholderText="Enter Speed"
g.Text=""
g.Parent=e

local h=Instance.new("TextButton")
h.Size=UDim2.new(0.8,0,0,35)
h.Position=UDim2.new(0.1,0,0.55,0)
h.Text="Apply Speed"
h.Parent=e

local i=Instance.new("TextButton")
i.Size=UDim2.new(0.8,0,0,35)
i.Position=UDim2.new(0.1,0,0.78,0)
i.Text="Reset (16)"
i.Parent=e

local function j(k)
	local l=c.Character
	if l then
		local m=l:FindFirstChildOfClass("Humanoid")
		if m then
			m.WalkSpeed=k
		end
	end
end

h.MouseButton1Click:Connect(function()
	local k=tonumber(g.Text)
	if k then
		j(k)
	end
end)

i.MouseButton1Click:Connect(function()
	j(16)
end)

-- Drag UI with mouse
local n=false
local o
local q
local r

e.InputBegan:Connect(function(t)
	if t.UserInputType==Enum.UserInputType.MouseButton1 then
		n=true
		o=t.Position
		q=e.Position
	end
end)

e.InputChanged:Connect(function(t)
	if t.UserInputType==Enum.UserInputType.MouseMovement then
		r=t
	end
end)

b.InputChanged:Connect(function(t)
	if n and t==r then
		local v=t.Position-o
		e.Position=UDim2.new(
			q.X.Scale,
			q.X.Offset+v.X,
			q.Y.Scale,
			q.Y.Offset+v.Y
		)
	end
end)

b.InputEnded:Connect(function(t)
	if t.UserInputType==Enum.UserInputType.MouseButton1 then
		n=false
	end
end)

b.InputBegan:Connect(function(k,l)
	if l then return end
	if k.KeyCode==Enum.KeyCode.RightControl then
		e.Visible=not e.Visible
	end
end)
