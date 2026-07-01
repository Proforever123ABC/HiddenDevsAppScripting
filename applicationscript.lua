-- Discord: bhalla123abc
-- Roblox: proforever123abc

-- Roblox Core Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Constants and Player References
local LOCAL_PLAYER = Players.LocalPlayer

-- Colors for visual feedback on parts
local COLOR_SELECTED = Color3.fromRGB(0, 255, 0)    -- Green when selected
local COLOR_HOVERED = Color3.fromRGB(255, 255, 0)   -- Yellow when hovered
local COLOR_DEFAULT = Color3.fromRGB(200, 200, 200) -- Neutral grey

-- EditableObject class with metatable
-- Encapsulates a part and provides transformation methods
local EditableObject = {}
EditableObject.__index = EditableObject

-- Constructor for EditableObject
-- Wraps a Roblox Part, allowing encapsulation of its behaviors
function EditableObject.new(part)
	local self = setmetatable({}, EditableObject)
	self.instance = part
	self.name = part.Name
	return self
end

-- Move the part relative to its current CFrame
-- offset: Vector3 offset to move by
function EditableObject:move(offset)
	-- Apply movement relative to current position
	self.instance.CFrame = self.instance.CFrame * CFrame.new(offset)
end

-- Rotate the part around a local axis by degrees
-- axis: "X", "Y", or "Z"
-- degrees: degrees to rotate by
function EditableObject:rotate(axis, degrees)
	local radians = math.rad(degrees)
	-- Determine which axis to rotate around
	local xRot = (axis == "X") and radians or 0
	local yRot = (axis == "Y") and radians or 0
	local zRot = (axis == "Z") and radians or 0
	local rotationCFrame = CFrame.Angles(xRot, yRot, zRot)

	-- Apply rotation relative to current orientation
	self.instance.CFrame = self.instance.CFrame * rotationCFrame
end

-- Scale the part size smoothly using Tweening
-- multiplier: scale factor (e.g., 1.1 to grow by 10%)
function EditableObject:scale(multiplier)
	local newSize = self.instance.Size * multiplier
	-- Tween the size to provide smooth scaling animation
	local tween = TweenService:Create(self.instance, TweenInfo.new(0.3), {Size = newSize})
	tween:Play()
end

-- Change the color of the part for visual feedback
-- color: Color3 to apply to the part
function EditableObject:highlight(color)
	self.instance.Color = color
end

-- Module-level State

local allObjects = {}          -- Stores all created EditableObjects
local hoveredObject = nil      -- Object currently under the mouse cursor
local selectedObject = nil     -- Currently selected object for transformations
local undoStack = {}           -- Stores past states for Undo
local redoStack = {}           -- Stores states for Redo
local gridSnapEnabled = false  -- Whether to snap movements to integer grid
local infoBillboard = nil      -- BillboardGui displaying selected object info
local objectCounter = 0        -- Unique ID counter for naming objects
local objectsFolder = nil      -- Folder container that owns all spawned parts

-- Current camera, kept up to date in case it ever gets replaced
local currentCamera = workspace.CurrentCamera
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	currentCamera = workspace.CurrentCamera
end)

-- Utility Functions

-- Finds or creates the Folder that holds all spawned objects,
-- so parts don't get dropped loose into workspace
local function getObjectsFolder()
	if objectsFolder and objectsFolder.Parent then
		return objectsFolder
	end

	local existing = workspace:FindFirstChild("EditableObjects")
	if existing then
		objectsFolder = existing
	else
		local folder = Instance.new("Folder")
		folder.Name = "EditableObjects"
		folder.Parent = workspace
		objectsFolder = folder
	end

	return objectsFolder
end

-- Round vector components to nearest integer if grid snap is enabled
local function snapVector(vector)
	if not gridSnapEnabled then
		return vector
	end
	-- Use math.round to snap each component
	return Vector3.new(
		math.round(vector.X),
		math.round(vector.Y),
		math.round(vector.Z)
	)
end

-- Save current state of an object before change, for Undo functionality
-- Clears redo stack because redo history is invalidated after new actions
local function pushUndo(obj)
	if not obj or not obj.instance then return end

	-- Capture essential state: position and size
	local state = {
		instance = obj.instance,
		cframe = obj.instance.CFrame,
		size = obj.instance.Size
	}
	table.insert(undoStack, state)

	-- Reset redo history on new action to maintain linear history
	redoStack = {}
end

