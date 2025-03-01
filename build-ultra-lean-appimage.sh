#!/bin/bash
# Ultra-Lean Whisper Transcriber AppImage Builder (Updated for v0.8)
# Creates an extremely small AppImage with dynamic CUDA support

set -e  # Exit on any error

# Configuration
PROJECT_ROOT="$PWD"  # Assumes script is run from project root (WHISPER_LOCAL_DEPLOY)
SRC_DIR="$PROJECT_ROOT/src"
OUTPUT_DIR="$PROJECT_ROOT/dist"
BUILD_DIR="$OUTPUT_DIR/build"
APPDIR="$BUILD_DIR/WhisperTranscriber.AppDir"
VERSION="0.8.0"  # Updated version number

# Dynamically determine Python version
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "Detected Python version: $PYTHON_VERSION"

echo "=== Building Ultra-Lean Whisper Transcriber AppImage v$VERSION ==="
echo "Project root: $PROJECT_ROOT"

# Create necessary directories
mkdir -p "$OUTPUT_DIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib/python$PYTHON_VERSION/site-packages"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps"

# 1. Create AppRun script with dynamic environment setup
echo "Creating advanced AppRun entry point..."
cat > "$APPDIR/AppRun" << EOF
#!/bin/bash
# AppRun script for WhisperTranscriber with dynamic environment detection

# Find the directory where this AppRun script resides
HERE="\$(dirname "\$(readlink -f "\${0}")")"

# ------------------------
# Environment setup
# ------------------------
export PATH="\${HERE}/usr/bin:\${PATH}"
export LD_LIBRARY_PATH="\${HERE}/usr/lib:\${LD_LIBRARY_PATH}"
export PYTHONPATH="\${HERE}/usr/lib/python$PYTHON_VERSION/site-packages:\${PYTHONPATH}"
export XDG_DATA_DIRS="\${HERE}/usr/share:\${XDG_DATA_DIRS}"
export GI_TYPELIB_PATH="\${HERE}/usr/lib/girepository-1.0:\${GI_TYPELIB_PATH}"

# Set the Whisper model cache directory to a user-accessible location
MODEL_DIR="\$HOME/.cache/whisper-transcriber"
mkdir -p "\$MODEL_DIR"
export WHISPER_CACHE_DIR="\$MODEL_DIR"

# ------------------------
# GPU/CUDA detection
# ------------------------
# Check for system CUDA and PyTorch installations
SYSTEM_PYTHON=\$(which python3)
GPU_AVAILABLE=false

# Only check if system pytorch is available if we have system python
if [ -n "\$SYSTEM_PYTHON" ]; then
    if \$SYSTEM_PYTHON -c "import torch; exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
        GPU_AVAILABLE=true
        echo "System PyTorch with CUDA detected! Using system installation for GPU acceleration."
        export WHISPER_USE_SYSTEM_PYTORCH=1
    fi
fi

# Create a log file for debugging
LOG_FILE="\$HOME/.cache/whisper-transcriber/appimage.log"
echo "Starting WhisperTranscriber AppImage \$(date)" > "\$LOG_FILE"
echo "GPU Available: \$GPU_AVAILABLE" >> "\$LOG_FILE"
echo "System Python: \$SYSTEM_PYTHON" >> "\$LOG_FILE"
echo "Current Python: \$(which python3)" >> "\$LOG_FILE"

# ------------------------
# Launch the application
# ------------------------
"\${HERE}/usr/bin/python3" "\${HERE}/usr/bin/whisper-transcriber" "\$@"
exit \$?
EOF
chmod +x "$APPDIR/AppRun"

# 2. Copy application scripts - Updated to use v0.8 and v12
echo "Copying application files..."
cp "$SRC_DIR/gui-v0.8.py" "$APPDIR/usr/bin/whisper-transcriber"
cp "$SRC_DIR/transcriber_v12.py" "$APPDIR/usr/bin/transcriber_v12.py"
chmod +x "$APPDIR/usr/bin/whisper-transcriber"

