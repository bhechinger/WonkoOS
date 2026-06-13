local reconcile_delay_ms = 500

local desired_links = {
  -- Hardware/controller MIDI into Ardour.
  { output = "Pro24-004de0:Pro24-004de0 MIDI 1", input = "ardour:physical_midi_input_monitor_enable" },
  { output = "nanoKONTROL2:nanoKONTROL2 _ CTRL", input = "ardour:physical_midi_input_monitor_enable" },
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

local links = ObjectManager {
  Interest {
    type = "link",
  }
}

local reconcile_source = nil

local function find_port(alias, direction)
  return ports:lookup {
    Constraint { "port.alias", "equals", alias },
    Constraint { "port.direction", "equals", direction },
  }
end

local function lookup_port(port_id)
  return ports:lookup {
    Constraint { "object.id", "equals", port_id },
  }
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
    ["link.async"] = true,
    ["node.description"] = "static WirePlumber MIDI link",
  })

  link:activate(1)
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

local function remove_competing_links(output_port, desired_input_port)
  for link in links:iterate {
    Constraint { "link.output.node", "equals", output_port.properties["node.id"] },
    Constraint { "link.output.port", "equals", output_port.properties["object.id"] },
  } do
    local input_port = lookup_port(link.properties["link.input.port"])
    if not input_port or input_port.properties["object.id"] ~= desired_input_port.properties["object.id"] then
      remove_link(link)
    end
  end
end

local function reconcile_links()
  for _, desired_link in ipairs(desired_links) do
    local output_port = find_port(desired_link.output, "out")
    local input_port = find_port(desired_link.input, "in")

    if output_port and input_port then
      create_link(output_port, input_port)

      if desired_link.exclusive then
        remove_competing_links(output_port, input_port)
      end
    end
  end
end

local function schedule_reconcile()
  if reconcile_source then
    reconcile_source:destroy()
  end

  reconcile_source = Core.timeout_add(reconcile_delay_ms, function()
    reconcile_source = nil
    reconcile_links()
  end)
end

ports:connect("object-added", schedule_reconcile)
ports:connect("object-removed", schedule_reconcile)
links:connect("object-added", schedule_reconcile)
links:connect("object-removed", schedule_reconcile)

ports:activate()
links:activate()

schedule_reconcile()
