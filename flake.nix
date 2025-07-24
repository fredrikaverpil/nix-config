{
  description = "Fredrik's NixOS configuration with Raspberry Pi support";

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-raspberrypi, disko, home-manager, ... }@inputs: {
    nixosConfigurations = {
      # Your Raspberry Pi 5 homelab system configuration
      rpi5-homelab = nixos-raspberrypi.lib.nixosSystemFull {
        specialArgs = inputs // { nixos-raspberrypi = nixos-raspberrypi; };
        modules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          {
            # Hardware specific configuration
            imports = with nixos-raspberrypi.nixosModules; [
              raspberry-pi-5.base
              raspberry-pi-5.display-vc4
              raspberry-pi-5.bluetooth
            ];
          }

          ({ config, pkgs, lib, ... }: {
            networking.hostName = "rpi5-homelab";

            # WiFi configuration using NetworkManager (conflicts resolved)
            networking.networkmanager.enable = true;
            networking.networkmanager.wifi.backend = "iwd";
            # networking.networkmanager.ensureProfiles = {
            #   environmentFiles = [ "/etc/NetworkManager/profiles.env" ];
            #   profiles = {
            #     "my-wifi" = {
            #       connection = {
            #         id = "my-wifi";
            #         type = "wifi";
            #         autoconnect = true;
            #       };
            #       wifi = {
            #         ssid = "$WIFI_SSID";
            #         mode = "infrastructure";
            #       };
            #       wifi-security = {
            #         key-mgmt = "wpa-psk";
            #         psk = "$WIFI_PASSWORD";
            #       };
            #       ipv4 = {
            #         method = "auto";
            #       };
            #     };
            #   };
            # };

            # Disko configuration for automatic partitioning
            disko.devices = {
              disk = {
                main = {
                  type = "disk";
                  device = "/dev/nvme0n1"; # NVMe SSD
                  content = {
                    type = "gpt";
                    partitions = {
                      firmware = {
                        size = "512M";
                        type = "EF00";
                        content = {
                          type = "filesystem";
                          format = "vfat";
                          mountpoint = "/boot/firmware";
                        };
                      };
                      root = {
                        size = "100%";
                        content = {
                          type = "filesystem";
                          format = "ext4";
                          mountpoint = "/";
                        };
                      };
                    };
                  };
                };
              };
            };

            # Enable SSH
            services.openssh.enable = true;
            services.openssh.settings.PermitRootLogin = "no";

            # Enable Docker
            virtualisation.docker.enable = true;

            # Create a regular user
            users.users.fredrik = {
              isNormalUser = true;
              extraGroups = [ "wheel" "networkmanager" "docker" ];
              password = "changeme";
              # openssh.authorizedKeys.keys = [
              #   # Add your SSH public keys here
              # ];
            };

            # Enable sudo for wheel group
            security.sudo.wheelNeedsPassword = false;

            # Enhanced package set for homelab use
            environment.systemPackages = with pkgs; [
              vim
              git
              htop
              rsync
              docker-compose
              iwd # provides iwctl
              # Pi-specific tools available through nixos-raspberrypi
            ] ++ (with pkgs.rpi or { }; [
              # Pi-optimized packages when available
            ]);

            # System tags for identification (following nixos-raspberrypi pattern)
            system.nixos.tags =
              let
                cfg = config.boot.loader.raspberryPi;
              in
              [
                "raspberry-pi-${cfg.variant}"
                cfg.bootloader
                config.boot.kernelPackages.kernel.version
              ];

            # Home Manager configuration
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.fredrik = { pkgs, ... }: {
                home.packages = with pkgs; [
                  neovim
                  tmux
                  tree
                  curl
                  wget
                  lazygit
                ];

                programs.git = {
                  enable = true;
                  userName = "Fredrik Averpil";
                  userEmail = "fredrik.averpil@gmail.com";
                };

                home.stateVersion = "25.05";
              };
            };

            # This is required for nixos-anywhere
            system.stateVersion = "25.05";
          })
        ];
      };
    };
  };
}
