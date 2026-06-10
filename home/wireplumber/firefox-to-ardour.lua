local nodes = ObjectManager {
  Interest {
    type = "node",
  }
}

local ports = ObjectManager {
  Interest {
    type = "port",
  }
}

local links = ObjectManager {
  Interest {
    type = "link",
  }
}

local function lookup_node(node_id)
  return nodes:lookup {
    Constraint { "object.id", "equals", node_id },
  }
end

local function is_firefox_node(node)
  local props = node.properties

  return props["application.name"] == "Firefox"
    or props["node.name"] == "Firefox"
    or props["application.process.binary"] == "firefox"
end

local function firefox_output_channel(port)
  if port.properties["port.direction"] ~= "out" then
    return nil
  end

  local node = lookup_node(port.properties["node.id"])
  if not node or node.properties["media.class"] ~= "Stream/Output/Audio" then
    return nil
  end

  if not is_firefox_node(node) then
    return nil
  end

  local channel = port.properties["audio.channel"]
  if channel == "FL" then
    return "1"
  elseif channel == "FR" then
    return "2"
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

local function create_link(output_port, input_port)
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
    ["node.description"] = "firefox to ardour routing",
  })

  link:activate(1)
end

local function each_ardour_firefox_input(channel, callback)
  for port in ports:iterate {
    Constraint { "port.alias", "equals", "ardour:Firefox/audio_in " .. channel },
    Constraint { "port.direction", "equals", "in" },
  } do
    callback(port)
  end
end

local function ensure_firefox_to_ardour(port)
  local channel = firefox_output_channel(port)
  if not channel then
    return
  end

  each_ardour_firefox_input(channel, function(input_port)
    create_link(port, input_port)
  end)
end

local function ensure_routes()
  for port in ports:iterate() do
    ensure_firefox_to_ardour(port)
  end
end

nodes:connect("object-added", ensure_routes)
ports:connect("object-added", ensure_routes)
links:connect("object-added", ensure_routes)

nodes:activate()
ports:activate()
links:activate()

ensure_routes()
