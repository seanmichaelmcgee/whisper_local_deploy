#!/bin/bash
# Lean Whisper Transcriber AppImage Builder (Updated for v0.8)
# This script creates a minimal AppImage that downloads the model on first run

set -e  # Exit on any error

# Configuration - CHANGE THESE PATHS TO MATCH YOUR ENVIRONMENT
PROJECT_ROOT="$PWD"  # Assumes script is run from project root (WHISPER_LOCAL_DEPLOY)
SRC_DIR="$PROJECT_ROOT/src"
OUTPUT_DIR="$PROJECT_ROOT/dist"
BUILD_DIR="$OUTPUT_DIR/build"
APPDIR="$BUILD_DIR/WhisperTranscriber.AppDir"
VERSION="0.8.0"  # Updated version number

echo "=== Building Lean Whisper Transcriber AppImage v$VERSION ==="
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

# Set the Whisper model cache directory to a user-accessible location
# This allows the model to persist between application runs
MODEL_DIR="$HOME/.cache/whisper-transcriber"
mkdir -p "$MODEL_DIR"
export WHISPER_CACHE_DIR="$MODEL_DIR"

# Launch the application with the first-run model setup
exec "${HERE}/usr/bin/python3" "${HERE}/usr/bin/whisper-transcriber" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# 2. Copy application scripts - Updated to use v0.8 and v12
echo "Copying application files..."
cp "$SRC_DIR/gui-v0.8.py" "$APPDIR/usr/bin/whisper-transcriber"
cp "$SRC_DIR/transcriber_v12.py" "$APPDIR/usr/bin/transcriber_v12.py"
chmod +x "$APPDIR/usr/bin/whisper-transcriber"

# 3. Create a first-run script that will display a progress dialog 
echo "Creating first-run helper script..."
cat > "$APPDIR/usr/bin/first_run_helper.py" << 'EOF'
import os
import sys
import threading
import time
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib

class ModelDownloadDialog:
    def __init__(self):
        self.builder = Gtk.Builder()
        
        # Create dialog programmatically
        self.dialog = Gtk.Dialog(
            title="Downloading Whisper Model",
            flags=Gtk.DialogFlags.MODAL
        )
        self.dialog.set_default_size(400, 150)
        self.dialog.set_position(Gtk.WindowPosition.CENTER)
        
        # Add content area with messages
        content_area = self.dialog.get_content_area()
        content_area.set_spacing(10)
        content_area.set_margin_top(15)
        content_area.set_margin_bottom(15)
        content_area.set_margin_start(15)
        content_area.set_margin_end(15)
        
        # Add a label explaining what's happening
        self.label = Gtk.Label()
        self.label.set_markup("<b>Downloading Whisper Model</b>\n\nThis will only happen once. Please wait...")
        self.label.set_justify(Gtk.Justification.CENTER)
        content_area.add(self.label)
        
        # Add a progress bar
        self.progress = Gtk.ProgressBar()
        self.progress.set_pulse_step(0.1)
        content_area.add(self.progress)
        
        # Add status message
        self.status_label = Gtk.Label()
        self.status_label.set_text("Preparing download...")
        content_area.add(self.status_label)
        
        # Show all widgets
        self.dialog.show_all()
        
    def start_progress_pulse(self):
        def update_progress():
            self.progress.pulse()
            return True
            
        self.progress_id = GLib.timeout_add(100, update_progress)
        
    def stop_progress_pulse(self):
        if hasattr(self, 'progress_id'):
            GLib.source_remove(self.progress_id)
            
    def update_status(self, message):
        def do_update():
            self.status_label.set_text(message)
            return False
            
        GLib.idle_add(do_update)
        
    def close(self):
        def do_close():
            self.stop_progress_pulse()
            self.dialog.destroy()
            return False
            
        GLib.idle_add(do_close)

