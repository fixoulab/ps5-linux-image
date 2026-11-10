# Proxmox VE 9 on PS5

Build target for a headless Proxmox VE 9 image (Debian 13 "Trixie", `pve-no-subscription` repository) running on the `linux-ps5` kernel. It sits next to the existing `proxmox` target (PVE 8, Debian 12) and follows the same approach.

Unofficial community image. Not affiliated with or supported by Proxmox Server Solutions GmbH or Sony.

## Build and flash

Prerequisites are the same as for the other targets (see the main [README](../../README.md)).

```bash
./build_image.sh --distro proxmox9
sudo dd if=output/ps5-proxmox9.img of=/dev/sdX bs=4M status=progress conv=fsync
```

The first run compiles the kernel. After editing `image.yaml`, remove the cached root filesystem before rebuilding, otherwise it is reused:

```bash
sudo rm -rf work/chroot
```

Boot the image with [ps5-linux-loader](https://github.com/ps5-linux/ps5-linux-loader), like any other image from this builder.

## First boot

Plug in wired ethernet before booting (internal port or a USB adapter). WiFi is left unconfigured: Proxmox guests are bridged, and WiFi interfaces cannot be bridged reliably.

On first boot the image:

1. grows the root filesystem to fill the drive,
2. generates its own SSH host keys,
3. bridges the first wired interface into `vmbr0` and requests an address by DHCP,
4. points the node name at that address in `/etc/hosts`, which Proxmox needs before its services start.

Then open `https://<address>:8006` and log in as `root` (realm "Linux PAM"). The address is printed on the console login screen once the lease is obtained. You can also look it up on your DHCP server, or run `ip -4 addr show vmbr0` on the console.

## Defaults

| Setting | Value |
|---------|-------|
| Node name | `ps5pve` |
| Login | `root` / `proxmox` |
| SSH | root login with password enabled |
| Network | `vmbr0` on the first wired interface, DHCP |
| Swap | zram, half of RAM |

**Change the root password right after the first login** (`passwd`). The default one is public.

To use a static address, edit `vmbr0` in the web UI (or `/etc/network/interfaces`), set the node address in `/etc/hosts` yourself, and delete `/etc/dhcp/dhclient-exit-hooks.d/ps5-pve-hosts`.

## How it differs from the PVE 8 target

- Debian 13 bootstrap verified against the Debian 13 archive keys.
- Proxmox repository in deb822 format, keyring checked against the published sha256.
- `isc-dhcp-client` installed: on Debian 13, ifupdown2 has no `dhclient` by default. Its AppArmor profile is not loaded (see the comment in `image.yaml`).
- A dhclient exit hook keeps `/etc/hosts` on the leased address. pmxcfs refuses to start when the node name only resolves to a loopback address.
- The first-boot bridge setup runs before `networking.service` and retries on the next boot if no wired interface was found.
- SSH host keys are created on first boot instead of being shipped in the image.

## Kernel

Only `linux-ps5` boots the console. `proxmox-ve` is satisfied by a small stub package (`ps5-proxmox-kernel-stub`), and an apt pin in `/etc/apt/preferences.d/ps5-no-distro-kernel` blocks Proxmox and Debian kernel images. Do not remove either: any kernel package that gets installed is copied over the boot files.

`apt update && apt full-upgrade` updates Proxmox VE as usual. Kernel updates come as `linux-ps5` packages from [ps5-linux-patches](https://github.com/ps5-linux/ps5-linux-patches). Those upstream packages are built from the stock PS5 config, without the additions below.

### Config fragment

The stock PS5 kernel config is aimed at desktop use and leaves out several things Proxmox relies on. [`kernel.config`](kernel.config) is a fragment merged on top of it when this target is built:

| Section | What it brings |
|---------|----------------|
| Firewall | legacy iptables/ebtables tables and ipset, which `pve-firewall` requires |
| VLANs | 802.1Q interfaces and VLAN-aware bridges |
| Rate limit | traffic control pieces used for guest network rate limits |
| LVM | thin provisioning (LVM-thin) and classic LVM snapshots |
| Shared storage | iSCSI initiator, Ceph RBD and CephFS clients |

Almost everything is built as modules and loads on demand. The build stops if an option of the fragment does not make it into the final config. The Proxmox firewall itself stays disabled until you enable it at datacenter level, as on any fresh install.

`build_image.sh` records which fragment the cached kernel packages were built with. After the fragment changes, the next run rebuilds the kernel and the root filesystem on its own. Building another target afterwards rebuilds the kernel without the fragment.

## Known limitations

- No ZFS: it is an out-of-tree module and is not built here.
