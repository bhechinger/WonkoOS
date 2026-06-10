{ pkgs, config, ... }:
let
  ardourPipewire = pkgs.symlinkJoin {
    name = "ardour-pipewire";
    paths = [ pkgs.ardour ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/ardour9 \
        --prefix LD_LIBRARY_PATH : ${pkgs.pipewire.jack}/lib
    '';
  };

  battletechGamesRule = ''
    stream.rules = [
      {
        matches = [
          {
            application.name = "BattleTech"
            media.class = "Stream/Output/Audio"
          }
          {
            node.name = "BattleTech"
            media.class = "Stream/Output/Audio"
          }
          {
            application.process.binary = "BattleTech"
            media.class = "Stream/Output/Audio"
          }
        ]
        actions = {
          update-props = {
            target.object = "Games"
            node.dont-move = true
            state.restore-target = false
          }
        }
      }
    ]
  '';

  directStreamsRule = ''
    stream.rules = [
      {
        matches = [
          {
            application.name = "Firefox"
            media.class = "Stream/Output/Audio"
          }
          {
            application.name = "spotify"
            media.class = "Stream/Output/Audio"
          }
        ]
        actions = {
          update-props = {
            node.autoconnect = false
            state.restore-target = false
            node.dont-move = true
          }
        }
      }
    ]
  '';

in
{
  home.packages = with pkgs; [
    carla
    qpwgraph
    ardourPipewire
    pipewire.jack
    rnnoise-plugin.lv2
    lmms
    lsp-plugins
    show-midi
    audacious
    pavucontrol
    spotify
  ];
  xdg.configFile."autostart/org.rncbc.qpwgraph.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Categories=AudioVideo;Audio;Video;Midi;X-Alsa;X-PipeWire;Qt;
      Comment=qpwgraph is a PipeWire graph Qt GUI interface
      Exec=qpwgraph -d -m
      GenericName=PipeWire Graph Viewer
      Icon=org.rncbc.qpwgraph
      Keywords=PipeWire;MIDI;ALSA;JACK;Qt;
      Name=qpwgraph
      StartupNotify=true
      Terminal=false
      Type=Application
      Version=1.0
    '';
  };

  systemd.user.services.ardour-default = {
    Unit = {
      Description = "Ardour Default session";
      Wants = [
        "pipewire.service"
        "wireplumber.service"
      ];
      After = [
        "pipewire.service"
        "wireplumber.service"
      ];
      PartOf = [
        "hyprland-session.target"
        "pipewire.service"
        "wireplumber.service"
      ];
    };

    Service = {
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
      ExecStart = "${ardourPipewire}/bin/ardour9 /home/wonko/Default";
      KillSignal = "SIGINT";
      Restart = "on-failure";
      RestartSec = 5;
      SuccessExitStatus = "SIGINT";
      TimeoutStopSec = 120;
    };

    Install.WantedBy = [ "hyprland-session.target" ];
  };

  xdg.configFile."pipewire/pipewire.conf.d/10-null-sink.conf" = {
    force = true;
    text = ''
      context.objects = [
          {   factory = adapter
              args = {
                 factory.name     = support.null-audio-sink
                 node.name        = "System Sounds"
                 node.description = "System Sounds"
                 media.class      = Audio/Sink
                 object.linger    = true
                 audio.position   = [ FL FR ]
                 monitor.channel-volumes = true
              }
          }
          {   factory = adapter
              args = {
                 factory.name     = support.null-audio-sink
                 node.name        = "Games"
                 node.description = "Games"
                 media.class      = Audio/Sink
                 object.linger    = true
                 audio.position   = [ FL FR ]
                 monitor.channel-volumes = true
              }
          }
          {   factory = adapter
              args = {
                 factory.name     = support.null-audio-sink
                 node.name        = "Music"
                 node.description = "Music"
                 media.class      = Audio/Sink
                 object.linger    = true
                 audio.position   = [ FL FR ]
                 monitor.channel-volumes = true
              }
          }
      ]
    '';
  };

  xdg.configFile."pipewire/pipewire.conf.d/11-null-source.conf" = {
    force = true;
    text = ''
      context.objects = [
          {   factory = adapter
              args = {
                 factory.name     = support.null-audio-sink
                 node.name        = "Ardour"
                 node.description = "Ardour"
                 media.class      = Audio/Source/Virtual
                 object.linger    = true
                 audio.position   = [ FL FR ]
                 monitor.channel-volumes = true
              }
          }
      ]
    '';
  };

  # I don't know why all three of these are required, but it doesn't work without them.
  xdg.configFile."pipewire/client.conf.d/52-battletech-games.conf".text = battletechGamesRule;
  xdg.configFile."pipewire/pipewire-pulse.conf.d/52-battletech-games.conf".text = battletechGamesRule;
  xdg.configFile."wireplumber/wireplumber.conf.d/52-battletech-games.conf".text = battletechGamesRule;

  xdg.configFile."pipewire/client.conf.d/53-ardour-direct-streams.conf".text = directStreamsRule;
  xdg.configFile."pipewire/pipewire-pulse.conf.d/53-ardour-direct-streams.conf".text =
    directStreamsRule;
  xdg.configFile."wireplumber/wireplumber.conf.d/53-ardour-direct-streams.conf".text =
    directStreamsRule;

  xdg.configFile."wireplumber/scripts/89-ardour-default-routing.lua".text = ''
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

    local routes = {
      { "System Sounds:monitor_FL", "ardour:System/audio_in 1" },
      { "System Sounds:monitor_FR", "ardour:System/audio_in 2" },
      { "Games:monitor_FL", "ardour:Games/audio_in 1" },
      { "Games:monitor_FR", "ardour:Games/audio_in 2" },
      { "Music:monitor_FL", "ardour:Music/audio_in 1" },
      { "Music:monitor_FR", "ardour:Music/audio_in 2" },
      { "Firefox:output_FL", "ardour:System/audio_in 1" },
      { "Firefox:output_FR", "ardour:System/audio_in 2" },
      { "spotify:output_FL", "ardour:Music/audio_in 1" },
      { "spotify:output_FR", "ardour:Music/audio_in 2" },
      { "alsa_input.firewire-0x00130e0401c04de0.multichannel-input:capture_AUX0", "ardour:Mic/audio_in 1" },
      { "Midi-Bridge:nanoKONTROL2: _ CTRL (capture)", "ardour:MIDI Control In" },
      { "ardour:Master/audio_out 1", "alsa_output.firewire-0x00130e0401c04de0.multichannel-output:playback_FL" },
      { "ardour:Master/audio_out 2", "alsa_output.firewire-0x00130e0401c04de0.multichannel-output:playback_FR" },
    }

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
        ["node.description"] = "ardour default routing",
      })

      link:activate(1)
    end

    local function each_matching_port(alias, direction, callback)
      for port in ports:iterate {
        Constraint { "port.alias", "equals", alias },
        Constraint { "port.direction", "equals", direction },
      } do
        callback(port)
      end
    end

    local function ensure_route(output_alias, input_alias)
      each_matching_port(output_alias, "out", function(output_port)
        each_matching_port(input_alias, "in", function(input_port)
          create_link(output_port, input_port)
        end)
      end)
    end

    local function ensure_routes()
      for _, route in ipairs(routes) do
        ensure_route(route[1], route[2])
      end
    end

    ports:connect("object-added", ensure_routes)
    links:connect("object-added", ensure_routes)
    ports:activate()
    links:activate()
    ensure_routes()
  '';

  xdg.configFile."wireplumber/wireplumber.conf.d/89-ardour-default-routing.conf".text = ''
    wireplumber.components = [
      {
        name = "${config.home.homeDirectory}/.config/wireplumber/scripts/89-ardour-default-routing.lua", type = script/lua
        provides = custom.ardour-default-routing
        requires = [ support.lua-scripting ]
      }
    ]

    wireplumber.profiles = {
      main = {
        custom.ardour-default-routing = required
      }
    }
  '';

  xdg.configFile."wireplumber/scripts/90-spotify-midi-control-link.lua".text = ''
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

    local output_name = "nanoKONTROL2: _ CTRL (capture)"
    local input_alias = "spotify-midi-control:input_1"

    local function lookup_output_port()
      return ports:lookup {
        Constraint { "port.name", "equals", output_name },
        Constraint { "port.direction", "equals", "out" },
      }
    end

    local function lookup_input_port()
      return ports:lookup {
        Constraint { "port.alias", "equals", input_alias },
        Constraint { "port.direction", "equals", "in" },
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

    local function ensure_link()
      local output_port = lookup_output_port()
      local input_port = lookup_input_port()

      if not output_port or not input_port or link_exists(output_port, input_port) then
        return
      end

      local link = Link("link-factory", {
        ["link.output.node"] = output_port.properties["node.id"],
        ["link.output.port"] = output_port.properties["object.id"],
        ["link.input.node"] = input_port.properties["node.id"],
        ["link.input.port"] = input_port.properties["object.id"],
        ["object.id"] = nil,
        ["object.linger"] = true,
        ["node.description"] = "spotify-midi-control nanoKONTROL2 link",
      })

      link:activate(1)
    end

    ports:connect("object-added", ensure_link)
    links:connect("object-added", ensure_link)
    ports:activate()
    links:activate()
    ensure_link()
  '';

  xdg.configFile."wireplumber/wireplumber.conf.d/90-spotify-midi-control-link.conf".text = ''
    wireplumber.components = [
      {
        name = "${config.home.homeDirectory}/.config/wireplumber/scripts/90-spotify-midi-control-link.lua", type = script/lua
        provides = custom.spotify-midi-control-link
        requires = [ support.lua-scripting ]
      }
    ]

    wireplumber.profiles = {
      main = {
        custom.spotify-midi-control-link = required
      }
    }
  '';

  services = {
    spotifyd = {
      enable = true;
      settings = {
        global = {
          bitrate = 320;
          username = "";
          password = "";
          backend = "pulseaudio";
          device = "pipewire";
          control = "pipewire";
          device_type = "computer";
          device_name = "deepthought";
        };
      };
    };
    spotify-midi-control = {
      enable = true;
      backend = "pipewire";

      midiCommands = {
        play = [
          176
          41
          127
        ];
        pause = [
          176
          42
          127
        ];
        previous = [
          176
          58
          127
        ];
        next = [
          176
          59
          127
        ];
      };
    };
  };
}