def download_model_with_progress():
    dialog = ModelDownloadDialog()
    dialog.start_progress_pulse()
    
    def do_download():
        try:
            dialog.update_status("Importing Whisper...")
            import whisper
            
            dialog.update_status("Downloading model (this may take a few minutes)...")
            # Load the small model - this will download it if not present
            model = whisper.load_model("small")
            
            dialog.update_status("Model download complete!")
            time.sleep(1)  # Give user a moment to see the success message
            dialog.close()
            Gtk.main_quit()
        except Exception as e:
            dialog.update_status(f"Error: {str(e)}")
            time.sleep(3)
            dialog.close()
            Gtk.main_quit()
    
    # Start download in a separate thread
    thread = threading.Thread(target=do_download)
    thread.daemon = True
    thread.start()
    
    # Start GTK main loop
    Gtk.main()

if __name__ == "__main__":
    download_model_with_progress()
EOF

# 4. Create model manager
echo "Creating model manager..."
cat > "$APPDIR/usr/bin/model_manager.py" << 'EOF'
import os
import sys
import subprocess
import threading

def ensure_model_available():
    """Check if the Whisper model is available, download if not."""
    import whisper
    
    # Path where whisper models are stored by default
    cache_dir = os.environ.get("WHISPER_CACHE_DIR", os.path.join(os.path.expanduser("~"), ".cache", "whisper"))
    model_path = os.path.join(cache_dir, "small.pt")
    
    # Check if model exists
    if not os.path.exists(model_path):
        # Model doesn't exist, show download dialog
        app_dir = os.path.dirname(os.path.abspath(__file__))
        subprocess.call([sys.executable, os.path.join(app_dir, "first_run_helper.py")])
        
        # Double-check model was downloaded
        if not os.path.exists(model_path):
            raise RuntimeError("Model download failed. Please check your internet connection and try again.")
    
    return "small"  # Return the model name for loading
EOF

# 5. Create desktop file and icon
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

# Create SVG icon
cat > "$APPDIR/usr/share/icons/hicolor/scalable/apps/whisper-transcriber.svg" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <circle cx="50" cy="50" r="45" fill="#3498db"/>
  <path d="M35,35 L35,65 M45,30 L45,70 M55,25 L55,75 M65,30 L65,70" stroke="white" stroke-width="5"/>
</svg>
EOF

# Create symlinks required by AppImage
ln -sf usr/share/applications/whisper-transcriber.desktop "$APPDIR/whisper-transcriber.desktop"
ln -sf usr/share/icons/hicolor/scalable/apps/whisper-transcriber.svg "$APPDIR/whisper-transcriber.svg"

# 6. Set up minimal Python environment
echo "Setting up Python environment..."
cd "$BUILD_DIR"
python3 -m venv venv
source venv/bin/activate

# Install only essential packages for smaller size
# Make sure to include numpy for audio level detection
pip install --no-cache-dir --upgrade pip wheel setuptools
pip install --no-cache-dir torch==2.6.0 --extra-index-url https://download.pytorch.org/whl/cpu # CPU-only torch for smaller size
pip install --no-cache-dir openai-whisper==20240930 # Specific commit version
pip install --no-cache-dir numpy==2.1.3  # Required for audio level detection
pip install --no-cache-dir PyAudio==0.2.14
pip install --no-cache-dir PyGObject==3.50.0

# 7. Patch the main application to use our model manager
echo "Patching main application..."
MAIN_SCRIPT="$APPDIR/usr/bin/whisper-transcriber"
sed -i '1i import model_manager' "$MAIN_SCRIPT"
sed -i 's/whisper.load_model("small")/whisper.load_model(model_manager.ensure_model_available())/' "$MAIN_SCRIPT"

# 8. Bundle Python interpreter and minimal libraries
echo "Bundling Python and essential libraries..."
cp $(which python3) "$APPDIR/usr/bin/"
mkdir -p "$APPDIR/usr/lib/python3.8/site-packages"

