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
      rpi5-homelab = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = inputs // { nixos-raspberrypi = nixos-raspberrypi; };
        modules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          {
            # Hardware specific configuration
            imports = with nixos-raspberrypi.nixosModules; [
              raspberry-pi-5.base
              raspberry-pi-5.bluetooth
            ];
          }

          ({ config, pkgs, lib, ... }: {
            networking.hostName = "rpi5-homelab";
            
            # WiFi configuration
            networking.wireless.enable = true;
            networking.wireless.networks = {
              "Attic" = {
                psk = builtins.getEnv "WIFI_PASSWORD";
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
            services.openssh.settings.PermitRootLogin = "no";

            # Enable Docker
            virtualisation.docker.enable = true;

            # SSH keys for both users
            users.users.root.openssh.authorizedKeys.keys = [
              (builtins.getEnv "SSH_PUBLIC_KEY")
            ];

            # Create a regular user
            users.users.fredrik = {
              isNormalUser = true;
              extraGroups = [ "wheel" "networkmanager" "docker" ];
              password = builtins.getEnv "FREDRIK_PASSWORD";
              openssh.authorizedKeys.keys = [
                (builtins.getEnv "SSH_PUBLIC_KEY")
              ];
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
