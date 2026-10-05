local M = {}

function M.ThrowVelocity(offset: Vector3, gravity: number, speed: number, arcHeight: number): Vector3
	if gravity <= 0 then
		return offset.Magnitude > 0.001 and offset.Unit * speed or Vector3.new(0, speed, 0)
	end
	local apex = math.max(0, offset.Y) + math.max(0.1, arcHeight)
	local riseTime = math.sqrt(2 * apex / gravity)
	local flightTime = riseTime + math.sqrt(2 * (apex - offset.Y) / gravity)
	local velocity = Vector3.new(offset.X / flightTime, gravity * riseTime, offset.Z / flightTime)
	if velocity.Magnitude <= speed then return velocity end
	-- Beyond the accurate lob's reach, throw a full-speed 45-degree arc in
	-- that horizontal direction. Gravity still determines where it lands.
	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	if horizontal.Magnitude < 0.001 then return Vector3.new(0, speed, 0) end
	return (horizontal.Unit + Vector3.new(0, 1, 0)) * (speed / math.sqrt(2))
end

-- Off-center blasts keep their horizontal punch while the launch angle falls
-- naturally with distance. Directly underneath always launches straight up.
function M.Knockback(offset: Vector3, radius: number, speed: number): Vector3
	local distance = offset.Magnitude
	if distance > radius then return Vector3.zero end
	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	local direction = Vector3.new(offset.X, math.max(offset.Y, 0.75), offset.Z).Unit
	if horizontal.Magnitude < 0.001 then direction = Vector3.new(0, 1, 0) end
	local strength = speed * (1 - 0.35 * math.clamp(distance / radius, 0, 1))
	return direction * strength
end

return M
