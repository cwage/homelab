{ ... }:

# Disk layout for xmpp1, consumed by nixos-anywhere at install time.
#
# NO PARTITION TABLE — the ext4 filesystem sits directly on the raw device.
# This is not an oversight; it is the load-bearing line of this file.
#
# Linode's "GRUB 2" boot mode runs THEIR grub on the host (2.12 as of this
# writing), which loads the guest's config from the fixed path
# (hd0)/boot/grub/grub.cfg — i.e. it expects the filesystem directly on the
# bare disk, because Linode's own images are partitionless. There is no search
# fallback: with a partition table (GPT *or* MBR), the config lives at
# (hd0,partN)/... where their grub never looks, and the box wedges silently at
# a busy-waiting `grub>` prompt that only Lish can see. The install itself
# reports success. This cost four install cycles to diagnose; see docs/xmpp.md.
#
# The matching half in configuration.nix: boot.loader.grub.device = "nodev" +
# forceInstall — write the config, install no bootloader (there is nowhere to
# put one, and nothing would run it anyway).
{
  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "filesystem";
      format = "ext4";
      mountpoint = "/";
      # Their host grub is 2.12 today, which reads modern ext4 features fine —
      # but the grub version is Linode's choice, not ours, and can differ after
      # a host migration. Formatting without post-1.47 e2fsprogs defaults costs
      # nothing and removes the risk class.
      extraArgs = [ "-O" "^orphan_file,^metadata_csum_seed" ];
    };
  };
}
