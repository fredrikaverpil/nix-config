# nix-config

## Folder structure proposal

As proposed by Gemini. Let's see how it turns out, as it's still just ideas and
early days.

```text
my-nix-configs/
├── flake.nix                  # Defines all inputs and outputs (systems, users, packages)
├── flake.lock                 # Pins all flake inputs (auto-generated, ALWAYS COMMIT)
├── README.md                  # Explanation of your config, setup instructions
├── .gitignore                 # Standard Nix/Git ignores
├── hosts/                     # Directory for machine-specific system configurations
│   ├── rpi5-homelab/          # Configuration for your Raspberry Pi 5
│   │   ├── default.nix        # Main system definition for RPi5
│   │   ├── hardware-configuration.nix # Hardware-specific (UUIDs, partitions) for RPi5
│   │   └── secrets.yaml       # Encrypted secrets specific to RPi5 (e.g., Netbird keys)
│   └── macbook-pro/           # Configuration for your MacBook Pro (when you adopt Nix-Darwin)
│       └── default.nix        # Main system definition for MacBook Pro
│       └── secrets.yaml       # Encrypted secrets specific to MacBook
├── home-manager/              # Directory for Home Manager user configurations
│   ├── default.nix            # Central file to import other Home Manager modules
│   ├── common.nix             # Shared user-level configs (e.g., Neovim, Git, Zsh)
│   ├── rpi5-user.nix          # Specific user configs for the RPi5 (e.g., Docker client setup)
│   ├── mac-user.nix           # Specific user configs for the Mac
├── modules/                   # Optional: Custom NixOS/Nix-Darwin modules (system-level)
│   ├── services/
│   │   └── netbird.nix        # Custom module for Netbird service setup
│   ├── networking.nix
│   └── common-system.nix      # Common system-wide settings
├── packages/                  # Optional: Custom package definitions (non-system specific)
│   └── my-custom-app/
│       └── default.nix
├── lib/                       # Optional: Custom Nix functions
│   └── default.nix
├── secrets/                   # Optional: Global encrypted secrets (if applicable)
│   └── global-secrets.yaml
└── .sops.yaml                # SOPS configuration for secret encryption/decryption
```

## rpi5-homelab

The setup has taken inspiration from:

- [Raspberry Pi 5 on NixOS wiki](https://wiki.nixos.org/wiki/NixOS_on_ARM/Raspberry_Pi_5)
- [nvmd/nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi)

### Prepare bootloader on Raspberry Pi 5

- Ensure NVMe SSD is connected.
- Boot Raspberry Pi OS from SD card.
- Update and upgrade: `sudo apt update && sudo apt full-upgrade -y`
- Enable PCIe: Edit `/boot/firmware/config.txt` and add `dtparam=pciex1`.
  Reboot.
- Verify NVMe detection: `lsblk` should show `/dev/nvme0n1`.
- Update Bootloader (EEPROM) - Crucial for NVMe Boot:
  `sudo rpi-eeprom-config --edit`
  - Change `BOOT_ORDER` to `0xf461` so either USB or SD Card takes precedence.
  - Add `PCIE_PROBE=1`.
  - Save and exit.
- Reboot.

The boot order can be translated like this:

- 4 = USB
- 6 = SD card
- 1 = NVMe

### Write NixOS installer onto NVMe SSD

On the rpi5, install Nix and enable flakes/nix-command:

```sh
sh <(curl -L https://nixos.org/nix/install) --daemon
```

Edit `/etc/nix/nix.conf` and add the following:

- `experimental-features`: add flakes support
- `trusted-users`, `extra-substituters` and `extra-trusted-public-keys`: needed
  for `nvmd/nixos-raspberrypi` build cache

```conf
experimental-features = nix-command flakes

trusted-users = root nixos fredrik
extra-substituters = https://nixos-raspberrypi.cachix.org
extra-trusted-public-keys = nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=
```

Restart `nix-daemon` or reboot.

### Deploy with nixos-anywhere

From another develpment machine (e.g. macOS), `cd` into this repo. We will now
deploy the `flake.nix` using `nixos-anywhere`. This is a one-time step for the
very first installation which includes NVMe SSD partitioning.

Install nixos-anywhere on the machine:

```sh
nix profile install nixpkgs#nixos-anywhere
```

Now we need to enable `root` password on the rpi5. Make sure the rpi5 is running
the Raspberry OS from SD Card.

```sh
# SSH into rpi5
ssh root@raspberrypi.local

# Set root password
sudo passwd root
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo systemctl restart ssh

# Add Nix to system PATH permanently
echo 'export PATH="/root/.nix-profile/bin:$PATH"' >> /etc/bash.bashrc
echo 'source /root/.nix-profile/etc/profile.d/nix.sh' >> /etc/bash.bashrc

# Also add to /etc/environment for system-wide access
echo 'PATH="/root/.nix-profile/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' >> /etc/environment

# Install nixos-install
nix-env -iA nixpkgs.nixos-install-tools

# Exit shell
exit
```

Now, let's eploy to the rpi5. From the development machine, run:

```sh
# Use disko to partition and format the storage
nixos-anywhere --flake .#rpi5-homelab --phases disko root@raspberrypi.local

# Build and deploy the NixOS configuration
nixos-anywhere --flake .#rpi5-homelab --phases install root@raspberrypi.local
```

Finally, remove the SD card from the rpi5 and reboot. It should now be possible
to SSH into the new system:

```sh
ssh fredrik@<ip-to-rpi5-homelab>
```

If you did not set the Wi-Fi password, log into the homelab locally and...

```sh
iwctl  # start iwctl in interactive mode
device list # get devices, such as 'wlan0'
station wlan0 scan # scan for networks
station wlan0 get-networks # show available networks
station wlan0 connect "YOUR_SSID" # connect (will prompt for password)
quit # exit iwctl

ip a # verify connection and get IP
systemctl is-enabled sshd  # check if sshd is enabled
systemctl is-active sshd  # check if sshd is running
```

### Maintenance

Now that the homelab is up and running, changes to the flake can be made locally
after having executed `ssh fredrik@<ip>` (you can get the ip with `ip a`):

```sh
# cd into the cloned down nix-config repo

sudo -H -E nixos-rebuild switch --flake .#rpi5-homelab --impure
```

Or from the development machine:

```sh
nixos-rebuild switch --flake .#rpi5-homelab --target-host fredrik@<rpi5-ip> --use-remote-sudo --impure
```