-- Restore the last saved state from a stack (undo or redo)
-- fromStack: stack to pop the state from
-- toStack: stack to push current state onto before restoring
local function restoreState(fromStack, toStack)
	local lastState = table.remove(fromStack)
	if not lastState then return end

	local inst = lastState.instance
	if not inst or not inst.Parent then
		-- Instance might have been destroyed; ignore invalid state
		return
	end

	-- Save current state before restoring, enabling redo/undo toggling
	table.insert(toStack, {
		instance = inst,
		cframe = inst.CFrame,
		size = inst.Size
	})

	-- Apply saved position and size
	inst.CFrame = lastState.cframe
	inst.Size = lastState.size
end

-- Assign a unique name to a new part for clarity and debugging
local function assignUniqueName(part)
	objectCounter += 1
	part.Name = "Obj_" .. tostring(objectCounter)
end

-- Create a new anchored part in front of the player and wrap in EditableObject
local function createObject(position)
	local part = Instance.new("Part")
	part.Size = Vector3.new(4, 4, 4)
	part.Anchored = true
	part.Color = COLOR_DEFAULT

	-- Position the part either at given position or above player
	local spawnCFrame
	if position then
		spawnCFrame = CFrame.new(position)
	else
		local character = LOCAL_PLAYER.Character
		local basePos = character and character:GetPivot().Position or Vector3.new(0, 5, 0)
		spawnCFrame = CFrame.new(basePos + Vector3.new(0, 5, 0))
	end
	part.CFrame = spawnCFrame

	assignUniqueName(part)
	part.Parent = getObjectsFolder()

	local obj = EditableObject.new(part)
	table.insert(allObjects, obj)
	return obj
end

-- Update or create the BillboardGui displaying selected object info
local function updateInfoGui()
	if infoBillboard then
		infoBillboard:Destroy()
		infoBillboard = nil
	end

	if not selectedObject then return end

	local gui = Instance.new("BillboardGui")
	gui.Adornee = selectedObject.instance
	gui.Size = UDim2.new(0, 200, 0, 60)
	gui.StudsOffset = Vector3.new(0, selectedObject.instance.Size.Y + 1.5, 0)
	gui.AlwaysOnTop = true

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.Code
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Text = selectedObject.name .. "\n" .. tostring(selectedObject.instance.Size)
	label.Parent = gui

	gui.Parent = selectedObject.instance
	infoBillboard = gui
end

-- Clear previous selection and highlight, then select and highlight the new object
local function selectObject(obj)
	if selectedObject and selectedObject ~= obj then
		selectedObject:highlight(COLOR_DEFAULT)
	end
	selectedObject = obj
	if obj then
		obj:highlight(COLOR_SELECTED)
	end

	updateInfoGui()
end

-- Delete the currently selected object and save state for Undo
local function deleteSelectedObject()
	if not selectedObject then return end

	pushUndo(selectedObject)
	selectedObject.instance:Destroy()

	-- Remove from allObjects list
	for i, obj in ipairs(allObjects) do
		if obj == selectedObject then
			table.remove(allObjects, i)
			break
		end
	end

	selectedObject = nil
	updateInfoGui()
end

-- Duplicate selected object by cloning its part with slight offset
local function duplicateSelectedObject()
	if not selectedObject then return end

	local clonePart = selectedObject.instance:Clone()
	clonePart.CFrame = clonePart.CFrame * CFrame.new(2, 0, 2) -- Offset to avoid overlap
	assignUniqueName(clonePart)
	clonePart.Parent = getObjectsFolder()

	local cloneObj = EditableObject.new(clonePart)
	table.insert(allObjects, cloneObj)

	selectObject(cloneObj)
end

-- Detects which EditableObject the mouse is currently over and manages hover state
local lastMouseLocation = nil
local lastCameraCFrame = nil

local function refreshHover()
	if not currentCamera then return end

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = currentCamera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	-- Ignore the player's own character so it can't be picked as a target
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = LOCAL_PLAYER.Character and {LOCAL_PLAYER.Character} or {}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true

	local raycastResult = workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)
	local targetPart = raycastResult and raycastResult.Instance or nil

	-- Find EditableObject for the hit part
	local foundObj = nil
	if targetPart and targetPart:IsA("Part") then
		for _, obj in ipairs(allObjects) do
			if obj.instance == targetPart then
				foundObj = obj
				break
			end
		end
	end

	-- Update hover states only if changed
	if hoveredObject ~= foundObj then
		if hoveredObject and hoveredObject ~= selectedObject then
			hoveredObject:highlight(COLOR_DEFAULT)
		end
		hoveredObject = foundObj
		if hoveredObject and hoveredObject ~= selectedObject then
			hoveredObject:highlight(COLOR_HOVERED)
		end
	end
