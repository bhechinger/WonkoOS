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

local function lookup_port(port_id)
  return ports:lookup {
    Constraint { "object.id", "equals", port_id },
  }
end

local function is_firefox_node(node)
  local props = node.properties

  return props["application.name"] == "Firefox"
    or props["node.name"] == "Firefox"
    or props["application.process.binary"] == "firefox"
end

local function is_spotify_node(node)
  local props = node.properties

  return props["application.name"] == "spotify"
    or props["node.name"] == "spotify"
    or props["application.process.binary"] == ".spotify-wrapped"
    or props["application.process.binary"] == "spotify"
end

local function route_for_node(node)
  if is_firefox_node(node) then
    return "Firefox"
  elseif is_spotify_node(node) then
    return "Music"
  end

  return nil
end

local function output_route(port)
  if port.properties["port.direction"] ~= "out" then
    return nil
  end

  local node = lookup_node(port.properties["node.id"])
  if not node or node.properties["media.class"] ~= "Stream/Output/Audio" then
    return nil
  end

  local bus = route_for_node(node)
  if not bus then
    return nil
  end

  local channel = port.properties["audio.channel"]
  if channel == "FL" then
    return bus, "1"
  elseif channel == "FR" then
    return bus, "2"
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
    ["node.description"] = "browser/media to ardour routing",
  })

  link:activate(1)
end

local function each_ardour_input(bus, channel, callback)
  for port in ports:iterate {
    Constraint { "port.alias", "equals", "ardour:" .. bus .. "/audio_in " .. channel },
    Constraint { "port.direction", "equals", "in" },
  } do
    callback(port)
  end
end

local function each_matching_port(alias, direction, callback)
  for port in ports:iterate {
    Constraint { "port.alias", "equals", alias },
    Constraint { "port.direction", "equals", direction },
  } do
    callback(port)
  end
end

local function remove_link(link)
  local removed = pcall(function()
    link:remove()
  end)

  if not removed then
    pcall(function()
      link:request_destroy()
    end)
  end
end

local function remove_route(output_alias, input_alias)
  each_matching_port(output_alias, "out", function(output_port)
    each_matching_port(input_alias, "in", function(input_port)
      for link in links:iterate {
        Constraint { "link.output.node", "equals", output_port.properties["node.id"] },
        Constraint { "link.output.port", "equals", output_port.properties["object.id"] },
        Constraint { "link.input.node", "equals", input_port.properties["node.id"] },
        Constraint { "link.input.port", "equals", input_port.properties["object.id"] },
      } do
        remove_link(link)
      end
    end)
  end)
end

local function link_is_expected_route(output_port, input_port)
  local bus, channel = output_route(output_port)
  if not bus or not channel then
    return false
  end

  return input_port.properties["port.alias"] == "ardour:" .. bus .. "/audio_in " .. channel
end

local function remove_unwanted_firefox_links(port)
  if port.properties["port.direction"] ~= "out" then
    return
  end

  local node = lookup_node(port.properties["node.id"])
  if not node or not is_firefox_node(node) then
    return
  end

  for link in links:iterate {
    Constraint { "link.output.node", "equals", port.properties["node.id"] },
    Constraint { "link.output.port", "equals", port.properties["object.id"] },
  } do
    local input_port = lookup_port(link.properties["link.input.port"])
    if not input_port or not link_is_expected_route(port, input_port) then
      remove_link(link)
    end
  end
end

local function ensure_to_ardour(port)
  local bus, channel = output_route(port)
  if bus and channel then
    each_ardour_input(bus, channel, function(input_port)
      create_link(port, input_port)
    end)
  end

  remove_unwanted_firefox_links(port)
end

local function ensure_routes()
  for port in ports:iterate() do
    ensure_to_ardour(port)
  end

  remove_route("Firefox:output_FL", "System Sounds:playback_FL")
  remove_route("Firefox:output_FR", "System Sounds:playback_FR")
  remove_route("spotify:output_FL", "Music:playback_FL")
  remove_route("spotify:output_FR", "Music:playback_FR")
end

nodes:connect("object-added", ensure_routes)
ports:connect("object-added", ensure_routes)
links:connect("object-added", ensure_routes)

nodes:activate()
ports:activate()
links:activate()

ensure_routes()
