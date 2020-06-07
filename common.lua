
jumpdrive.sanitize_coord = function(coord)
	return math.max( math.min( coord, 31000 ), -31000 )
end

-- get pos object from pos
jumpdrive.get_meta_pos = function(pos)
	local meta = minetest.get_meta(pos);
	return {x=meta:get_int("x"), y=meta:get_int("y"), z=meta:get_int("z")}
end

-- set pos object from pos
jumpdrive.set_meta_pos = function(pos, target)
	local meta = minetest.get_meta(pos);
	meta:set_int("x", target.x)
	meta:set_int("y", target.y)
	meta:set_int("z", target.z)
end

-- get offset from meta
jumpdrive.get_radius = function(pos)
	local meta = minetest.get_meta(pos);
	return math.max(math.min(meta:get_int("radius"), jumpdrive.config.max_radius), 1)
end

-- calculates the power requirements for a jump
jumpdrive.calculate_power = function(radius, distance, sourcePos, targetPos)
	return 10 * distance * radius
end


-- preflight check, for overriding
jumpdrive.preflight_check = function(source, destination, radius, playername)
	return { success=true }
end

jumpdrive.reset_coordinates = function(pos)
	local meta = minetest.get_meta(pos)

	meta:set_int("x", pos.x)
	meta:set_int("y", pos.y)
	meta:set_int("z", pos.z)

end

function jumpdrive.get_mapblock_from_pos(pos)
	return {
		x = math.floor(pos.x / 16),
		y = math.floor(pos.y / 16),
		z = math.floor(pos.z / 16)
	}
end

jumpdrive.digiline_rules = {
	-- jumpdrive.digiline_rules
	{x= 1,y= 0,z= 0},{x=-1,y= 0,z= 0}, -- along x beside
	{x= 0,y= 0,z= 1},{x= 0,y= 0,z=-1}, -- along z beside
	{x= 1,y= 1,z= 0},{x=-1,y= 1,z= 0}, -- 1 node above along x diagonal
	{x= 0,y= 1,z= 1},{x= 0,y= 1,z=-1}, -- 1 node above along z diagonal
	{x= 1,y=-1,z= 0},{x=-1,y=-1,z= 0}, -- 1 node below along x diagonal
	{x= 0,y=-1,z= 1},{x= 0,y=-1,z=-1}, -- 1 node below along z diagonal
	-- added rules for digi cable
	{x= 0,y= 1,z= 0},{x= 0,y=-1,z= 0}, -- along y above and below
}
