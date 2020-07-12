-- Translation support
local S = minetest.get_translator("keyring")
local F = minetest.formspec_escape

-- context
local context = {}
local selected = {}
local selected_player = {}
local selected_player_num = {}
local key_list = {}
local tab = {}
local function reset_context(name)
	context[name] = nil
	selected[name] = nil
	selected_player[name] = nil
	selected_player_num[name] = nil
	key_list[name] = nil
	tab[name] = nil
end

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	reset_context(name)
end)


minetest.register_on_player_receive_fields(function(player, formname, fields)
	-- guard
	if not (formname == "keyring:edit") then
		return
	end
	local name = player:get_player_name()
	-- clean context
	if fields.quit and not fields.key_enter then
		reset_context(name)
		return
	end

	-- check abuses
	local item = player:get_wielded_item()
	local meta = item:get_meta()
	if item:get_name() ~= "keyring:keyring"
		and item:get_name() ~= "keyring:personal_keyring" then
		keyring.log("action", "Player "..name..
			" sent a keyring action but has no keyring in hand.")
		return
	end
	local krs = meta:get_string(keyring.fields.KRS)
	if krs ~= context[name] then
		keyring.log("action", "Player "..name
			.." sent a keyring action but has not the right keyring in hand.")
		return
	end

	-- edits rights not required for this section
	if item:get_name() == "keyring:personal_keyring" then
		-- tabheader selection
		if fields.header == "2" then
			tab[name] = true
		elseif fields.header == "1" then
			tab[name] = nil
		end
		if fields.header then
			keyring.formspec(item, minetest.get_player_by_name(name))
		end
	end

	-- check for edits
	local keyring_owner = meta:get_string("owner")
	local shared = meta:get_string(keyring.fields.shared)
	local keyring_allowed = keyring.fields.utils.owner.is_edit_allowed(keyring_owner, name)
	if not keyring_allowed then
		if (not minetest.check_player_privs(name, { keyring_inspect=true })) and
			not keyring.fields.utils.shared.is_shared_with(name, shared) then
			keyring.log("action", "Player "..name
				.." sent command to manage keys of a keyring owned by "
				..(keyring_owner or "unknown player"))
		end
		return
	end

	if item:get_name() == "keyring:personal_keyring" then
		-- make owner
		if fields.make_private or fields.make_public then
			if not keyring_allowed then
				minetest.chat_send_player(name,
					S("You are not allowed to edit settings of this keyring."))
				return
			end
			if fields.make_private  then
				meta:set_string("owner", name)
				meta:set_string("description",
					ItemStack("keyring:personal_keyring"):get_description()
					.." "..S("(owned by @1)", name))
			elseif fields.make_public then
				meta:set_string("owner", "")
				meta:set_string("description",
					ItemStack("keyring:personal_keyring"):get_description())
			end
			player:set_wielded_item(item)
			keyring.formspec(item, minetest.get_player_by_name(name))
		end
		if keyring_owner == name then
			if fields.share_player_dropdown and fields.player_dropdown
				and fields.player_dropdown ~= "" then
				meta:set_string(keyring.fields.shared, shared..
					((shared ~="") and " " or "")..fields.player_dropdown)
				player:set_wielded_item(item)
				keyring.formspec(item, minetest.get_player_by_name(name))
			end
			if (fields.share_player_button or (fields.key_enter and fields.key_enter_field
				and fields.key_enter_field == "share_player")) and fields.share_player
				and fields.share_player ~= "" then
				local concat = fields.share_player
				for _, v in ipairs({"%[", "]", ",", ";", "\\"}) do
					concat = concat:gsub(v," ")
				end
				meta:set_string(keyring.fields.shared, shared..
					((shared ~="") and " " or "")..concat)
					player:set_wielded_item(item)
				keyring.formspec(item, minetest.get_player_by_name(name))
			end
			if fields.unshare and selected_player[name]
				and selected_player[name] ~= "" then
				shared = keyring.fields.utils.shared.remove(selected_player[name], shared)
				if keyring.fields.utils.shared.get_from_index(
					selected_player_num[name], shared) == "" then
					selected_player_num[name] = selected_player_num[name] -1
				end
				selected_player[name] = keyring.fields.utils.shared.get_from_index(
					selected_player_num[name], shared)
				meta:set_string(keyring.fields.shared, shared)
				player:set_wielded_item(item)
				keyring.formspec(item, minetest.get_player_by_name(name))
			end

			-- refresh selected player
			if fields.selected_player then
				local event = minetest.explode_textlist_event(fields.selected_player)
				if event.type ~= "INV" then
					selected_player[name] = keyring.fields.utils.shared.get_from_index(
						event.index, shared)
					if selected_player[name] == "" then
						keyring.log("action", "Player "..name
							.." selected a player in keyring settings interface"
							.." but this player is not in the list.")
					else
						selected_player_num[name] = event.index
					end
				end
			end

			-- warn player
			if (fields.share_player_button or (fields.key_enter and fields.key_enter_field
				and fields.key_enter_field == "share_player")) and ((not fields.share_player)
				or fields.share_player == "") then
				minetest.chat_send_player(name, S("You must enter a player name first."))
			end
			if (fields.unshare and ((not selected_player[name])
				or selected_player[name] == ""))
				or (fields.share_player_dropdown and ((not fields.player_dropdown)
				or fields.player_dropdown == "")) then
				minetest.chat_send_player(name, S("You must select a player first."))
			end
		end
	end

	-- key selection
	if fields.selected_key ~= nil then
		local event = minetest.explode_textlist_event(fields.selected_key)
		if event.type ~= "INV" then
			if key_list[name] == nil or event.index > #key_list[name] then
				keyring.log("action", "Player "..name
					.." selected a key in keyring interface"
					.." but this key does not exist.")
				return
			end
			selected[name] = event.index
		end
	end

	if selected[name] then
		-- no name provided for renaming
		if (fields.rename or (fields.key_enter and fields.key_enter_field
			and fields.key_enter_field == "new_name"))
			and ((not fields.new_name) or fields.new_name == "") then
			minetest.chat_send_player(name, S("You must enter a name first."))
			return
		end
		-- add user description
		if (fields.rename or (fields.key_enter and fields.key_enter_field
			and fields.key_enter_field == "new_name"))
			and key_list[name] and selected[name] and selected[name] <= #key_list[name]
			and fields.new_name and fields.new_name ~= "" and selected[name] then
			local u_krs = minetest.deserialize(krs)
			u_krs[key_list[name][selected[name]]].user_description = fields.new_name
			meta:set_string(keyring.fields.KRS, minetest.serialize(u_krs))
			player:set_wielded_item(item)
			keyring.formspec(item, minetest.get_player_by_name(name))
			return
		end
		-- put the key out of keyring
		if fields.remove and selected[name] and key_list[name] and selected[name]
			and selected[name] <= #key_list[name] then
			local key = ItemStack("default:key")
			local u_krs = minetest.deserialize(krs)
			local key_meta = key:get_meta()
			key_meta:set_string("secret", selected[name])
			key_meta:set_string(keyring.fields.description,
				u_krs[key_list[name][selected[name]]].user_description)
			key_meta:set_string("description",
				u_krs[key_list[name][selected[name]]].description)
			local inv = minetest.get_player_by_name(name):get_inventory()
			if inv:room_for_item("main", key) then
				-- remove key from keyring
				local number = u_krs[key_list[name][selected[name]]].number
				if number > 1 then
					-- remove only 1 key
					u_krs[key_list[name][selected[name]]].number = number -1
				else
					u_krs[key_list[name][selected[name]]] = nil
				end
				-- apply
				item:get_meta():set_string(keyring.fields.KRS, minetest.serialize(u_krs))
				player:set_wielded_item(item)
				keyring.formspec(item, minetest.get_player_by_name(name))

				-- add key to inventory
				inv:add_item("main", key)
			else
				minetest.chat_send_player(name, S("There is no room in your inventory for a key."))
			end
			return
		end
	end
	-- no selected key, but removing/renaming asked
	if (fields.rename or fields.remove or (fields.key_enter and fields.key_enter_field
		and fields.key_enter_field == "new_name")) and not selected[name] then
		minetest.chat_send_player(name, S("You must select a key first."))
		return
	end
end)

