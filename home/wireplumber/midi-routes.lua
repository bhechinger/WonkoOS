local reconcile_delay_ms = 500
local graph_ready_retry_ms = 1000
local route_ready_delay_seconds = 10

local graph_ready_nodes = {
  "alsa_output.firewire-0x00130e0401c04de0.multichannel-output",
}

local desired_links = {
  -- nanoKONTROL2 control surface into Ardour.
  { output = "nanoKONTROL2:nanoKONTROL2 _ CTRL", input = "ardour:MIDI Control In" },

  -- nanoKONTROL2 control surface into spotify-midi-control after the audio graph is ready.
  {
    output = "nanoKONTROL2:nanoKONTROL2 _ CTRL",
    input = "spotify-midi-control:input_1",
    require_graph_ready = true,
    ready_delay_seconds = route_ready_delay_seconds,
  },
}

local ports = ObjectManager {
  Interest {
    type = "port",
    Constraint { "format.dsp", "equals", "8 bit raw midi" },
  }
}

local nodes = ObjectManager {
  Interest {
    type = "node",
  }
}

local reconcile_source = nil
local created_links = {}
local route_ready_since = {}
local schedule_reconcile

local function find_port(alias, direction)
  return ports:lookup {
    Constraint { "port.alias", "equals", alias },
    Constraint { "port.direction", "equals", direction },
  }
end

local function find_node(name)
  return nodes:lookup {
    Constraint { "node.name", "equals", name },
  }
end

local function is_node_running(node)
  local state = node.properties["state"]
  return state == nil or state == "running"
end

local function is_graph_ready()
  for _, node_name in ipairs(graph_ready_nodes) do
    local node = find_node(node_name)

    if not node or not is_node_running(node) then
      return false
    end
  end

  return true
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
    ["link.async"] = true,
    ["link.passive"] = true,
    ["node.description"] = "static WirePlumber MIDI link",
  })

  local activated = pcall(function()
    link:activate(1)
  end)

  if activated then
    created_links[key] = link
  end
end

local function route_key(desired_link)
  return desired_link.output .. "->" .. desired_link.input
end

local function reset_route_ready_since(desired_link)
  route_ready_since[route_key(desired_link)] = nil
end

local function route_delay_elapsed(desired_link)
  local delay_seconds = desired_link.ready_delay_seconds or 0
  if delay_seconds <= 0 then
    return true
  end

  local key = route_key(desired_link)
  local now = os.time()
  local ready_since = route_ready_since[key]

  if not ready_since then
    route_ready_since[key] = now
    return false
  end

  return now - ready_since >= delay_seconds
end

local function route_is_ready(desired_link, output_port, input_port)
  if not output_port or not input_port then
    reset_route_ready_since(desired_link)
    return false
  end

  if desired_link.require_graph_ready and not is_graph_ready() then
    reset_route_ready_since(desired_link)
    return false
  end

  return route_delay_elapsed(desired_link)
end

local function reconcile_links()
  local needs_retry = false

  for _, desired_link in ipairs(desired_links) do
    local output_port = find_port(desired_link.output, "out")
    local input_port = find_port(desired_link.input, "in")

    if route_is_ready(desired_link, output_port, input_port) then
      create_link(output_port, input_port)
    else
      needs_retry = true
    end
  end

  if needs_retry then
    schedule_reconcile(graph_ready_retry_ms)
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
nodes:connect("object-added", schedule_reconcile)
nodes:connect("object-removed", schedule_reconcile)

ports:activate()
nodes:activate()

schedule_reconcile()
