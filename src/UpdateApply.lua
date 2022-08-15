#@
-- Path of Building
--
-- Module: Update Apply
-- Applies updates.
--

--Cache globals

local print = print
local ipairs = ipairs
local assert = assert
local SpawnProcess = SpawnProcess

local os = os
local o_remove = os.remove

local io = io
local i_open = io.open

local opFileName = ...

print("Applying update...")

local opFile = i_open(opFileName, "r")
if not opFile then
	print("No operations list present.\n")
	return
end

local lines = { }

for line in opFile:lines() do
	lines[#lines + 1] = line
end

opFile:close()

o_remove(opFileName)

local function opSwitch(input, args)
	local switch = {
		["move"] = function(args)
			local src, dst = args:match('"(.*)" "(.*)"')
			dst = dst:gsub("{space}", " ")
			print("Updating '"..dst.."'")

			local srcFile = i_open(src, "rb")
			assert(srcFile, "couldn't open "..src)

			local dstFile
			while not dstFile do
				dstFile = i_open(dst, "w+b")
			end
			if dstFile then
				dstFile:write(srcFile:read("*a"))
				dstFile:close()
			end
			
			srcFile:close()
			o_remove(src)
		end,
		["delete"] = function(args)
			local file = args:match('"(.*)"')
			print("Deleting '"..file.."'")
			o_remove(file)
		end,
		["start"] = function(args)
			local target = args:match('"(.*)"')
			SpawnProcess(target)
		end
	}

	return switch[input] and switch[input](args)
end

local op, args
for _, line in ipairs(lines) do
	op = line:match("(%a+) ?(.*)")
	opSwitch(op, args)
end
