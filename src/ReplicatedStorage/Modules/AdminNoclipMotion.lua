-- Pure flight math for admin noclip. The client applies it. Rank and coin
-- upgrades do not change these speeds.
local Motion = {}

Motion.Cruise = 80
Motion.Fast = 200

-- Vector3's type is "vector", not "table". Treating only tables as coordinates
-- reads the camera and the body as the origin.
local function component(v, key)
	if v == nil then return 0 end
	local value = v[key]
	if type(value) ~= "number" then return 0 end
	return value
end

function Motion.SpeedFor(fast)
	return fast and Motion.Fast or Motion.Cruise
end

-- keys: w/a/s/d along the camera, up/down in world space. The result is a unit
-- direction, or zeros when nothing is held.
function Motion.Direction(keys, look, right)
	keys = type(keys) == "table" and keys or {}
	local forward = (keys.w and 1 or 0) - (keys.s and 1 or 0)
	local strafe = (keys.d and 1 or 0) - (keys.a and 1 or 0)
	local lift = (keys.up and 1 or 0) - (keys.down and 1 or 0)
	local x = component(look, "X") * forward + component(right, "X") * strafe
	local y = component(look, "Y") * forward + component(right, "Y") * strafe + lift
	local z = component(look, "Z") * forward + component(right, "Z") * strafe
	local mag = math.sqrt(x * x + y * y + z * z)
	if mag < 1e-4 then return 0, 0, 0 end
	return x / mag, y / mag, z / mag
end

-- Horizontal camera direction, used so the body yaws with the mouse. Nil when
-- the camera looks straight up or down.
function Motion.FlatLook(look)
	local x, z = component(look, "X"), component(look, "Z")
	local mag = math.sqrt(x * x + z * z)
	if mag < 1e-4 then return nil, nil end
	return x / mag, z / mag
end

function Motion.Move(position, direction, speed, dt)
	dt = math.clamp(dt or 0, 0, 0.1)
	speed = speed or 0
	return {
		X = component(position, "X") + component(direction, "X") * speed * dt,
		Y = component(position, "Y") + component(direction, "Y") * speed * dt,
		Z = component(position, "Z") + component(direction, "Z") * speed * dt,
	}
end

return Motion
