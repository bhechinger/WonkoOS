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

local function is_source_port(port)
  if port.properties["port.direction"] ~= "out" then
    return false
  end

  return port.properties["port.alias"] == "nanoKONTROL2:nanoKONTROL2 _ CTRL"
end

local function is_target_port(port)
  if port.properties["port.direction"] ~= "in" then
    return false
  end

  return port.properties["port.alias"] == "spotify-midi-control:input_1"
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
  local output_port = find_port(is_source_port)
  local input_port = find_port(is_target_port)
  if not output_port or not input_port then
    return
  end

  if link_exists(output_port, input_port) then
    return
  end

  local link = Link("link-factory", {
    ["link.output.node"] = output_port.properties["node.id"],
    ["link.output.port"] = output_port.properties["object.id"],
    ["link.input.node"] = input_port.properties["node.id"],
    ["link.input.port"] = input_port.properties["object.id"],
    ["object.id"] = nil,
    ["object.linger"] = true,
    ["link.async"] = true,
  })

  link:activate(1)
end

ports:connect("object-added", ensure_route)
links:connect("object-added", ensure_route)

ports:activate()
links:activate()

ensure_route()
