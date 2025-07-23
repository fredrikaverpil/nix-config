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

### First-time installation

#### Prepare bootloader

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

#### Install NixOS onto NVMe SSD

This step will likely be done on your main computer (PC/Mac/Linux) for faster
build times.

1. Install Nix (if you haven't already) and enable flakes/nix-command:

   ```sh
   sh <(curl -L https://nixos.org/nix/install) --daemon
   ```

   Enable flakes: Edit `/etc/nix/nix.conf` and add the following:

   ```ini
   experimental-features = nix-command flakes

   extra-substituters = https://nixos-raspberrypi.cachix.org
   extra-trusted-public-keys = nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=
   ```

   The latter two lines will prevent very long build times, and will instead
   download builds from a binary cache. Consult the `nvmd/nixos-raspberrypi`
   repo for potential updates on the hash.

   Restart `nix-daemon` or reboot.

2. Clone the [nvmd/nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi)
   flake and build the installer image:

   ```sh
   git clone https://github.com/nvmd/nixos-raspberrypi.git
   cd nixos-raspberrypi
   ```

   Consult the
   [nvmd/nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi)
   repository's README for the exact steps. The below outlines the steps as of
   writing this.

   Replace the `# YOUR SSH PUB KEY HERE` placeholder in the `flake.nix` file,
   like this, so to gain SSH access after installation:

   ```nix
   {
        users.users.nixos.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPqX6g2... youremail@example.com"
        ];
        users.users.root.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPqX6g2... youremail@example.com"
        ];
   }
   ```

   Build the image for the Raspberry Pi 5:

   ```sh
   nix build .#installerImages.rpi5
   ```

   This will generate a symlink `result`, pointing to the generated image,
   something like
   `/nix/store/...-nixos-sd-image-.../sd-image/nixos-installer-rpi5-kernelboot.img.zst`.

3. Decompress the image:

   ```sh
   zstd -d result/sd-image/nixos-installer-rpi5-kernelboot.img.zst -o nixos-installer-rpi5.img
   ```

4. Flash the image to the NVMe SSD.

   Use `dd` (or Raspberry Pi Imager if it supports custom images) to flash:

   ```sh
   sudo dd bs=4M if=nixos-installer-rpi5.img of=/dev/nvme0n1 conv=fsync status=progress
   ```

#### Initial Boot into NixOS Installer on NVMe SSD

> [!TODO] This part is outdated and not used. Let's move it / remove it.

1. Boot Pi 5 from NVMe: Power down your Pi, remove the Raspberry Pi OS SD card,
   and power on. It should boot into the NixOS installer.
2. Connect to network. If connecting to Wifi:

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

   Note you can run without interactive mode, like `iwctl station wlan0 scan`
   etc.

3. Set root password and enable SSH: `passwd` then `systemctl enable --now sshd`
   (and find IP with ip a). SSH in from your main computer for convenience:
   `ssh nixos@<ip-address>` (or `root@...`).

#### Deploy with nixos-anywhere

From the development machine (e.g. macOS), `cd` into this repo. We will now
deploy the `flake.nix`.

1. **Install nixos-anywhere** on your development machine:

   ```sh
   nix profile install nixpkgs#nixos-anywhere
   ```

2. **Allow root password on rpi5**:

   Make sure the rpi5 is running the Raspberry OS from SD Card.

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

3. **Deploy to the Pi**:

   From the development machine:

   ```sh
   nixos-anywhere --flake .#rpi5-homelab root@raspberrypi.local
   ```

   This will:
   - Use disko to partition and format the storage
   - Build and deploy your NixOS configuration
   - Reboot into your new system

4. **SSH to your new system**:

   ```sh
   ssh fredrik@<ip-to-rpi5-homelab>
   ```

#### Maintenance

Now that the homelab is up and running, changes to the flake can be made locally
after having executed `ssh fredrik@<ip>`:

```sh
# cd into the cloned down nix-config repo

# required secrets as environment variables for now
export SECRET="value"
# ...

# Switch
sudo -H -E nixos-rebuild switch --flake .#rpi5-homelab --impure
```

Or from the development machine:

```sh
env SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)" \
    WIFI_PASSWORD="your-wifi-password" \
    FREDRIK_PASSWORD="your-password" \
    nixos-rebuild switch --flake .#rpi5-homelab --target-host fredrik@<rpi5-ip> --use-remote-sudo --impure
```
