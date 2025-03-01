AppImage Distribution Issues

## Problem Summary

The Whisper Transcriber AppImage fails to run with GPU acceleration due to missing CUDA libraries, specifically `libcusparseLt.so.0`. The error occurs despite NVIDIA drivers being detected on the system.

## Attempted Fixes

1. **Rebuilding the AppImage with CUDA support** - We modified the build script to include CUDA libraries and use the correct PyTorch version with CUDA support.

2. **Targeted fix script** - We created a script to extract the AppImage, add missing CUDA libraries, and rebuild it.

Neither approach resolved the issue.

## Likely Causes

1. **Local CUDA installation issues** - The required CUDA libraries may be missing or installed in non-standard locations in the local environment.

2. **PyTorch CUDA dependencies** - PyTorch has specific version requirements for CUDA libraries that may not match the installed system versions.

3. **AppImage limitations** - AppImage struggles with GPU acceleration libraries which are typically expected to be present on the host system rather than bundled.

## Common Problems with CUDA in AppImages

1. **Library isolation vs. system integration** - CUDA requires deep system integration, which conflicts with AppImage's isolation philosophy.

2. **Version compatibility** - PyTorch expects specific CUDA library versions that may differ from what's installed on the system.

3. **Library path issues** - CUDA libraries use hardcoded paths that AppImage's containment may interfere with.

## Potential Solutions

1. Use a CPU-only version as a fallback

2. Consider alternative distribution methods like Docker containers which have better support for CUDA

3. Create detailed system requirements documenting the exact CUDA versions needed

4. Install the application directly in the host system rather than using AppImage