# Only copy essential packages
cp -r venv/lib/python3.8/site-packages/whisper "$APPDIR/usr/lib/python3.8/site-packages/"
cp -r venv/lib/python3.8/site-packages/torch "$APPDIR/usr/lib/python3.8/site-packages/"
cp -r venv/lib/python3.8/site-packages/gi "$APPDIR/usr/lib/python3.8/site-packages/"
cp -r venv/lib/python3.8/site-packages/pyaudio "$APPDIR/usr/lib/python3.8/site-packages/"
cp -r venv/lib/python3.8/site-packages/numpy "$APPDIR/usr/lib/python3.8/site-packages/"
# Copy other essential dependencies
cp -r venv/lib/python3.8/site-packages/regex "$APPDIR/usr/lib/python3.8/site-packages/"
cp -r venv/lib/python3.8/site-packages/tiktoken "$APPDIR/usr/lib/python3.8/site-packages/"
cp -r venv/lib/python3.8/site-packages/tqdm "$APPDIR/usr/lib/python3.8/site-packages/"
cp -r venv/lib/python3.8/site-packages/numba "$APPDIR/usr/lib/python3.8/site-packages/"
cp -r venv/lib/python3.8/site-packages/llvmlite "$APPDIR/usr/lib/python3.8/site-packages/"
# Copy all remaining .egg-info directories and .dist-info directories
mkdir -p "$APPDIR/usr/lib/python3.8/site-packages"
find venv/lib/python3.8/site-packages -maxdepth 1 -name "*.egg-info" -o -name "*.dist-info" | xargs -I{} cp -r {} "$APPDIR/usr/lib/python3.8/site-packages/"

# 9. Bundle only essential system libraries
echo "Bundling minimal system libraries..."
mkdir -p "$APPDIR/usr/lib/girepository-1.0"

# Only essential GTK typelibs
cp -L /usr/lib/*/girepository-1.0/Gtk-3.0.typelib "$APPDIR/usr/lib/girepository-1.0/" 2>/dev/null || true
cp -L /usr/lib/*/girepository-1.0/Gdk-3.0.typelib "$APPDIR/usr/lib/girepository-1.0/" 2>/dev/null || true
cp -L /usr/lib/*/girepository-1.0/GLib-2.0.typelib "$APPDIR/usr/lib/girepository-1.0/" 2>/dev/null || true
cp -L /usr/lib/*/girepository-1.0/GObject-2.0.typelib "$APPDIR/usr/lib/girepository-1.0/" 2>/dev/null || true

# Only copy essential libraries for PyGObject and PyAudio
mkdir -p "$APPDIR/usr/lib"
for module in "_gi" "_portaudio"; do
    lib_path=$(find venv -name "${module}*.so" | head -1)
    if [ -n "$lib_path" ]; then
        echo "Resolving dependencies for $lib_path"
        deps=$(ldd "$lib_path" | grep "=> /" | awk '{print $3}' | sort | uniq)
        for dep in $deps; do
            base_dep=$(basename "$dep")
            # Skip system libraries that should be present on all systems
            if [[ "$base_dep" != libc.so* ]] && [[ "$base_dep" != libpthread.so* ]] && 
               [[ "$base_dep" != libdl.so* ]] && [[ "$base_dep" != libm.so* ]]; then
                cp -L "$dep" "$APPDIR/usr/lib/" 2>/dev/null || true
            fi
        done
    fi
done

# 10. Build AppImage
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
mv Whisper*.AppImage WhisperTranscriber-$VERSION-lean-x86_64.AppImage
chmod +x WhisperTranscriber-$VERSION-lean-x86_64.AppImage

echo "=== Lean AppImage created successfully: $(pwd)/WhisperTranscriber-$VERSION-lean-x86_64.AppImage ==="
echo "This AppImage will download the Whisper 'small' model on first run."
echo "Estimated size reduction: 400-500MB compared to bundling the model."