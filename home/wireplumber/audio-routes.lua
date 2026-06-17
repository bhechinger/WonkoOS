local reconcile_delay_ms = 500

local desired_links = {
  -- Route selected app streams directly into Ardour and remove their default sink links.
  { output = "spotify:output_FL",             input = "ardour:Music/audio_in 1",   exclusive = true },
  { output = "spotify:output_FR",             input = "ardour:Music/audio_in 2",   exclusive = true },
  { output = "Firefox:output_FL",             input = "ardour:Firefox/audio_in 1", exclusive = true },
  { output = "Firefox:output_FR",             input = "ardour:Firefox/audio_in 2", exclusive = true },

  -- Feed PipeWire-owned virtual sinks into matching Ardour buses.
  { output = "System Sounds:monitor_FL",      input = "ardour:System/audio_in 1" },
  { output = "System Sounds:monitor_FR",      input = "ardour:System/audio_in 2" },
  { output = "Games:monitor_FL",              input = "ardour:Games/audio_in 1" },
  { output = "Games:monitor_FR",              input = "ardour:Games/audio_in 2" },
  { output = "Music:monitor_FL",              input = "ardour:Music/audio_in 1" },
  { output = "Music:monitor_FR",              input = "ardour:Music/audio_in 2" },

  -- Feed Ardour's master bus into the PipeWire-owned virtual source.
  { output = "ardour:Mic/audio_out 1",        input = "Ardour:input_FL" },
  { output = "ardour:Mic/audio_out 2",        input = "Ardour:input_FR" },

  -- Feed Ardour's outputs into the Saffire
  { output = "ardour:Master/audio_out 1",     input = "saffire_ffado_output:00130e0401c04de0_1394/In:01 (Mixer/In:17)_in" },
  { output = "ardour:Master/audio_out 2",     input = "saffire_ffado_output:00130e0401c04de0_1394/In:02 (Mixer/In:18)_in" },
  { output = "ardour:auditioner/audio_out 1", input = "saffire_ffado_output:00130e0401c04de0_1394/In:01 (Mixer/In:17)_in" },
  { output = "ardour:auditioner/audio_out 2", input = "saffire_ffado_output:00130e0401c04de0_1394/In:02 (Mixer/In:18)_in" },
  { output = "ardour:Click/audio_out 1",      input = "saffire_ffado_output:00130e0401c04de0_1394/In:01 (Mixer/In:17)_in" },
  { output = "ardour:Click/audio_out 2",      input = "saffire_ffado_output:00130e0401c04de0_1394/In:02 (Mixer/In:18)_in" },

  -- Feed the Saffire inputs into Ardour
  { output = "saffire_ffado_input:00130e0401c04de0_1394/Out:01 (Anlg/In:03)_out",  input = "ardour:Mic/audio_in 1" },
  { output = "saffire_ffado_input:00130e0401c04de0_1394/Out:05 (SPDIF/In:01)_out", input = "ardour:Mac/audio_in 1" },
  { output = "saffire_ffado_input:00130e0401c04de0_1394/Out:06 (SPDIF/In:02)_out", input = "ardour:Mac/audio_in 2" },
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
    ["node.description"] = "static WirePlumber audio link",
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
