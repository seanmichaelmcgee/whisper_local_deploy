#!/bin/bash
# Whisper Transcriber AppImage Builder
# This script creates a plug-and-play AppImage for the Whisper transcription application

set -e  # Exit on any error

# Configuration - CHANGE THESE PATHS TO MATCH YOUR ENVIRONMENT
PROJECT_ROOT="$PWD"  # Assumes script is run from project root (WHISPER_LOCAL_DEPLOY)
SRC_DIR="$PROJECT_ROOT/src"
OUTPUT_DIR="$PROJECT_ROOT/dist"
BUILD_DIR="$OUTPUT_DIR/build"
APPDIR="$BUILD_DIR/WhisperTranscriber.AppDir"
VERSION="0.6.2"  # Match your current version

echo "=== Building Whisper Transcriber AppImage v$VERSION ==="
echo "Project root: $PROJECT_ROOT"
echo "Source directory: $SRC_DIR"

# Create necessary directories
mkdir -p "$OUTPUT_DIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib/python3.8/site-packages"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps"
mkdir -p "$APPDIR/usr/share/whisper-models"

# 1. Create AppRun script (entry point)
echo "Creating AppRun entry point..."
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
# AppRun script for WhisperTranscriber

# Find the directory where this AppRun script resides
HERE="$(dirname "$(readlink -f "${0}")")"

# Set up environment variables
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
export PYTHONPATH="${HERE}/usr/lib/python3.8/site-packages:${PYTHONPATH}"
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS}"
export GI_TYPELIB_PATH="${HERE}/usr/lib/girepository-1.0:${GI_TYPELIB_PATH}"

# Set the Whisper model cache directory to our bundled models
export WHISPER_MODEL_DIR="${HERE}/usr/share/whisper-models"
export TORCH_HOME="${HERE}/usr/share/torch"

# Check for GPU before launching (optional)
if [ "$1" = "--gpu-check" ]; then
    python3 -c "import torch; print('CUDA available:', torch.cuda.is_available()); print('Device count:', torch.cuda.device_count())"
    exit $?
fi

# Launch the application
exec "${HERE}/usr/bin/python3" "${HERE}/usr/bin/whisper-transcriber" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# 2. Copy application scripts
echo "Copying application files..."
cp "$SRC_DIR/gui-v0.6.2.py" "$APPDIR/usr/bin/whisper-transcriber"
cp "$SRC_DIR/transcriber_v8.py" "$APPDIR/usr/bin/transcriber_v8.py"
chmod +x "$APPDIR/usr/bin/whisper-transcriber"

# 3. Create a launcher script to find Whisper models in the AppImage
echo "Patching application for AppImage compatibility..."
cat > "$APPDIR/usr/bin/whisper_model_patch.py" << 'EOF'
import os
import sys
import whisper
import torch

# Override the Whisper _download function to check our bundled models first
original_download = whisper._download

def patched_download(url, root, in_memory=False):
    # Extract model name from URL
    model_name = url.split("/")[-1].split(".")[0]
    # Check if we have the model in our bundled directory
    bundled_path = os.path.join(os.environ.get("WHISPER_MODEL_DIR", ""), f"{model_name}.pt")
    
    if os.path.exists(bundled_path):
        print(f"Using bundled Whisper model: {bundled_path}")
        if not in_memory:
            return bundled_path
        else:
            with open(bundled_path, "rb") as f:
                return f.read()
    else:
        # Fall back to original download function
        return original_download(url, root, in_memory)

# Apply the patch
whisper._download = patched_download

# Also patch torch hub home if needed
if "TORCH_HOME" in os.environ:
    torch.hub.set_dir(os.environ["TORCH_HOME"])
EOF

# 4. Create desktop file and icon
echo "Creating desktop entry and icon..."
cat > "$APPDIR/usr/share/applications/whisper-transcriber.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Whisper Transcriber
Comment=Real-time speech transcription with OpenAI Whisper
Exec=whisper-transcriber
Icon=whisper-transcriber
Categories=Audio;Utility;
Terminal=false
EOF

# Create a simple SVG icon (you can replace this with a better one later)
cat > "$APPDIR/usr/share/icons/hicolor/scalable/apps/whisper-transcriber.svg" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <circle cx="50" cy="50" r="45" fill="#3498db"/>
  <path d="M35,35 L35,65 M45,30 L45,70 M55,25 L55,75 M65,30 L65,70" stroke="white" stroke-width="5"/>
</svg>
EOF