--[[ Get key list
-- parameter: serialized krs and player name
-- return: key list
--]]
local function get_key_list(serialized_krs, name)
	local krs = minetest.deserialize(serialized_krs) or {}
	local list = ""
	local first = true
	local index = 1
	key_list[name] = {}
	for k, v in pairs(krs) do
		key_list[name][index] = k
		index = index +1
		if not first then
			list = list..","
		else
			first = false
		end
		list = list..F(v.user_description or v.description)
		if (v.number > 1) then
			list = list..F(" (×"..v.number..")")
		end
	end
	return list
end

--[[ Get player shared list
-- parameter: list of players separated by space, player name
-- return: return player list separated by comma
-- ]]
local function get_player_shared_list(player_list, name)
	if player_list == "" or player_list == nil then
		return ""
	end
	return player_list:gsub("%s+", ",")
end

--[[ Get connected players list (not already in shared)
-- parameter: list of players separated by space, player name
--]]
local function get_player_list_connected(player_list, name)
	local list = minetest.get_connected_players()
	local res_list = ""
	local first = true
	for _, v in pairs(list) do
		local v_name = v:get_player_name()
		if (v_name ~= name) and
			not keyring.fields.utils.shared.is_shared_with(v_name, player_list) then
			if not first then
				res_list = res_list..","
			else
				first = false
			end
			res_list = res_list..v_name
		end
	end
	return res_list
