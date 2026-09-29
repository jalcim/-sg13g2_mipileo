# sg13g2_mipileo

LibreLane top-level integration for the MIPI CSI-2 D-PHY TX/RX chip.

## Prerequisites

First, install LibreLane by following the Nix-based installation instructions: https://librelane.readthedocs.io/en/latest/installation/nix_installation/index.html

This repository contains a Nix flake that provides a shell with the [`dev`](https://github.com/librelane/librelane/tree/dev) branch of LibreLane.
To install the PDK, enable a Nix shell using `nix-shell` from the root of this repository and run `make clone-pdk`.

## Implement the Design

> [!NOTE]
> If you aren't in the Nix shell, run `nix-shell` from the root of this repository.

With this shell enabled, run the implementation:

```
make librelane
```

> [!TIP]
> Run `make librelane-nodrc` to skip the DRCs.

## View the Design

After completion, you can view the design using the OpenROAD GUI:

```
make librelane-openroad
```

Or using KLayout:

```
make librelane-klayout
```

## Credits

This design is based on https://github.com/IHP-GmbH/ihp-sg13-librelane-template/