# 3. Create dynamic PyTorch/CUDA loader
echo "Creating dynamic PyTorch loader..."
cat > "$APPDIR/usr/bin/pytorch_loader.py" << 'EOF'
"""
Dynamic PyTorch loader that checks for system installations before using bundled version.
This allows the AppImage to use the system's CUDA-enabled PyTorch when available.
"""
import os
import sys
import importlib.util
import logging

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    filename=os.path.expanduser('~/.cache/whisper-transcriber/pytorch_loader.log'),
    filemode='a'
)

def get_system_torch():
    """Try to import system torch with CUDA support."""
    try:
        # Remove our path from sys.path temporarily
        original_path = sys.path.copy()
        appdir_paths = [p for p in sys.path if '/tmp/.mount_' in p or '.AppDir' in p]
        for p in appdir_paths:
            if p in sys.path:
                sys.path.remove(p)
        
        # Try importing system torch
        spec = importlib.util.find_spec('torch')
        if spec is not None:
            torch = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(torch)
            
            # Check if CUDA is available
            if hasattr(torch, 'cuda') and torch.cuda.is_available():
                device_name = torch.cuda.get_device_name(0)
                device_count = torch.cuda.device_count()
                logging.info(f"Using system PyTorch with CUDA. Devices: {device_count}, Name: {device_name}")
                return torch
            else:
                logging.info("System PyTorch found but CUDA not available")
        else:
            logging.info("No system PyTorch found")
    except Exception as e:
        logging.error(f"Error trying to import system torch: {e}")
    finally:
        # Restore original path
        sys.path = original_path
    
    return None

def get_bundled_torch():
    """Fall back to bundled torch."""
    try:
        import torch
        logging.info(f"Using bundled PyTorch (CPU-only)")
        return torch
    except ImportError as e:
        logging.error(f"Failed to import bundled torch: {e}")
        raise

# Try to get system torch with CUDA first
if os.environ.get('WHISPER_USE_SYSTEM_PYTORCH') == '1':
    system_torch = get_system_torch()
    if system_torch is not None:
        sys.modules['torch'] = system_torch
        logging.info("Successfully loaded system PyTorch with CUDA support")
    else:
        logging.info("Falling back to bundled PyTorch")
        torch = get_bundled_torch()
else:
    logging.info("Using bundled PyTorch as specified by environment")
    torch = get_bundled_torch()

# Create a global flag that other modules can check
torch.is_using_system_cuda = getattr(torch, 'cuda', None) is not None and torch.cuda.is_available()
EOF

# 4. Create download helper for model
echo "Creating model downloader..."
cat > "$APPDIR/usr/bin/model_downloader.py" << 'EOF'
import os
import sys
import time
import threading
import logging
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib

# Setup logging
logging.basicConfig(
    level=logging.INFO, 
    format='%(asctime)s [%(levelname)s] %(message)s',
    filename=os.path.expanduser('~/.cache/whisper-transcriber/model_downloader.log'),
    filemode='a'
)

class ModelDownloadDialog:
    def __init__(self):
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
        
        self.label = Gtk.Label()
        self.label.set_markup("<b>Downloading Whisper Model</b>\n\nThis will only happen once. Please wait...")
        self.label.set_justify(Gtk.Justification.CENTER)
        content_area.add(self.label)
        
        self.progress = Gtk.ProgressBar()
        self.progress.set_pulse_step(0.1)
        content_area.add(self.progress)
        
        self.status_label = Gtk.Label()
        self.status_label.set_text("Preparing download...")
        content_area.add(self.status_label)
        
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

