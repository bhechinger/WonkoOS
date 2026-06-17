local reconcile_delay_ms = 500
local reconcile_interval_ms = 2000

local desired_links = {
  -- nanoKONTROL2 control surface into Ardour.
  { output = "nanoKONTROL2:nanoKONTROL2 _ CTRL", input = "ardour:MIDI Control In" },

  -- nanoKONTROL2 control surface into spotify-midi-control.
  { output = "nanoKONTROL2:nanoKONTROL2 _ CTRL", input = "spotify-midi-control:input_1" },
}

local ports = ObjectManager {
  Interest {
    type = "port",
    Constraint { "format.dsp", "equals", "8 bit raw midi" },
  }
}

local reconcile_source = nil
local reconcile_interval_source = nil
local created_links = {}
local schedule_reconcile

local function find_port(alias, direction)
  return ports:lookup {
    Constraint { "port.alias", "equals", alias },
    Constraint { "port.direction", "equals", direction },
  }
end

local function link_key(output_port, input_port)
  return output_port.properties["object.id"] .. ":" .. input_port.properties["object.id"]
end

local function create_link(output_port, input_port)
  local key = link_key(output_port, input_port)
  if created_links[key] then
    return
  end

  local link = Link("link-factory", {
    ["link.output.node"] = output_port.properties["node.id"],
    ["link.output.port"] = output_port.properties["object.id"],
    ["link.input.node"] = input_port.properties["node.id"],
    ["link.input.port"] = input_port.properties["object.id"],
    ["object.id"] = nil,
    ["object.linger"] = false,
    ["node.description"] = "static WirePlumber MIDI link",
  })

  local activated = pcall(function()
    link:activate(1)
  end)

  if activated then
    created_links[key] = link
  end
end

local function reconcile_links()
  for _, desired_link in ipairs(desired_links) do
    local output_port = find_port(desired_link.output, "out")
    local input_port = find_port(desired_link.input, "in")

    if output_port and input_port then
      create_link(output_port, input_port)
    end
  end
end

schedule_reconcile = function(delay_ms)
  if type(delay_ms) ~= "number" then
    delay_ms = reconcile_delay_ms
  end

  if reconcile_source then
    reconcile_source:destroy()
  end

  reconcile_source = Core.timeout_add(delay_ms, function()
    reconcile_source = nil
    reconcile_links()
  end)
end

ports:connect("object-added", schedule_reconcile)
ports:connect("object-removed", schedule_reconcile)

ports:activate()

schedule_reconcile()

reconcile_interval_source = Core.timeout_add(reconcile_interval_ms, function()
  reconcile_links()
  return true
end)
