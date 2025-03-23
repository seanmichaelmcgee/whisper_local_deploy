# Real-Time Speech Transcription

A lightweight, GPU-accelerated real-time speech transcription application powered by OpenAI's Whisper model.

![Version](https://img.shields.io/badge/version-0.8-blue)
![Python](https://img.shields.io/badge/python-3.10+-green)
![License](https://img.shields.io/badge/license-MIT-orange)

## 🔍 Overview

This application provides real-time transcription of speech with a minimalist GTK interface. It's designed to be unobtrusive (stays on top with slight transparency) while efficiently transcribing speech in real-time using GPU acceleration when available.

This application was built primarily using iterative work with AI assistants, including Claude 3.7 Sonnet by Anthropic, which helped implement key optimizations and improvements.

The application is optimized for English transcription with technical vocabulary. It runs stably on modern hardware with decent performance on both CPU and GPU configurations. The latest updates include hardware-specific optimizations for modern NVIDIA RTX GPUs.

A green status indicator shows when the application is detecting audio input.

## ✨ Key Features

- **Real-time transcription** with OpenAI's Whisper model
- **GPU acceleration** with optimizations for modern NVIDIA GPUs
- **Two recording modes**:
  - **Normal mode**: Processes audio in 60-second chunks with 1-second overlap
  - **Long recording mode**: Captures extended speech (up to 5 minutes) before processing
- **Optimized for technical vocabulary** with priming for programming/ML terminology
- **Keyboard shortcuts** (spacebar to toggle recording in both modes)
- **Auto-clipboard copying** of transcriptions
- **Minimal, always-on-top UI** with transparency
- **Audio level visualization** for input monitoring

## 🛠️ Installation

### Prerequisites

- Python 3.10+
- CUDA-compatible GPU (recommended but not required)
- GTK3 libraries
- FFmpeg
- PortAudio

### Setup

1. **Create a virtual environment**:
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

2. **Install dependencies**:
   ```bash
   pip install --upgrade pip setuptools wheel
   pip install -r requirements.txt
   ```

3. **Install system dependencies** (if not already installed):
   ```bash
   # Ubuntu/Debian
   sudo apt-get update
   sudo apt-get install python3-gi python3-gi-cairo gir1.2-gtk-3.0 ffmpeg portaudio19-dev libcairo2-dev pkg-config python3-dev libgirepository1.0-dev
   ```

## 🚀 Usage

Run the application:
```bash
# Activate virtual environment first
source venv/bin/activate

# Run the application
python gui-v0.8.py
```

Controls:
- **Start**: Begin transcribing in normal mode (60-second chunks)
- **Long Record**: Begin extended recording session (up to 5 minutes)
- **Stop**: End recording and finalize transcription
- **Spacebar**: Toggle recording in both normal and long modes

## 🔧 Recent Enhancements

### March 2025 Update

1. **Extended Recording Durations**
   - Normal mode increased from 30 to 60 seconds
   - Long recording mode increased from 3 to 5 minutes

2. **Improved Controls**
   - Spacebar now works to stop recording in both normal and long modes
   - More responsive UI with better audio level visualization

3. **Hardware Optimizations**
   - Optimized for modern multi-core CPUs with larger chunk sizes
   - Enhanced CUDA acceleration for RTX GPUs:
     - cuDNN benchmark mode enabled
     - TF32 precision for faster computations on Ampere+ GPUs
   - Medium model option for systems with 8GB+ VRAM
   - Fine-tuned silence detection thresholds

## 🏗️ Project Structure

```
├── gui-v0.8.py           # GTK user interface
├── transcriber_v12.py    # Whisper-based transcription engine
├── requirements.txt      # Project dependencies
└── System_dependencies.md # Detailed system requirements
```

### Core Components

- **TranscriptionApp** (in gui-v0.8.py): Handles the GTK UI, button events, and UI updating
- **RealTimeTranscriber** (in transcriber_v12.py): Manages audio recording, processing, and transcription

## 🔮 Future Development

### Planned Improvements

- Fine-tuning Whisper for specific domains or vocabularies
- Adding language support beyond English
- Implementing post-processing to improve grammar and remove filler words
- UI improvements including theme support
- Containerization for easier distribution

## Distribution Notes

While AppImage distribution was explored, library compatibility issues (specifically with CUDA libraries) made this approach challenging. For now, the recommended approach is to run the application from a virtual environment after installing the necessary system dependencies.

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgements

- [OpenAI Whisper](https://github.com/openai/whisper) for the speech recognition model
- [PyTorch](https://pytorch.org/) for GPU acceleration
- [GTK](https://www.gtk.org/) for the user interface
- [Claude](https://claude.ai) by Anthropic for development assistance