def download_model():
    logging.info("Starting model download dialog")
    
    try:
        # Ensure pytorch_loader is imported first
        import pytorch_loader
        
        dialog = ModelDownloadDialog()
        dialog.start_progress_pulse()
        
        def do_download():
            try:
                dialog.update_status("Importing Whisper...")
                logging.info("Importing whisper")
                import whisper
                
                dialog.update_status("Downloading small model (this may take a few minutes)...")
                logging.info("Downloading whisper model")
                model = whisper.load_model("small")
                
                dialog.update_status("Model download complete!")
                logging.info("Model download complete")
                time.sleep(1)
                dialog.close()
                Gtk.main_quit()
            except Exception as e:
                error_msg = f"Error: {str(e)}"
                logging.error(error_msg)
                dialog.update_status(error_msg)
                time.sleep(3)
                dialog.close()
                Gtk.main_quit()
        
        thread = threading.Thread(target=do_download)
        thread.daemon = True
        thread.start()
        
        Gtk.main()
        return True
    except Exception as e:
        logging.error(f"Error in download_model: {e}")
        return False

def check_and_download_model():
    """Check if model exists, download if not."""
    cache_dir = os.environ.get("WHISPER_CACHE_DIR", os.path.join(os.path.expanduser("~"), ".cache", "whisper"))
    model_path = os.path.join(cache_dir, "small.pt")
    
    if not os.path.exists(model_path):
        logging.info(f"Model not found at {model_path}, starting download")
        return download_model()
    else:
        logging.info(f"Model already exists at {model_path}")
        return True

if __name__ == "__main__":
    check_and_download_model()
EOF

# 5. Create minimal wrapper script - updated for audio visualization support
echo "Creating application wrapper..."
cat > "$APPDIR/usr/bin/app_wrapper.py" << 'EOF'
"""
Application wrapper that handles initialization and dynamic loading.
"""
import os
import sys
import logging

# Setup logging
log_dir = os.path.expanduser("~/.cache/whisper-transcriber")
os.makedirs(log_dir, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    filename=os.path.join(log_dir, 'app_wrapper.log'),
    filemode='a'
)

def initialize_app():
    # Import dynamic pytorch loader first (it will handle CUDA detection)
    try:
        logging.info("Importing PyTorch loader")
        import pytorch_loader
    except Exception as e:
        logging.error(f"Failed to import PyTorch loader: {e}")
        print(f"Error: Could not initialize PyTorch: {e}", file=sys.stderr)
        return False
    
    # Check for model and download if needed
    try:
        logging.info("Checking for Whisper model")
        import model_downloader
        if not model_downloader.check_and_download_model():
            logging.error("Model download failed")
            print("Error: Could not download Whisper model", file=sys.stderr)
            return False
    except Exception as e:
        logging.error(f"Error checking/downloading model: {e}")
        print(f"Error: Model initialization failed: {e}", file=sys.stderr)
        return False
    
    return True

def run_application():
    # Patch whisper's model loading to use our cache directory
    import whisper
    original_load_model = whisper.load_model
    
    def patched_load_model(name, *args, **kwargs):
        logging.info(f"Loading whisper model: {name}")
        # If using CUDA, explicitly use device='cuda'
        import torch
        if torch.is_using_system_cuda:
            logging.info("Using system CUDA")
            kwargs['device'] = 'cuda'
        return original_load_model(name, *args, **kwargs)
    
    whisper.load_model = patched_load_model
    
    # Now run the actual application
    logging.info("Starting main application")
    import gui-v0.8 as gui_app
    gui_app.main()

if __name__ == "__main__":
    logging.info("Application wrapper starting")
    if initialize_app():
        run_application()
    else:
        sys.exit(1)
EOF

# 6. Patch main application to use our wrapper
echo "Patching main application..."
MAIN_SCRIPT="$APPDIR/usr/bin/whisper-transcriber"
mv "$MAIN_SCRIPT" "$APPDIR/usr/bin/gui-v0.8.py"
cat > "$MAIN_SCRIPT" << 'EOF'
#!/usr/bin/env python3
# Main entry point for Whisper Transcriber AppImage
import app_wrapper
app_wrapper.run_application()
EOF
chmod +x "$MAIN_SCRIPT"

