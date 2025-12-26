{
  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
  inputs.determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
  inputs.fh.url = "https://flakehub.com/f/DeterminateSystems/fh/*.tar.gz";

  outputs =
    {
      self,
      determinate,
      nixpkgs,
      fh,
      ...
    }:
    let
      forSystems =
        s: f:
        nixpkgs.lib.genAttrs s (
          system:
          f rec {
            inherit system;
            pkgs = nixpkgs.legacyPackages.${system};
          }
        );

      forAllSystems = forSystems [
        "aarch64-darwin"
        "x86_64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
      forLinuxSystems = forSystems [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      devShells = forAllSystems (
        { system, pkgs, ... }:
        {
          default = pkgs.mkShellNoCC {
            buildInputs = with pkgs; [
              nixfmt-rfc-style
            ];
          };
        }
      );

      packages = forLinuxSystems (
        { system, ... }:
        {
          toplevel = self.nixosConfigurations.${system}.install.config.system.build.toplevel;
          iso = self.nixosConfigurations.${system}.install.config.system.build.isoImage;
        }
      );

      nixosConfigurations = forLinuxSystems (
        { system, ... }:
        {
          install = nixpkgs.lib.nixosSystem {
            system = system;
            modules = [
              # Load the Determinate module
              determinate.nixosModules.default
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal-combined.nix"
              (
                {
                  options,
                  pkgs,
                  lib,
                  ...
                }:
                {
                  environment.systemPackages = [ fh.packages.${pkgs.stdenv.hostPlatform.system}.default ];
                  environment.etc."nixos/flake.nix" = {
                    source = ./flake.nix;
                    mode = "0644";
                  };
                  environment.etc."nixos/flake.lock" = {
                    source = ./flake.lock;
                    mode = "0644";
                  };
                  environment.etc."nixos-generate-config.conf".text = ''
                    [Defaults]
                    Flake=1
                  '';

                  networking.wireless.enable = lib.mkForce false;
                  networking.networkmanager.enable = true;

                  # ===== UTM/QEMU Guest Support =====

                  # SPICE guest tools for clipboard, display resize, etc.
                  services.spice-vdagentd.enable = true;
                  services.qemuGuest.enable = true;

                  # VirtFS (9p) support for shared folders
                  boot.kernelModules = [ "9p" "9pnet_virtio" "virtio_pci" "virtio_blk" ];
                  boot.initrd.availableKernelModules = [ "9p" "9pnet_virtio" "virtio_pci" "virtio_blk" ];

                  # ===== ZFS Support =====
                  # Pin to kernel 6.12 for ZFS compatibility (nixpkgs ZFS 2.3.x supports up to 6.12)
                  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;
                  # Use mkForce to override latest-kernel specialisation which disables ZFS
                  boot.supportedFilesystems = lib.mkForce [ "btrfs" "reiserfs" "vfat" "f2fs" "xfs" "ntfs" "cifs" "zfs" ];
                  # hostId is required for ZFS - generate a random one for the live ISO
                  networking.hostId = "8425e349";

                  # ===== VMware Guest Support (kept for compatibility) =====
                  virtualisation.vmware.guest.enable = true;

                  system.nixos-generate-config.flake = ''
                    {
                      inputs = {
                        determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
                        nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # NixOS, rolling release
                        # nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # NixOS, current stable
                      };
                      outputs = inputs\@{ self, nixpkgs, determinate, ... }: {
                        # NOTE: '${options.networking.hostName.default}' is the default hostname
                        nixosConfigurations.${options.networking.hostName.default} = nixpkgs.lib.nixosSystem {
                          modules = [
                            determinate.nixosModules.default
                            ./configuration.nix
                          ];
                        };
                      };
                    }
                  '';
                }
              )
            ];
          };
        }
      );
    };
}