end

--[[
-- itemstack: a keyring:keyring
-- player: the player to show formspec
--]]
keyring.formspec = function(itemstack, player)
	local name = player:get_player_name()
	local keyring_owner = itemstack:get_meta():get_string("owner")
	local keyring_allowed = keyring.fields.utils.owner.is_edit_allowed(keyring_owner,
		name)
	local has_list_priv = minetest.check_player_privs(name, { keyring_inspect=true })
	local shared = itemstack:get_meta():get_string(keyring.fields.shared)
	local is_shared_with = keyring.fields.utils.shared.is_shared_with(name, shared)
	if not (keyring_allowed or has_list_priv or is_shared_with) then
		keyring.log("action", "Player "..name
			.." tryed to access key management of a keyring owned by "
			..(keyring_owner or "unknown player"))
		minetest.chat_send_player(name, S("You are not allowed to use this keyring."))
		return itemstack
	end
	local keyring_type = itemstack:get_name()
	local krs = itemstack:get_meta():get_string(keyring.fields.KRS)
	-- formspec
	local formspec = "formspec_version[3]"
		.."size[10.75,11.25]"
	if keyring_type == "keyring:personal_keyring" then
		-- tabheader
		formspec = formspec.."tabheader[0,0;10.75,1;header;"
			..S("Keys management")..","..S("Keyring settings")..";"
			..(tab[name] and "2" or "1")..";false;true]"
	end
	if tab[name] then
		local protected = false
		local public = false
		if keyring_owner == name then
			formspec = formspec.."label[1,1;"..F(S("You own this keyring.")).."]"
				.."button[1,1.5;5,1;make_public;"..F(S("Make public")).."]"
		elseif keyring_owner and keyring_owner ~= "" then
			formspec = formspec.."label[1,1;"
				..F(S("This keyring is owned by @1.", keyring_owner)).."]"
			protected = true
		else
			formspec = formspec.."label[1,1;"..F(S("This keyring is public.")).."]"
				.."button[1,1.5;5,1;make_private;"..F(S("Make private")).."]"
			public = true
		end
		if (not public) and shared ~= nil and shared ~= "" then
			formspec = formspec.."label[1,"..(protected and "2" or "3")
				..";"..F(S("This keyring is shared with:")).."]"
				.."textlist[1,"..(protected and "2.75" or "3.75")
				..";8.75,"..(protected and "6" or "4")
				..";selected_player;"..get_player_shared_list(shared, name).."]"
		elseif not public then
			formspec = formspec.."label[1,"..(protected and "2" or "3")
				..";"..F(S("This keyring is not shared.")).."]"
		end
		if (not protected) and (not public) then
			formspec = formspec
				-- dropdown
				.."dropdown[1,8;5,1;player_dropdown;"
				..get_player_list_connected(shared, name)..";0]"
				.."button[6.5,8;3.25,1;share_player_dropdown;"..F(S("Share")).."]"
				-- field
				.."field[1,9;5,1;share_player;;]"
				.."field_close_on_enter[share_player;false]"
				.."button[6.5,9;3.25,1;share_player_button;"..F(S("Share")).."]"
		end
		if (not protected) and (not public) and shared ~= nil and shared ~= "" then
			formspec = formspec
				.."button[1,10;5,1;unshare;"..F(S("Unshare")).."]"
		end
	else
		local has_keys = next(minetest.deserialize(krs) or {}) ~= nil
		if has_keys then
			formspec = formspec
				-- header label
				.."label[1,1;"..F(S("List of keys in the keyring")).."]"
				-- list of keys
				.."textlist[1,1.75;8.75,"
				..( -- space for rename button
					(keyring_type == "keyring:personal_keyring" and not keyring_allowed)
					and "8" or "7"
				)
			formspec = formspec..";selected_key;"..get_key_list(krs, name).."]"
			if keyring_allowed or (keyring_type ~= "keyring:personal_keyring") then
				-- rename button
				formspec = formspec.."button[1,9;5,1;rename;"..F(S("Rename key")).."]"
					.."field[6.5,9;3.25,1;new_name;;]"
					.."field_close_on_enter[new_name;false]"
					.."button[1,10;5,1;remove;"..F(S("Remove key")).."]"
			end
		else
			formspec = formspec.."label[1,1;"..F(S("There is no key in the keyring.")).."]"
		end
	end
	formspec = formspec.."button_exit[6.5,10;3.25,1;exit;"..F(S("Exit")).."]"

	-- context
	context[name] = krs
	minetest.show_formspec(name, "keyring:edit", formspec)
	return itemstack
end
