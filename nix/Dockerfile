FROM nixos/nix:2.34.1

# filter-syscalls: seccomp filtering breaks Nix builds inside Docker
RUN mkdir -p /etc/nix && \
    echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf && \
    echo "filter-syscalls = false" >> /etc/nix/nix.conf && \
    echo "system-features = kvm nixos-test benchmark big-parallel" >> /etc/nix/nix.conf && \
    git config --global --add safe.directory /workspace

WORKDIR /workspace

ENTRYPOINT ["nix"]
CMD ["--help"]
