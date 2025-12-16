Dependencies: Kubgrupp relies on `glslc` to compile the shaders.

To run the renderer, call `./run.sh <scene>`. This script
- compiles shaders
- compiles the Rust project
- runs the renderer

The scenes corresponding to our submission are:
- `kubgrupp.toml`, Fig. 1
- `prism.toml`, Fig. 2
- `diffraction.toml`, Fig. 3
- `b1-through-b5.toml`, Fig. 4
- `several-lights.toml`, Fig. 5
- `rgb.toml`, Fig. 6
- `light-spectra.toml`, Fig. 7

The scene files are located in `resources/scenes`.