end

-- Only re-checks hover when the mouse or camera has actually moved,
-- instead of raycasting every single frame
local function updateHover()
	local mouseLocation = UserInputService:GetMouseLocation()
	local cameraCFrame = currentCamera and currentCamera.CFrame or nil

	local mouseMoved = lastMouseLocation == nil or mouseLocation ~= lastMouseLocation
	local cameraMoved = cameraCFrame ~= lastCameraCFrame

	if mouseMoved or cameraMoved then
		lastMouseLocation = mouseLocation
		lastCameraCFrame = cameraCFrame
		refreshHover()
	end
end

-- Movement offsets mapped to keys for intuitive WASD + PageUp/PageDown controls
local MOVE_KEYS = {
	[Enum.KeyCode.W] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.S] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.D] = Vector3.new(1, 0, 0),
	[Enum.KeyCode.PageUp] = Vector3.new(0, 1, 0),
	[Enum.KeyCode.PageDown] = Vector3.new(0, -1, 0)
}

-- Rotation keys mapped to axis and degrees for quick rotation shortcuts
local ROTATE_KEYS = {
	[Enum.KeyCode.Q] = {"Y", -15},
	[Enum.KeyCode.R] = {"Y", 15},
	[Enum.KeyCode.T] = {"X", 15},
	[Enum.KeyCode.Z] = {"Z", 15}
}

-- Handle keyboard input: creating, selecting, deleting, transforming objects
local function handleKeyInput(key)
	-- Early returns reduce nested conditionals and improve readability

	-- Create new object at player position
	if key == Enum.KeyCode.F then
		local newObj = createObject()
		selectObject(newObj)
		return
	end

	-- Select currently hovered object
	if key == Enum.KeyCode.E and hoveredObject then
		selectObject(hoveredObject)
		return
	end

	-- Delete selected object
	if key == Enum.KeyCode.Backspace then
		deleteSelectedObject()
		return
	end

	-- Toggle grid snap on/off
	if key == Enum.KeyCode.G then
		gridSnapEnabled = not gridSnapEnabled
		print("Grid Snap is now", gridSnapEnabled and "ENABLED" or "DISABLED")
		return
	end

	-- Undo last action
	if key == Enum.KeyCode.U then
		restoreState(undoStack, redoStack)
		print("Undo performed")
		return
	end

	-- Redo last undone action
	if key == Enum.KeyCode.Y then
		restoreState(redoStack, undoStack)
		print("Redo performed")
		return
	end

	-- Duplicate selected object
	if key == Enum.KeyCode.C then
		duplicateSelectedObject()
		return
	end

	-- If no object is selected, no further input applies
	if not selectedObject then return end

	-- Save state before transformations for undo
	pushUndo(selectedObject)

	-- Check for movement keys and apply movement if matched
	local moveVector = MOVE_KEYS[key]
	if moveVector then
		selectedObject:move(snapVector(moveVector))
		return
	end

	-- Check for rotation keys and apply rotation if matched
	local rotateParams = ROTATE_KEYS[key]
	if rotateParams then
		local axis, degrees = unpack(rotateParams)
		selectedObject:rotate(axis, degrees)
		return
	end

	-- Handle scaling with +/- keys
	if key == Enum.KeyCode.Equals then
		selectedObject:scale(1.1) -- Increase size by 10%
	elseif key == Enum.KeyCode.Minus then
		selectedObject:scale(0.9) -- Decrease size by 10%
	end
end

-- Event Connections

-- Listen to user keyboard input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		handleKeyInput(input.KeyCode)
	end
end)

-- Check hover state every frame
RunService.Heartbeat:Connect(updateHover)

-- Print control instructions on script load for user clarity
print([[
EditableObject Controls:
  F       - Create new object in front of player
  E       - Select object under mouse cursor
  Backspace - Delete selected object
  G       - Toggle grid snapping (moves snap to whole units)
  U       - Undo last action
  Y       - Redo last undone action
  C       - Duplicate selected object
  W/A/S/D - Move selected object along XZ plane
  PageUp  - Move selected object up
  PageDown- Move selected object down
  Q/R     - Rotate selected object around Y-axis (-15/+15 degrees)
  T       - Rotate selected object around X-axis (+15 degrees)
  Z       - Rotate selected object around Z-axis (+15 degrees)
  =       - Scale selected object up by 10%
  -       - Scale selected object down by 10%
]])
