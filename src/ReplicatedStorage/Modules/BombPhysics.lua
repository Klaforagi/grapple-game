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

-- Give connected assemblies a compatible rotating velocity field. Spinning
-- the torso one way and every limb the other lets the joints cancel the motion.
function M.LaunchMotion(bodies, velocity: Vector3, tumbleSpeed: number, limbKickSpeed: number)
	local mass, center = 0, Vector3.zero
	for _, body in ipairs(bodies) do
		mass += body.mass
		center += body.position * body.mass
	end
	if mass <= 0 then return end
	center /= mass
	local omega = M.TumbleVelocity(velocity, tumbleSpeed)
	local kickSpeed = math.clamp(limbKickSpeed, 0, 6)
	local meanKick = Vector3.zero
	for _, body in ipairs(bodies) do
		local r = body.position - center
		local radial = r.Magnitude > 0.01 and r.Unit or Vector3.zero
		-- omega cross r: limbs travel around the same center as the torso turns.
		local orbital = Vector3.new(omega.Y * r.Z - omega.Z * r.Y,
			omega.Z * r.X - omega.X * r.Z, omega.X * r.Y - omega.Y * r.X)
		body.kick = orbital + radial * kickSpeed
		body.angular = omega + (body.isRoot and Vector3.zero or radial * math.min(kickSpeed * 0.4, 1.2))
		meanKick += body.kick * body.mass
	end
	meanKick /= mass
	local maximumKick = 0
	for _, body in ipairs(bodies) do
		body.kick -= meanKick
		maximumKick = math.max(maximumKick, body.kick.Magnitude)
	end
	-- One scale preserves zero net extra impulse, including on differently
	-- sized avatars. The configured trajectory remains the body's COM trajectory.
	local scale = maximumKick > 12 and 12 / maximumKick or 1
	for _, body in ipairs(bodies) do
		body.velocity = velocity + body.kick * scale
		body.angular *= scale
		if body.angular.Magnitude > 5 then body.angular = body.angular.Unit * 5 end
	end
end

return M
