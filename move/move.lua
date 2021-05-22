
local c_air = minetest.get_content_id("air")


-- map of replaced content id's on jump
-- TODO: expose as api function
-- <id> = <id>
local mapped_content_ids = {}

if minetest.get_modpath("vacuum") then
	-- don't jump vacuum
	mapped_content_ids[minetest.get_content_id("vacuum:vacuum")] = c_air
end

-- map of "on_movenode" aware node id's
-- content_id = nodedef
local movenode_aware_nodeids = {}

-- collect movenode aware node id's
minetest.register_on_mods_loaded(function()
	local count = 0
	for nodename, nodedef in pairs(minetest.registered_nodes) do
		if type(nodedef.on_movenode) == "function" then
			count = count + 1
			local id = minetest.get_content_id(nodename)
			movenode_aware_nodeids[id] = nodedef
		end
	end
	minetest.log("action", "[jumpdrive] collected " .. count .. " 'on_movenode' aware nodes")
end)

-- moves the source to the target area
-- no protection- or overlap checking is done here
function jumpdrive.move(source_pos1, source_pos2, target_pos1, target_pos2)

	minetest.log("action", "[jumpdrive] initiating jump (" ..
		minetest.pos_to_string(source_pos1) .. "-" .. minetest.pos_to_string(source_pos2) ..
		") (" .. minetest.pos_to_string(target_pos1) .. "-" .. minetest.pos_to_string(target_pos2) .. ")")

	-- step 1: copy via voxel manip
	-- https://dev.minetest.net/VoxelManip#Examples

	-- delta between source and target
	local delta_vector = vector.subtract(target_pos1, source_pos1)

	-- center of source
	local source_center = vector.add(source_pos1, vector.divide(vector.subtract(source_pos2, source_pos1), 2))
	minetest.log("action", "[jumpdrive] source-center: " .. minetest.pos_to_string(source_center))

	local t0 = minetest.get_us_time()


	-- load areas (just a precaution)
	if minetest.load_area then
		minetest.load_area(source_pos1, source_pos2)
		minetest.load_area(target_pos1, target_pos2)
	end

	-- read source
	local manip = minetest.get_voxel_manip()
	local e1, e2 = manip:read_from_map(source_pos1, source_pos2)
	local source_area = VoxelArea:new({MinEdge=e1, MaxEdge=e2})
	local source_data = manip:get_data()
	local source_param1 = manip:get_light_data()
	local source_param2 = manip:get_param2_data()

	minetest.log("action", "[jumpdrive] read source-data")

	-- write target
	manip = minetest.get_voxel_manip()
	e1, e2 = manip:read_from_map(target_pos1, target_pos2)
	local target_area = VoxelArea:new({MinEdge=e1, MaxEdge=e2})
	local target_data = manip:get_data()
	local target_param1 = manip:get_light_data()
	local target_param2 = manip:get_param2_data()

	-- list of { from_pos, to_pos, }
	local movenode_list = {}

	minetest.log("action", "[jumpdrive] read target-data");

	for z=source_pos1.z, source_pos2.z do
	for y=source_pos1.y, source_pos2.y do
	for x=source_pos1.x, source_pos2.x do

		local from_pos = { x=x, y=y, z=z }
		local to_pos = vector.add(from_pos, delta_vector)

		local source_index = source_area:indexp(from_pos)
		local target_index = target_area:indexp(to_pos)

		-- copy block id
		local id = source_data[source_index]

		if mapped_content_ids[id] then
			-- replace original content id
			id = mapped_content_ids[id]
		end

		target_data[target_index] = id

		if movenode_aware_nodeids[id] then

			-- check if we are on an edge
			local edge = { x=0, y=0, z=0 }

			-- negative edge
			if source_pos1.x == x then edge.x = -1 end
			if source_pos1.y == y then edge.y = -1 end
			if source_pos1.z == z then edge.z = -1 end
			-- positive edge
			if source_pos2.z == x then edge.x = 1 end
			if source_pos2.y == y then edge.y = 1 end
			if source_pos2.z == z then edge.z = 1 end

			table.insert(movenode_list, {
				from_pos = from_pos,
				to_pos = to_pos,
				edge = edge,
				nodedef = movenode_aware_nodeids[id]
			})
		end

		-- copy params
		target_param1[target_index] = source_param1[source_index]
		target_param2[target_index] = source_param2[source_index]
	end
	end
	end


	manip:set_data(target_data)
	manip:set_light_data(target_param1)
	manip:set_param2_data(target_param2)
	manip:write_to_map()
	manip:update_map()

	local t1 = minetest.get_us_time()
	minetest.log("action", "[jumpdrive] step I took " .. (t1 - t0) .. " us")

	-- step 2: check meta/timers and copy if needed
	t0 = minetest.get_us_time()
	jumpdrive.move_metadata(source_pos1, source_pos2, delta_vector)
	jumpdrive.move_nodetimers(source_pos1, source_pos2, delta_vector)

	-- move "on_movenode" aware nodes
	for _, entry in ipairs(movenode_list) do
		entry.nodedef.on_movenode(entry.from_pos, entry.to_pos, {
			edge = entry.edge
		})
	end

	-- print stats
	t1 = minetest.get_us_time()
	minetest.log("action", "[jumpdrive] step II took " .. (t1 - t0) .. " us")


	-- step 3: execute target region compat code
	t0 = minetest.get_us_time()
	jumpdrive.target_region_compat(source_pos1, source_pos2, target_pos1, target_pos2, delta_vector)
	t1 = minetest.get_us_time()
	minetest.log("action", "[jumpdrive] step III took " .. (t1 - t0) .. " us")


	-- step 4: move objects
	t0 = minetest.get_us_time()
	jumpdrive.move_objects(source_center, source_pos1, source_pos2, delta_vector)

	-- move players
	jumpdrive.move_players(source_pos1, source_pos2, delta_vector)

	t1 = minetest.get_us_time()
	minetest.log("action", "[jumpdrive] step IV took " .. (t1 - t0) .. " us")


	-- step 5: clear source area with voxel manip
	t0 = minetest.get_us_time()
	jumpdrive.clear_area(source_pos1, source_pos2)

	t1 = minetest.get_us_time()
	minetest.log("action", "[jumpdrive] step V took " .. (t1 - t0) .. " us")

	-- call after_jump callbacks
	jumpdrive.fire_after_jump({
		pos1 = source_pos1,
		pos2 = source_pos2
	}, {
		pos1 = target_pos1,
		pos2 = target_pos2
	})

end