# Create symlinks required by AppImage
ln -sf usr/share/applications/whisper-transcriber.desktop "$APPDIR/whisper-transcriber.desktop"
ln -sf usr/share/icons/hicolor/scalable/apps/whisper-transcriber.svg "$APPDIR/whisper-transcriber.svg"

# 5. Set up Python environment with dependencies
echo "Setting up Python environment..."
cd "$BUILD_DIR"
python3 -m venv venv
source venv/bin/activate

# Install required packages (using your requirements.txt)
pip install --upgrade pip wheel setuptools
pip install -r "$PROJECT_ROOT/requirements.txt"

# 6. Download Whisper model (small) to bundle with AppImage
echo "Downloading Whisper 'small' model..."
python -c "import whisper; whisper.load_model('small')"

# 7. Copy the model files to our bundled directory
echo "Copying Whisper model files..."
# Copy from the default cache location
WHISPER_CACHE_DIR="$HOME/.cache/whisper"
if [ -d "$WHISPER_CACHE_DIR" ]; then
    cp "$WHISPER_CACHE_DIR/small.pt" "$APPDIR/usr/share/whisper-models/"
else
    echo "Warning: Could not find Whisper model cache at $WHISPER_CACHE_DIR"
    echo "The AppImage will download the model on first run."
fi

# 8. Bundle Python interpreter and libraries
echo "Bundling Python and libraries..."
cp $(which python3) "$APPDIR/usr/bin/"
cp -r venv/lib/python3.8/site-packages/* "$APPDIR/usr/lib/python3.8/site-packages/"

# 9. Bundle necessary system libraries for GTK and audio 
echo "Bundling system libraries..."
mkdir -p "$APPDIR/usr/lib/girepository-1.0"

# GTK typelibs
cp -L /usr/lib/*/girepository-1.0/Gtk-3.0.typelib "$APPDIR/usr/lib/girepository-1.0/" 2>/dev/null || true
cp -L /usr/lib/*/girepository-1.0/Gdk-3.0.typelib "$APPDIR/usr/lib/girepository-1.0/" 2>/dev/null || true
cp -L /usr/lib/*/girepository-1.0/GLib-2.0.typelib "$APPDIR/usr/lib/girepository-1.0/" 2>/dev/null || true
cp -L /usr/lib/*/girepository-1.0/GObject-2.0.typelib "$APPDIR/usr/lib/girepository-1.0/" 2>/dev/null || true
cp -L /usr/lib/*/girepository-1.0/Gio-2.0.typelib "$APPDIR/usr/lib/girepository-1.0/" 2>/dev/null || true
cp -L /usr/lib/*/girepository-1.0/Pango-1.0.typelib "$APPDIR/usr/lib/girepository-1.0/" 2>/dev/null || true
cp -L /usr/lib/*/girepository-1.0/GdkPixbuf-2.0.typelib "$APPDIR/usr/lib/girepository-1.0/" 2>/dev/null || true
cp -L /usr/lib/*/girepository-1.0/cairo-1.0.typelib "$APPDIR/usr/lib/girepository-1.0/" 2>/dev/null || true

# Copy required libraries for PyGObject and GTK
LIBS=$(ldd $(find venv -name "_gi.*.so") | grep "=> /" | awk '{print $3}')
for lib in $LIBS; do
    cp -L "$lib" "$APPDIR/usr/lib/" 2>/dev/null || true
done

# Copy required libraries for PyAudio
LIBS=$(ldd $(find venv -name "_portaudio.*.so") | grep "=> /" | awk '{print $3}')
for lib in $LIBS; do
    cp -L "$lib" "$APPDIR/usr/lib/" 2>/dev/null || true
done

# 10. Patch import statements in the main script to use the bundled model finder
echo "Patching import statements..."
MAIN_SCRIPT="$APPDIR/usr/bin/whisper-transcriber"
sed -i '1i import whisper_model_patch' "$MAIN_SCRIPT"

# 11. Build AppImage
echo "Building AppImage..."
cd "$OUTPUT_DIR"

# Download appimagetool if not available
if [ ! -f "./appimagetool" ]; then
    echo "Downloading appimagetool..."
    wget -q -O appimagetool "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x appimagetool
fi

# Build the AppImage
./appimagetool -n "$APPDIR"

# Rename to final version
mv Whisper*.AppImage WhisperTranscriber-$VERSION-x86_64.AppImage
chmod +x WhisperTranscriber-$VERSION-x86_64.AppImage

echo "=== AppImage created successfully: $(pwd)/WhisperTranscriber-$VERSION-x86_64.AppImage ==="
echo "This AppImage includes the 'small' Whisper model for offline use."