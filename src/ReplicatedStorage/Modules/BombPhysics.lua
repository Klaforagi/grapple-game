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

-- Specify a trajectory in studs, not an enormous additive speed. This is the
-- desired final velocity, so repeated blasts do not stack launch energy.
function M.Knockback(offset: Vector3, radius: number, gravity: number, height: number, range: number): Vector3
	local distance = offset.Magnitude
	if distance > radius then return Vector3.zero end
	local strength = 1 - 0.3 * math.clamp(distance / math.max(radius, 0.001), 0, 1)
	local g = math.max(gravity, 1)
	local verticalSpeed = math.sqrt(2 * g * math.max(1, height) * strength)
	local flightTime = 2 * verticalSpeed / g
	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	local horizontalRange = math.max(0, range) * math.clamp(distance / math.max(radius, 0.001), 0, 1)
	local sideways = horizontal.Magnitude > 0.001 and horizontal.Unit * (horizontalRange / flightTime) or Vector3.zero
	return sideways + Vector3.new(0, verticalSpeed, 0)
end

-- Pitch away from the blast. Even a perfectly vertical launch needs a rotation
-- axis: equal linear velocities alone preserve a standing pose in free fall.
function M.TumbleVelocity(velocity: Vector3, speed: number): Vector3
	local axis = Vector3.new(velocity.Z, 0, -velocity.X)
	if axis.Magnitude < 0.001 then axis = Vector3.new(1, 0, 0) end
	return axis.Unit * math.clamp(speed, 0, 4)
end

return M
