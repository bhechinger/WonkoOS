local nodes = ObjectManager {
  Interest {
    type = "node",
  }
}

local ports = ObjectManager {
  Interest {
    type = "port",
    Constraint { "format.dsp", "equals", "8 bit raw midi" },
  }
}

local links = ObjectManager {
  Interest {
    type = "link",
  }
}

local current_link = nil

local function lookup_node(node_id)
  return nodes:lookup {
    Constraint { "object.id", "equals", node_id },
  }
end

local function is_source_port(port)
  if port.properties["port.direction"] ~= "out" then
    return false
  end

  if port.properties["port.alias"] ~= "nanoKONTROL2:nanoKONTROL2 _ CTRL" then
    return false
  end

  local node = lookup_node(port.properties["node.id"])
  if not node then
    return false
  end

  return node.properties["node.name"] == "Midi-Bridge"
    and node.properties["media.class"] == "Midi/Bridge"
end

local function is_target_port(port)
  if port.properties["port.direction"] ~= "in" then
    return false
  end

  if port.properties["port.name"] ~= "input_1" then
    return false
  end

  local node = lookup_node(port.properties["node.id"])
  if not node then
    return false
  end

  return node.properties["node.name"] == "spotify-midi-control"
    and node.properties["media.class"] == "Stream/Input/Midi"
end

local function find_port(predicate)
  for port in ports:iterate() do
    if predicate(port) then
      return port
    end
  end

  return nil
end

local function link_exists(output_port, input_port)
  return links:lookup {
    Constraint { "link.output.node", "equals", output_port.properties["node.id"] },
    Constraint { "link.output.port", "equals", output_port.properties["object.id"] },
    Constraint { "link.input.node", "equals", input_port.properties["node.id"] },
    Constraint { "link.input.port", "equals", input_port.properties["object.id"] },
  } ~= nil
end

local function ensure_route()
  if current_link then
    return
  end

  local output_port = find_port(is_source_port)
  local input_port = find_port(is_target_port)
  if not output_port or not input_port then
    return
  end

  if link_exists(output_port, input_port) then
    return
  end

  current_link = Link("link-factory", {
    ["link.output.node"] = output_port.properties["node.id"],
    ["link.output.port"] = output_port.properties["object.id"],
    ["link.input.node"] = input_port.properties["node.id"],
    ["link.input.port"] = input_port.properties["object.id"],
    ["object.id"] = nil,
    ["node.description"] = "nanoKONTROL2 to spotify-midi-control",
  })

  current_link:activate(1)
end

nodes:connect("object-added", ensure_route)
ports:connect("object-added", ensure_route)

nodes:activate()
ports:activate()
links:activate()

ensure_route()
