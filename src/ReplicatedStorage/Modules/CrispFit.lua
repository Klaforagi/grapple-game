-- UIScale draws the tree into a texture and then shrinks it, so phone text goes soft.
-- This keeps the same on-screen size by baking that factor into offsets and text sizes
-- and leaving UIScale at 1, which lets glyphs rasterize at the size they are shown.
-- A GuiObject's own UIScale does not move that object, so the root Position stays put.
-- Decorative UIScales on children are left alone. Their children are still baked by the
-- window factor, so the extra scale remains a local multiplier on top of the fit.

local CrispFit = {}

local function near(a, b)
	return math.abs(a - b) < 0.02
end

local function sameUDim(a, b)
	return math.abs(a.Scale - b.Scale) < 0.0001 and near(a.Offset, b.Offset)
end

local function sameUDim2(a, b)
	return sameUDim(a.X, b.X) and sameUDim(a.Y, b.Y)
end

local function scaleUDim(value, factor)
	return UDim.new(value.Scale, value.Offset * factor)
end

local function scaleUDim2(value, factor)
	return UDim2.new(value.X.Scale, value.X.Offset * factor, value.Y.Scale, value.Y.Offset * factor)
end

local function scaleText(value, factor)
	return math.max(1, math.floor(value * factor + 0.5))
end

local function numberField(instance, name)
	return {
		name = name,
		get = function() return instance[name] end,
		set = function(value) instance[name] = value end,
		scale = function(value, factor) return value * factor end,
		same = near,
	}
end

local function textField(instance, name)
	return {
		name = name,
		get = function() return instance[name] end,
		set = function(value) instance[name] = value end,
		scale = scaleText,
		same = near,
	}
end

local function udimField(instance, name)
	return {
		name = name,
		get = function() return instance[name] end,
		set = function(value) instance[name] = value end,
		scale = scaleUDim,
		same = sameUDim,
	}
end

local function udim2Field(instance, name)
	return {
		name = name,
		get = function() return instance[name] end,
		set = function(value) instance[name] = value end,
		scale = scaleUDim2,
		same = sameUDim2,
	}
end

local function fieldsFor(instance, isRoot)
	local fields = {}
	if instance:IsA("GuiObject") then
		table.insert(fields, udim2Field(instance, "Size"))
		if not isRoot then table.insert(fields, udim2Field(instance, "Position")) end
		table.insert(fields, numberField(instance, "BorderSizePixel"))
		if instance:IsA("ScrollingFrame") then
			table.insert(fields, numberField(instance, "ScrollBarThickness"))
		end
		local mirror = instance:IsA("TextLabel") and instance.Name == "Label"
			and instance.Parent and instance.Parent:IsA("TextButton")
		if not mirror and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) then
			table.insert(fields, textField(instance, "TextSize"))
		end
	elseif instance:IsA("UIPadding") then
		for _, name in ipairs({"PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight"}) do
			table.insert(fields, udimField(instance, name))
		end
	elseif instance:IsA("UICorner") then
		table.insert(fields, udimField(instance, "CornerRadius"))
	elseif instance:IsA("UIStroke") then
		table.insert(fields, numberField(instance, "Thickness"))
	elseif instance:IsA("UIListLayout") then
		table.insert(fields, udimField(instance, "Padding"))
	elseif instance:IsA("UIGridLayout") then
		table.insert(fields, udim2Field(instance, "CellSize"))
		table.insert(fields, udim2Field(instance, "CellPadding"))
	elseif instance:IsA("UITextSizeConstraint") then
		table.insert(fields, textField(instance, "MinTextSize"))
		table.insert(fields, textField(instance, "MaxTextSize"))
	end
	return fields
end

function CrispFit.attach(root, scaleObject)
	local records = {}
	local factor = 1
	local busy = 0

	local function write(record)
		for _, field in ipairs(record.fields) do
			local scaled = field.scale(record.original[field.name], factor)
			record.applied[field.name] = scaled
			field.set(scaled)
		end
	end

	local function watch(instance, isRoot)
		if records[instance] or instance:IsA("UIScale") then return end
		if instance:GetAttribute("CrispIgnore") then return end
		local fields = fieldsFor(instance, isRoot)
		if #fields == 0 then return end
		local record = {fields = fields, original = {}, applied = {}}
		records[instance] = record
		for _, field in ipairs(fields) do
			local value = field.get()
			record.original[field.name] = value
			record.applied[field.name] = value
			instance:GetPropertyChangedSignal(field.name):Connect(function()
				if busy > 0 then return end
				local now = field.get()
				local applied = record.applied[field.name]
				if applied ~= nil and field.same(now, applied) then return end
				record.original[field.name] = now
				if math.abs(factor - 1) < 0.0005 then
					record.applied[field.name] = now
					return
				end
				busy += 1
				local scaled = field.scale(now, factor)
				record.applied[field.name] = scaled
				field.set(scaled)
				busy -= 1
			end)
		end
		if math.abs(factor - 1) >= 0.0005 then
			busy += 1
			write(record)
			busy -= 1
		end
		instance.Destroying:Connect(function()
			records[instance] = nil
		end)
	end

	watch(root, true)
	for _, descendant in ipairs(root:GetDescendants()) do
		watch(descendant, false)
	end
	root.DescendantAdded:Connect(function(descendant)
		watch(descendant, false)
	end)

	return function(nextFactor)
		if type(nextFactor) ~= "number" or nextFactor ~= nextFactor or nextFactor <= 0 then return end
		if scaleObject then
			scaleObject.Scale = 1
			scaleObject:SetAttribute("CrispFactor", nextFactor)
		end
		if math.abs(nextFactor - factor) < 0.0005 then return end
		factor = nextFactor
		busy += 1
		for _, record in pairs(records) do
			write(record)
		end
		busy -= 1
	end
end

return CrispFit
