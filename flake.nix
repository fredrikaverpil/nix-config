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
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-raspberrypi, disko, ... }@inputs: {
    nixosConfigurations = {
      # Your Raspberry Pi 5 homelab system configuration
      rpi5-homelab = nixos-raspberrypi.lib.nixosSystemFull {
        specialArgs = inputs // { nixos-raspberrypi = nixos-raspberrypi; };
        modules = [
          disko.nixosModules.disko
          {
            # Hardware specific configuration
            imports = with nixos-raspberrypi.nixosModules; [
              raspberry-pi-5.base
              raspberry-pi-5.display-vc4
              raspberry-pi-5.bluetooth
            ];
          }

          ({ config, pkgs, lib, ... }: 
          let
            secrets = import /etc/nixos/secrets.nix;
          in {
            networking.hostName = "rpi5-homelab";
            
            # WiFi configuration
            networking.wireless.enable = true;
            networking.wireless.networks = {
              "Attic" = {
                psk = secrets.wifiPassword;
              };
            };

            # Disko configuration for automatic partitioning
            disko.devices = {
              disk = {
                main = {
                  type = "disk";
                  device = "/dev/nvme0n1";  # NVMe SSD
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
            services.openssh.settings.PermitRootLogin = "yes";

            # SSH keys for both users
            users.users.root.openssh.authorizedKeys.keys = [
              secrets.sshPublicKey
            ];

            # Create a regular user
            users.users.fredrik = {
              isNormalUser = true;
              extraGroups = [ "wheel" "networkmanager" ];
              password = secrets.fredrikPassword;
              openssh.authorizedKeys.keys = [
                secrets.sshPublicKey
              ];
            };

            # Enable sudo for wheel group
            security.sudo.wheelNeedsPassword = false;

            # Enhanced package set for homelab use
            environment.systemPackages = with pkgs; [
              vim
              neovim
              git
              htop
              tree
              curl
              wget
              tmux
              rsync
              # Pi-specific tools available through nixos-raspberrypi
            ] ++ (with pkgs.rpi or {}; [
              # Pi-optimized packages when available
            ]);

            # System tags for identification (following nixos-raspberrypi pattern)
            system.nixos.tags = let
              cfg = config.boot.loader.raspberryPi;
            in [
              "raspberry-pi-${cfg.variant}"
              cfg.bootloader
              config.boot.kernelPackages.kernel.version
            ];

            # This is required for nixos-anywhere
            system.stateVersion = "24.05";
          })
        ];
      };
    };
  };
}
