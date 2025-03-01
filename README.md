# Real-Time Speech Transcription

A lightweight, GPU-accelerated real-time speech transcription application powered by OpenAI's Whisper model.

![Version](https://img.shields.io/badge/version-0.6.2-blue)
![Python](https://img.shields.io/badge/python-3.8+-green)
![License](https://img.shields.io/badge/license-MIT-orange)

## 🔍 Overview

This application provides real-time transcription of speech with a minimalist GTK interface. It's designed to be unobtrusive (stays on top with slight transparency) while efficiently transcribing speech in real-time using GPU acceleration when available.

This application was built primarily using iterative work on consumer-level LLMs and reasoner models, particularly OpenAI o3-mini-high and GPT 4o, as well as Claude 3.7 Thinking by Anthropic.

The application is optimized for English and transcription only. This can easily be adjusted in the transcriber code. This application runs stably in Ubuntu 24.04 on PC with NVIDIA 1660 Ti, 6GB of VRAM, and a 9th generation Intel i7. Enjoy!

A green status bar was added so you know when it is detecting audio.

Given distribution issue, at present to run I recommend a fresh terminal, activating VENV in your PATH, and running gui-v0.8.py,

## ✨ Features

- **Real-time transcription** with OpenAI's Whisper model
- **GPU acceleration** for improved performance
- **Two recording modes**:
  - **Normal mode**: Processes audio in 30-second chunks with 1-second overlap
  - **Long recording mode**: Captures extended speech (up to 3 minutes) before processing
- **Optimized for technical vocabulary** with priming for programming/ML terminology
- **Keyboard shortcuts** (spacebar to toggle recording in normal mode)
- **Auto-clipboard copying** of transcriptions
- **Minimal, always-on-top UI** with transparency

## 🛠️ Installation

### Prerequisites

- Python 3.8+
- CUDA-compatible GPU (recommended but not required)
- GTK3 libraries
- FFmpeg

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
   sudo apt-get install python3-gi python3-gi-cairo gir1.2-gtk-3.0 ffmpeg
   
   # macOS
   brew install pygobject3 gtk+3 ffmpeg
   ```

## 🚀 Usage

Run the application:
```bash
python gui-v0.6.2.py
```

Controls:
- **Start**: Begin transcribing in normal mode
- **Long Record**: Begin extended recording session
- **Stop**: End recording and finalize transcription
- **Spacebar**: Toggle recording in normal mode

## 🏗️ Project Structure

```
├── gui-v0.6.2.py         # GTK user interface
├── transcriber_v8.py     # Whisper-based transcription engine
└── requirements.txt      # Project dependencies
```

### Core Components

- **TranscriptionApp** (in gui-v0.6.2.py): Handles the GTK UI, button events, and UI updating
- **RealTimeTranscriber** (in transcriber_v8.py): Manages audio recording, processing, and transcription

## 🔮 Future Development

### Docker Containerization

The next development phase will focus on containerizing this application:

- Create a Dockerfile optimized for GPU passthrough
- Ensure CUDA compatibility in the container
- Minimize image size by removing unnecessary dependencies
- Add volume mounting for persistent storage of transcriptions
- Implement environment variables for configuration

### Other Planned Improvements

- Fine-tuning Whisper for specific domains or vocabularies
- Adding language support beyond English
- Implementing post-processing to improve grammar and remove filler words
- UI improvements including theme support

## Distrubution

Library issues, specifically libcusparseLt.so.0, prevent the CUDA optimization from working with a AppImage distrubution. Issues would abound with Linux builds. etc. Conatainerized distribution is a posibility, but already requires a higher level of user knowledge. Perhaps ONNX doesn't require as much? Build would then have to be from system code level, and would ltake a lot of optimzation.

In the meantime recommend terminal based run within virtual environemnt after installing dependencies.


## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgements

- [OpenAI Whisper](https://github.com/openai/whisper) for the speech recognition model
- [PyTorch](https://pytorch.org/) for GPU acceleration
- [GTK](https://www.gtk.org/) for the user interface
