# MyTranscribe Development Guide

## Usage Commands
- Run application: `python gui-v0.8.py`
- Setup virtual environment: `python3 -m venv venv && source venv/bin/activate`
- Install dependencies: `pip install -r requirements.txt`
- Install system dependencies: `sudo apt-get install python3-gi python3-gi-cairo gir1.2-gtk-3.0 ffmpeg portaudio19-dev libcairo2-dev pkg-config python3-dev libgirepository1.0-dev`

## Key Features and Implementation
- **60-second normal recording**: Modified `DEFAULT_CHUNK_DURATION` in transcriber_v12.py
- **5-minute long recording**: Changed auto-stop timeout from 180 to 300 seconds
- **Spacebar control for all modes**: Removed mode restriction in `on_key_press` handler
- **Hardware optimizations**:
  - Increased CHUNK size to 2048 for better multi-core CPU performance
  - Enabled GPU optimizations for RTX cards:
    - cuDNN benchmark mode: `torch.backends.cudnn.benchmark = True`  
    - TF32 precision: `torch.backends.cuda.matmul.allow_tf32 = True`
  - Upgraded to "medium" Whisper model for systems with 8GB+ VRAM
  - Adjusted silence detection thresholds to 350
  - Enhanced audio visualization timing

## Hardware Compatibility
- **CPU**: Optimized for modern multi-core processors (e.g., Intel i7/i9, AMD Ryzen)
- **GPU**: Best performance with NVIDIA RTX 20/30/40 series cards (8GB+ VRAM)
- **Memory**: Recommended 16GB+ system RAM
- **Audio**: Compatible with most microphones/audio interfaces via PortAudio

## Code Style Guidelines
- **Formatting**: Use 4-space indentation
- **Naming**: Use snake_case for functions/variables, CamelCase for classes
- **Imports**: Group standard library, third-party, and local imports with blank lines between groups
- **Error Handling**: Use try/except blocks with specific exceptions and logging
- **Documentation**: Document functions with docstrings explaining purpose and parameters
- **Type Hints**: Not currently used but encouraged for new code
- **Logging**: Use the logging module with appropriate levels (info, error)
- **UI Components**: Follow GTK3 widget patterns with consistent styling
- **Audio Processing**: Document chunk size, format, and rate when modified

## Development History
- **March 2025**: Extended recording durations, improved spacebar control, hardware optimizations (implemented with Claude 3.7 Sonnet)
- **Earlier**: Initial application development with real-time transcription capabilities

## Troubleshooting Common Issues
- **No audio detection**: Check microphone setup with `arecord -l`
- **Slow transcription**: Verify GPU is being used (`logging.info` will show GPU status)
- **GTK errors**: Ensure GTK3 and required libraries are installed system-wide
- **CUDA issues**: Check compatible CUDA toolkit is installed