# 7. Create desktop file and icon
echo "Creating desktop entry and icon..."
cat > "$APPDIR/usr/share/applications/whisper-transcriber.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Whisper Transcriber
Comment=Real-time speech transcription with OpenAI Whisper
Exec=whisper-transcriber
Icon=whisper-transcriber
Categories=AudioVideo;Audio;Utility;
Terminal=false
EOF

# Create a simple SVG icon
cat > "$APPDIR/usr/share/icons/hicolor/scalable/apps/whisper-transcriber.svg" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <circle cx="50" cy="50" r="45" fill="#3498db"/>
  <path d="M35,35 L35,65 M45,30 L45,70 M55,25 L55,75 M65,30 L65,70" stroke="white" stroke-width="5"/>
</svg>
EOF

# Create symlinks required by AppImage
ln -sf usr/share/applications/whisper-transcriber.desktop "$APPDIR/whisper-transcriber.desktop"
ln -sf usr/share/icons/hicolor/scalable/apps/whisper-transcriber.svg "$APPDIR/whisper-transcriber.svg"

# 8. Set up minimal Python environment with CPU-only torch
# Ensure numpy is included for audio visualization
echo "Setting up ultra-minimal Python environment..."
cd "$BUILD_DIR"
python3 -m venv venv
source venv/bin/activate

# Install only the absolute minimum requirements
pip install --no-cache-dir --upgrade pip wheel setuptools
# Install minimal CPU-only PyTorch (as fallback only)
pip install --no-cache-dir torch==2.6.0 --extra-index-url https://download.pytorch.org/whl/cpu --no-deps
# Install minimal Whisper without extra dependencies
pip install --no-cache-dir openai-whisper==20240930 --no-deps
# Install strictly required dependencies
pip install --no-cache-dir PyAudio==0.2.14 --no-deps
pip install --no-cache-dir PyGObject==3.50.0 --no-deps
pip install --no-cache-dir numpy==2.1.3 --no-deps  # Required for audio visualization
pip install --no-cache-dir regex==2024.11.6 --no-deps
pip install --no-cache-dir tiktoken==0.9.0 --no-deps

# 9. Bundle only essential Python packages (minimal approach)
echo "Bundling minimal Python packages..."
cp $(which python3) "$APPDIR/usr/bin/"
mkdir -p "$APPDIR/usr/lib/python$PYTHON_VERSION/site-packages"

# Manually copy only essential modules - extremely selective approach
SITE_PACKAGES_PATH="venv/lib/python$PYTHON_VERSION/site-packages"
modules_to_copy=(
    "whisper"
    "torch"
    "numpy"
    "gi"
    "pyaudio"
    "regex"
    "tiktoken"
    "numba"
    "llvmlite"
)

for module in "${modules_to_copy[@]}"; do
    if [ -d "$SITE_PACKAGES_PATH/$module" ]; then
        echo "Copying module: $module"
        cp -r "$SITE_PACKAGES_PATH/$module" "$APPDIR/usr/lib/python$PYTHON_VERSION/site-packages/"
    else
        echo "Warning: Module $module not found in $SITE_PACKAGES_PATH"
    fi
done

# Copy minimal dependencies for imports to work
find "$SITE_PACKAGES_PATH" -maxdepth 1 -name "__pycache__" -prune -o -name "*.py" -print | xargs -I{} cp {} "$APPDIR/usr/lib/python$PYTHON_VERSION/site-packages/" 2>/dev/null || true
find "$SITE_PACKAGES_PATH" -maxdepth 1 -name "*.dist-info" | xargs -I{} cp -r {} "$APPDIR/usr/lib/python$PYTHON_VERSION/site-packages/" 2>/dev/null || true

# 10. Bundle only absolutely essential system libraries 
echo "Bundling minimal system libraries..."
mkdir -p "$APPDIR/usr/lib/girepository-1.0"

# Copy only the exact GTK typelibs needed
cp -L /usr/lib/*/girepository-1.0/Gtk-3.0.typelib "$APPDIR/usr/lib/girepository-1.0/" 2>/dev/null || true
cp -L /usr/lib/*/girepository-1.0/Gdk-3.0.typelib "$APPDIR/usr/lib/girepository-1.0/" 2>/dev/null || true

