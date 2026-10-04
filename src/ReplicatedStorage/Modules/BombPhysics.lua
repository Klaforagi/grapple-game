local M = {}

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
