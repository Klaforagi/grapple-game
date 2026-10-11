return function(source)
	local credit = assert(loadstring(source))()

	local function expect(actual, expected, label)
		assert(actual == expected, label .. " expected " .. tostring(expected) .. " got " .. tostring(actual))
	end

	local function humanoid(attrs)
		local self = {attributes = attrs or {}}
		function self:GetAttribute(key) return self.attributes[key] end
		function self:SetAttribute(key, value) self.attributes[key] = value end
		return self
	end

	expect(credit.LavaWindow, 20, "lava window")
	expect(credit.VoidWindow, 5, "void window")

	local lines = {
		Lava = {
			"{Killer} gave {Victim} a lava bath.",
			"{Killer} cooked {Victim} alive.",
			"{Killer} turned {Victim} into ashes.",
			"{Killer} sent {Victim} into the lava.",
			"{Killer} melted {Victim}.",
			"{Killer} turned up the heat on {Victim}.",
			"{Killer} served {Victim} extra crispy.",
			"{Killer} made {Victim} into BBQ.",
			"{Killer} threw {Victim} into the furnace.",
			"{Killer} made sure {Victim} couldn't handle the heat.",
		},
		Void = {
			"{Killer} sent {Victim} flying.",
			"{Killer} threw {Victim} into the void.",
			"{Killer} introduced {Victim} to gravity.",
			"{Killer} sent {Victim} on a one-way trip.",
			"{Killer} launched {Victim} into oblivion.",
			"{Killer} helped {Victim} discover the edge of the world.",
			"{Killer} gave {Victim} flying lessons.",
			"{Killer} sent {Victim} sightseeing.",
			"{Killer} removed {Victim} from the map.",
			"{Killer} made {Victim} take the express route down.",
		},
		Freeze = {
			"{Killer} turned {Victim} into a popsicle.",
			"{Killer} put {Victim} on ice.",
			"{Killer} froze {Victim} solid.",
			"{Killer} gave {Victim} the cold shoulder.",
			"{Killer} sent {Victim} into cryosleep.",
			"{Killer} made {Victim} chill out.",
			"{Killer} left {Victim} out in the cold.",
			"{Killer} gave {Victim} a permanent brain freeze.",
			"{Killer} added {Victim} to the frozen collection.",
			"{Killer} put {Victim} in cold storage.",
		},
		Crusher = {
			"{Killer} turned {Victim} into a pancake.",
			"{Killer} flattened {Victim}.",
			"{Killer} crushed {Victim}.",
			"{Killer} put {Victim} under pressure.",
			"{Killer} squished {Victim}.",
			"{Killer} made {Victim} two-dimensional.",
			"{Killer} pressed {Victim} into oblivion.",
			"{Killer} compressed {Victim} into a smaller package.",
			"{Killer} gave {Victim} a crushing defeat.",
			"{Killer} made {Victim} fit into tight spaces.",
		},
	}
	local voidPush = {
		"{Killer} gave {Victim} a friendly shove.",
		"{Killer} helped {Victim} find the exit.",
		"{Killer} told {Victim} to watch their step.",
		"{Killer} gave {Victim} a little encouragement.",
		"{Killer} decided {Victim} needed some fresh air.",
		"{Killer} gave {Victim} a helping hand.",
		"{Killer} showed {Victim} the shortcut.",
		"{Killer} gave {Victim} a push in the right direction.",
		"{Killer} reminded {Victim} that gravity exists.",
		"{Killer} suggested {Victim} take a hike.",
		"{Killer} helped {Victim} overcome their fear of heights.",
		"{Killer} gave {Victim} some personal space.",
		"{Killer} escorted {Victim} off the premises.",
		"{Killer} helped {Victim} take their next big step.",
		"{Killer} thought {Victim} looked better down there.",
		"{Killer} sent {Victim} to explore the bottom of the map.",
		"{Killer} insisted {Victim} go first.",
		"{Killer} showed {Victim} where they belong.",
		"{Killer} decided {Victim} had overstayed their welcome.",
	}
	local voidBomb = {
		"{Killer} blasted {Victim} into the void.",
		"{Killer} blew {Victim} off the map.",
		"{Killer} sent {Victim} flying with a bang.",
		"{Killer} gave {Victim} an explosive exit.",
		"{Killer} launched {Victim} into oblivion.",
		"{Killer} gave {Victim} a one-way flight.",
		"{Killer} sent {Victim} out with a bang.",
		"{Killer} turned {Victim} into a human cannonball.",
		"{Killer} made {Victim} go out with a boom.",
		"{Killer} gave {Victim} an unexpected blastoff.",
		"{Killer} made {Victim} disappear with a bang.",
		"{Killer} blew {Victim} into next week.",
		"{Killer} gave {Victim} a blast they won't forget.",
	}
	expect(#credit.Lines.VoidPush, #voidPush, "push void count")
	expect(#credit.Lines.VoidBomb, #voidBomb, "bomb void count")
	for index, line in ipairs(voidPush) do
		expect(credit.Lines.VoidPush[index], line, "push void line " .. index)
	end
	for index, line in ipairs(voidBomb) do
		expect(credit.Lines.VoidBomb[index], line, "bomb void line " .. index)
	end
	expect(credit.FeedKey("Void", "Push"), "VoidPush", "push void feed")
	expect(credit.FeedKey("Void", "Bomb"), "VoidBomb", "bomb void feed")
	expect(credit.FeedKey("Void", nil), "Void", "grapple void feed")
	expect(credit.FeedKey("Lava", "Push"), "Lava", "push lava feed")
	local soloLines = {
		Lava = {
			"{Player} took a lava bath",
			"{Victim} couldn't handle the heat.",
			"{Victim} is extra crispy.",
			"{Victim} forgot lava was hot.",
			"{Victim} is having a meltdown.",
			"{Victim} is well done.",
			"{Victim} took a dip in the wrong pool.",
			"{Victim} is feeling a little warm.",
			"{Victim} is having a bad spa day.",
		},
		Void = {
			"{Player} is still falling",
			"{Victim} forgot how to fly.",
			"{Victim} discovered gravity.",
			"{Victim} missed a step.",
			"{Victim} went sightseeing.",
			"{Victim} forgot where the floor was.",
			"{Victim} took a leap of faith.",
		},
		Crusher = {
			"{Player} became a pancake",
			"{Victim} got a little too comfortable.",
			"{Victim} couldn't handle the pressure.",
			"{Victim} made a crushing mistake.",
			"{Victim} is feeling a little flat.",
			"{Victim} volunteered for a pressure test.",
			"{Victim} found out what the crusher does.",
			"{Victim} tried to become two-dimensional.",
			"{Victim} decided to flatten themselves.",
			"{Victim} became one with the floor.",
		},
	}
	for cause, expected in pairs(soloLines) do
		assert(#credit.SoloLines[cause] == #expected, cause .. " solo count")
		for index, line in ipairs(expected) do
			expect(credit.SoloLines[cause][index], line, cause .. " solo line " .. index)
		end
	end
	for cause, expected in pairs(lines) do
		assert(#credit.Lines[cause] == 10, cause .. " needs 10 feed lines")
		for index, line in ipairs(expected) do
			expect(credit.Lines[cause][index], line, cause .. " line " .. index)
			assert(string.find(line, "{Killer}", 1, true) and string.find(line, "{Victim}", 1, true),
				cause .. " line " .. index .. " is missing a name")
		end
	end

	expect(credit.Plain("{Killer} melted {Victim}.", "Ann", "Bob"), "Ann melted Bob.", "plain feed text")
	expect(credit.Plain("{Killer} melted {Victim}.", "", "Bob"), "Player melted Bob.", "blank killer name")
	expect(credit.Plain("{Killer} melted {Victim}.", "Ann\n", "Bob"), "Ann melted Bob.", "name kept a newline")
	local rich = credit.Format("{Killer} melted {Victim}.", "A%B", "<Vic>")
	assert(string.find(rich, "A%B", 1, true), "percent in a name was eaten")
	assert(string.find(rich, "&lt;Vic&gt;", 1, true), "rich text name was not escaped")
	assert(not string.find(rich, "<Vic>", 1, true), "raw markup survived in a name")
	assert(string.find(rich, "#FFD68C", 1, true) and string.find(rich, "#FFFFFF", 1, true), "names lost their colors")

	local grappler, victim = 11, 22
	local body = humanoid()
	assert(credit.Resolve(victim, body, 0) == nil, "unmarked death was credited")
	body:SetAttribute("DeathCause", "Lava")
	local lavaSolo = credit.Resolve(victim, body, 50)
	assert(lavaSolo and lavaSolo.solo and lavaSolo.show and not lavaSolo.count and lavaSolo.killerId == victim,
		"lava suicide was stored or hidden")
	body:SetAttribute("DeathCause", "Void")
	local voidSolo = credit.Resolve(victim, body, 50)
	assert(voidSolo and voidSolo.solo and voidSolo.show and not voidSolo.count, "void suicide was stored or hidden")

	credit.NoteAttach(body, grappler, "Ann")
	assert(credit.IsActive(body, grappler), "attach did not record the grapple")
	body:SetAttribute("DeathCause", "Lava")
	local held = credit.Resolve(victim, body, 5000)
	assert(held and held.killerId == grappler and held.killerName == "Ann" and held.count and held.show,
		"a grapple that is still on was outside the lava window")
	body:SetAttribute("DeathCause", "Reset")
	assert(credit.Resolve(victim, body, 5000) == nil, "reset during a grapple was credited")

	credit.NoteRelease(body, grappler, 100)
	assert(not credit.IsActive(body), "release left the grapple active")
	body:SetAttribute("DeathCause", "Lava")
	assert(credit.Resolve(victim, body, 120).killerId == grappler, "lava missed the 20 second boundary")
	local lateLava = credit.Resolve(victim, body, 120.01)
	assert(lateLava and lateLava.solo and not lateLava.count and lateLava.killerId == victim, "lava stayed open after 20 seconds")
	body:SetAttribute("DeathCause", "Void")
	assert(credit.Resolve(victim, body, 105).killerId == grappler, "void missed the 5 second boundary")
	local lateVoid = credit.Resolve(victim, body, 105.01)
	assert(lateVoid and lateVoid.solo and not lateVoid.count, "void used the lava window")

	local replaced = humanoid()
	credit.NoteAttach(replaced, grappler, "Ann")
	credit.NoteAttach(replaced, 33, "Cyd")
	credit.NoteRelease(replaced, grappler, 10)
	assert(credit.IsActive(replaced, 33), "the previous grappler cleared the new tether")
	replaced:SetAttribute("DeathCause", "Lava")
	expect(credit.Resolve(victim, replaced, 40).killerId, 33, "older grappler")
	credit.NoteRelease(replaced, 33, 50)
	assert(credit.Resolve(victim, replaced, 70).killerId == 33, "lava closed before 20 seconds from release")
	local replacedLate = credit.Resolve(victim, replaced, 70.01)
	assert(replacedLate and replacedLate.solo and not replacedLate.count, "lava stayed open after 20 seconds from release")

	local frozen = humanoid({DeathCause = "Freeze", DeathFreezer = 44})
	credit.NoteAttach(frozen, grappler, "Ann")
	credit.NoteRelease(frozen, grappler, 0)
	local freeze = credit.Resolve(victim, frozen, 1000)
	assert(freeze and freeze.killerId == 44 and freeze.count and freeze.show, "freeze used the grapple window")
	frozen:SetAttribute("DeathFreezer", victim)
	assert(credit.Resolve(victim, frozen, 1000) == nil, "self freeze was credited")

	local crushed = humanoid({DeathCause = "Crusher", DeathPuller = 55})
	local smash = credit.Resolve(victim, crushed, 0)
	assert(smash and smash.killerId == 55 and smash.count and smash.show, "lever puller was not credited")
	crushed:SetAttribute("DeathGrappler", 66)
	expect(credit.Resolve(victim, crushed, 0).killerId, 66, "current grappler lost to the lever")
	crushed:SetAttribute("DeathGrappler", nil)
	crushed:SetAttribute("DeathPuller", victim)
	local selfSmash = credit.Resolve(victim, crushed, 0)
	assert(selfSmash and selfSmash.solo and selfSmash.show and not selfSmash.count, "self crush was stored or hidden")
	crushed:SetAttribute("DeathGrappler", 66)
	local saved = credit.Resolve(victim, crushed, 0)
	assert(saved and saved.killerId == 66 and saved.count and saved.show, "grappler lost a self-pulled crusher")

	local queuedBody = humanoid({DeathCause = "Lava"})
	local queuedPlayer = {UserId = victim, Name = "Bob"}
	credit.NoteAttach(queuedBody, grappler, "Ann")
	local queued = credit.Report(queuedPlayer, queuedBody, 1)
	assert(queued and queued.count, "queued lava kill was dropped")
	expect(queuedBody:GetAttribute("DeathCause"), nil, "reported cause")
	local delivered = {}
	credit.SetListener(function(result)
		delivered[#delivered + 1] = result
	end)
	expect(#delivered, 1, "queued kill delivery")
	expect(delivered[1].killerId, grappler, "queued killer")
	expect(delivered[1].victimId, victim, "queued victim")

	local heard = 0
	credit.SetListener(function() heard += 1 end)
	local reported = humanoid({DeathCause = "Void"})
	credit.NoteAttach(reported, grappler, "Ann")
	credit.NoteRelease(reported, grappler, 10)
	local player = {UserId = victim}
	assert(credit.Report(player, reported, 12).cause == "Void", "void report missed")
	assert(credit.Report(player, reported, 12) == nil, "the same death was reported twice")
	expect(heard, 1, "kill listener")

	local bombed = humanoid()
	credit.NoteHit(bombed, 77, "Bea", 10, "Bomb")
	bombed:SetAttribute("DeathCause", "Lava")
	local bombKill = credit.Resolve(victim, bombed, 30)
	assert(bombKill and bombKill.killerId == 77 and bombKill.killerName == "Bea" and bombKill.count,
		"bomb missed the 20 second lava window")
	local lateBomb = credit.Resolve(victim, bombed, 30.01)
	assert(lateBomb and lateBomb.solo and not lateBomb.count, "bomb stayed open after 20 seconds")
	bombed:SetAttribute("DeathCause", "Void")
	local bombVoid = credit.Resolve(victim, bombed, 15)
	assert(bombVoid and bombVoid.killerId == 77 and bombVoid.source == "Bomb", "bomb missed the 5 second void window")
	expect(credit.FeedKey(bombVoid.cause, bombVoid.source), "VoidBomb", "bomb void lines")
	local lateBombVoid = credit.Resolve(victim, bombed, 15.01)
	assert(lateBombVoid and lateBombVoid.solo and not lateBombVoid.count, "bomb used the lava window on a fall")

	local pushed = humanoid()
	credit.NoteAttach(pushed, grappler, "Ann")
	credit.NoteHit(pushed, 77, "Bea", 10)
	assert(credit.IsActive(pushed, grappler), "a hit cleared a grapple that is still on")
	pushed:SetAttribute("DeathCause", "Lava")
	expect(credit.Resolve(victim, pushed, 100).killerId, grappler, "held grapple lost to a hit")
	credit.NoteRelease(pushed, grappler, 20)
	credit.NoteHit(pushed, 77, "Bea", 25, "Push")
	local pushLava = credit.Resolve(victim, pushed, 40)
	expect(pushLava.killerId, 77, "newer push lost to the old grapple")
	expect(credit.FeedKey(pushLava.cause, pushLava.source), "Lava", "push into lava kept the lava lines")
	pushed:SetAttribute("DeathCause", "Void")
	local pushVoid = credit.Resolve(victim, pushed, 29)
	assert(pushVoid and pushVoid.killerId == 77 and pushVoid.source == "Push", "push void credit")
	expect(credit.FeedKey(pushVoid.cause, pushVoid.source), "VoidPush", "push void lines")
	pushed:SetAttribute("DeathCause", "Lava")
	credit.NoteAttach(pushed, grappler, "Ann")
	credit.NoteRelease(pushed, grappler, 30)
	expect(credit.Resolve(victim, pushed, 45).killerId, grappler, "newer grapple lost to an older push")

	local frozenBomb = humanoid({DeathCause = "Freeze", DeathFreezer = 44})
	credit.NoteHit(frozenBomb, 77, "Bea", 0)
	expect(credit.Resolve(victim, frozenBomb, 1).killerId, 44, "freeze used the bomb window")
	local crushedBomb = humanoid({DeathCause = "Crusher", DeathPuller = 55})
	credit.NoteHit(crushedBomb, 77, "Bea", 0)
	expect(credit.Resolve(victim, crushedBomb, 5).killerId, 55, "bomb overrode the crusher lever")
	credit.NoteHit(bombed, victim, "Self", 12)
	bombed:SetAttribute("DeathCause", "Lava")
	local selfBomb = credit.Resolve(victim, bombed, 14)
	assert(selfBomb and selfBomb.solo and not selfBomb.count, "self bomb was stored as a kill")

	local resetBody = humanoid({DeathCause = "Reset"})
	credit.NoteAttach(resetBody, grappler, "Ann")
	assert(credit.Report({UserId = victim}, resetBody, 1) == nil, "reset report was announced")
	expect(heard, 1, "reset listener")
	assert(not credit.IsActive(resetBody), "reset left the grapple record active")
end