# Use ldd to find exact dependencies of PyAudio
audio_lib=$(find venv -name "_portaudio.*.so" | head -1)
if [ -n "$audio_lib" ]; then
    audio_deps=$(ldd "$audio_lib" | grep "=> /" | awk '{print $3}' | sort | uniq)
    for dep in $audio_deps; do
        # Skip very common system libraries
        lib_name=$(basename "$dep")
        if [[ "$lib_name" != libc.so* ]] && 
           [[ "$lib_name" != libpthread.so* ]] && 
           [[ "$lib_name" != libdl.so* ]] && 
           [[ "$lib_name" != libm.so* ]]; then
            cp -L "$dep" "$APPDIR/usr/lib/" 2>/dev/null || true
        fi
    done
fi

# Only add essential GTK libraries
gi_lib=$(find venv -name "_gi.*.so" | head -1)
if [ -n "$gi_lib" ]; then
    gi_deps=$(ldd "$gi_lib" | grep "=> /" | awk '{print $3}' | sort | uniq)
    for dep in $gi_deps; do
        # Only copy GTK and GI related libraries
        lib_name=$(basename "$dep")
        if [[ "$lib_name" == libgtk* ]] || 
           [[ "$lib_name" == libg* ]] || 
           [[ "$lib_name" == libpango* ]] || 
           [[ "$lib_name" == libcairo* ]]; then
            cp -L "$dep" "$APPDIR/usr/lib/" 2>/dev/null || true
        fi
    done
fi

# 11. Use UPX to compress binaries if available
if command -v upx &> /dev/null; then
    echo "Compressing binaries with UPX..."
    find "$APPDIR" -type f -executable -size +100k | xargs upx -9 2>/dev/null || true
    find "$APPDIR/usr/lib" -name "*.so" -size +100k | xargs upx -9 2>/dev/null || true
else
    echo "UPX not found, skipping binary compression"
    echo "Install UPX for further size reduction: sudo apt install upx"
fi

# 12. Strip debug symbols
echo "Stripping debug symbols..."
find "$APPDIR" -type f -executable | xargs strip --strip-all 2>/dev/null || true
find "$APPDIR/usr/lib" -name "*.so*" | xargs strip --strip-unneeded 2>/dev/null || true

# 13. Build AppImage
echo "Building AppImage..."
cd "$OUTPUT_DIR"

# Download appimagetool if not available
if [ ! -f "./appimagetool" ]; then
    echo "Downloading appimagetool..."
    wget -q -O appimagetool "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x appimagetool
fi

# Build the AppImage with maximum compression
./appimagetool -n --comp xz "$APPDIR"

# Rename to final version - Fixed to match correct source filename
mv Whisper_Transcriber-x86_64.AppImage WhisperTranscriber-$VERSION-ultra-lean-x86_64.AppImage 2>/dev/null || true

# Get final size
if [ -f "WhisperTranscriber-$VERSION-ultra-lean-x86_64.AppImage" ]; then
    FINAL_SIZE=$(du -h WhisperTranscriber-$VERSION-ultra-lean-x86_64.AppImage | cut -f1)
    echo "=== Ultra-Lean AppImage created successfully! ==="
    echo "Location: $(pwd)/WhisperTranscriber-$VERSION-ultra-lean-x86_64.AppImage"
    echo "Size: $FINAL_SIZE"
else
    echo "=== AppImage created as Whisper_Transcriber-x86_64.AppImage ==="
    echo "Location: $(pwd)/Whisper_Transcriber-x86_64.AppImage"
    echo "Size: $(du -h Whisper_Transcriber-x86_64.AppImage | cut -f1)"
fi

echo "This AppImage will download the Whisper model on first run and"
echo "will use system CUDA when available."
echo ""
echo "New in v0.8: Audio level visualization and improved transcription quality"