#!/bin/bash
# Lean Whisper Transcriber AppImage Builder (Updated for v0.9.1)
# This script creates a minimal AppImage that downloads the model on first run
# and uses system CUDA when available

set -e  # Exit on any error

# Configuration - CHANGE THESE PATHS TO MATCH YOUR ENVIRONMENT
PROJECT_ROOT="$PWD"  # Assumes script is run from project root (WHISPER_LOCAL_DEPLOY)
SRC_DIR="$PROJECT_ROOT/src"
OUTPUT_DIR="$PROJECT_ROOT/dist"
BUILD_DIR="$OUTPUT_DIR/build"
APPDIR="$BUILD_DIR/WhisperTranscriber.AppDir"
VERSION="0.9.1"  # Updated version number

# Dynamically determine Python version
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "Detected Python version: $PYTHON_VERSION"

echo "=== Building Whisper Transcriber AppImage v$VERSION (with CUDA support) ==="
echo "Project root: $PROJECT_ROOT"
echo "Source directory: $SRC_DIR"

# Create necessary directories
mkdir -p "$OUTPUT_DIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib/python$PYTHON_VERSION/site-packages"
mkdir -p "$APPDIR/usr/lib/cuda"  # Special directory for CUDA libraries
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps"
mkdir -p "$APPDIR/usr/share/whisper-models"

# 1. Create AppRun script with CUDA detection
echo "Creating AppRun entry point with enhanced CUDA detection..."
cat > "$APPDIR/AppRun" << EOF
#!/bin/bash
# AppRun script for WhisperTranscriber with CUDA detection

# Find the directory where this AppRun script resides
HERE="\$(dirname "\$(readlink -f "\${0}")")"

# Set up environment variables
export PATH="\${HERE}/usr/bin:\${PATH}"
# Include the CUDA libraries path explicitly
export LD_LIBRARY_PATH="\${HERE}/usr/lib:\${HERE}/usr/lib/cuda:\${LD_LIBRARY_PATH}"
export PYTHONPATH="\${HERE}/usr/lib/python$PYTHON_VERSION/site-packages:\${PYTHONPATH}"
export XDG_DATA_DIRS="\${HERE}/usr/share:\${XDG_DATA_DIRS}"
export GI_TYPELIB_PATH="\${HERE}/usr/lib/girepository-1.0:\${GI_TYPELIB_PATH}"

# Check for NVIDIA drivers and CUDA support
if command -v nvidia-smi &> /dev/null; then
    echo "NVIDIA drivers detected. Using GPU if available."
    # These environment variables help PyTorch find system CUDA libraries
    export CUDA_HOME=\$(dirname \$(dirname \$(which nvidia-smi)))
    export USE_SYSTEM_CUDA=1
    
    # Add standard CUDA library paths to help find system CUDA libraries
    if [ -d "/usr/local/cuda/lib64" ]; then
        export LD_LIBRARY_PATH="/usr/local/cuda/lib64:\${LD_LIBRARY_PATH}"
    elif [ -d "/usr/lib/cuda" ]; then
        export LD_LIBRARY_PATH="/usr/lib/cuda:\${LD_LIBRARY_PATH}"
    elif [ -d "\${CUDA_HOME}/lib64" ]; then
        export LD_LIBRARY_PATH="\${CUDA_HOME}/lib64:\${LD_LIBRARY_PATH}"
    fi
else
    echo "NVIDIA drivers not detected. Falling back to CPU mode."
    export CUDA_VISIBLE_DEVICES=""
fi

# Debug: Print library paths to help troubleshoot
echo "LD_LIBRARY_PATH: \${LD_LIBRARY_PATH}"

# Set the Whisper model cache directory
MODEL_DIR="\$HOME/.cache/whisper-transcriber"
mkdir -p "\$MODEL_DIR"
export WHISPER_CACHE_DIR="\$MODEL_DIR"

# Launch the application
exec "\${HERE}/usr/bin/python3" "\${HERE}/usr/bin/whisper-transcriber" "\$@"
EOF
chmod +x "$APPDIR/AppRun"

# 2. Copy application scripts
echo "Copying application files..."
cp "$SRC_DIR/gui-v0.8.py" "$APPDIR/usr/bin/whisper-transcriber"
cp "$SRC_DIR/transcriber_v12.py" "$APPDIR/usr/bin/transcriber_v12.py"
chmod +x "$APPDIR/usr/bin/whisper-transcriber"

# 3. Create CUDA helper module
echo "Creating enhanced CUDA helper module..."
cat > "$APPDIR/usr/bin/cuda_helper.py" << 'EOF'
"""
Helper module for CUDA detection and configuration.
"""
import os
import sys
import subprocess
import logging

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    filename=os.path.expanduser('~/.cache/whisper-transcriber/cuda_helper.log'),
    filemode='a'
)

def check_cuda_available():
    """Check if CUDA is available on the system."""
    try:
        # Try to run nvidia-smi
        subprocess.run(["nvidia-smi"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        logging.info("NVIDIA drivers detected via nvidia-smi")
        return True
    except (subprocess.SubprocessError, FileNotFoundError):
        logging.info("NVIDIA drivers not detected")
        return False

def configure_torch_for_cuda():
    """Configure PyTorch to use system CUDA."""
    if not check_cuda_available():
        logging.info("No CUDA available, configuring for CPU-only mode")
        os.environ["CUDA_VISIBLE_DEVICES"] = ""
        return False

    try:
        # Log LD_LIBRARY_PATH to help debug
        logging.info(f"LD_LIBRARY_PATH: {os.environ.get('LD_LIBRARY_PATH', 'Not set')}")
        
        import torch
        logging.info(f"PyTorch version: {torch.__version__}")
        logging.info(f"CUDA available: {torch.cuda.is_available()}")
        
        if torch.cuda.is_available():
            device_count = torch.cuda.device_count()
            device_names = [torch.cuda.get_device_name(i) for i in range(device_count)]
            logging.info(f"CUDA is available with {device_count} device(s): {device_names}")
            
            # Print CUDA capabilities
            for i in range(device_count):
                cap = torch.cuda.get_device_capability(i)
                logging.info(f"Device {i} ({device_names[i]}) capability: {cap[0]}.{cap[1]}")
            
            return True
        else:
            logging.error("PyTorch reports CUDA is not available despite NVIDIA drivers")
            
            # Try to get more information about why CUDA is not available
            try:
                import ctypes
                cuda_path = os.environ.get("CUDA_HOME", "/usr/local/cuda")
                for lib_name in ["libcudart.so", "libcusparse.so", "libcusparseLt.so.0"]:
                    try:
                        lib_path = os.path.join(cuda_path, "lib64", lib_name)
                        if os.path.exists(lib_path):
                            logging.info(f"CUDA library {lib_name} found at {lib_path}")
                            try:
                                ctypes.CDLL(lib_path)
                                logging.info(f"Successfully loaded {lib_name}")
                            except Exception as e:
                                logging.error(f"Failed to load {lib_name}: {e}")
                        else:
                            logging.error(f"CUDA library {lib_name} not found at {lib_path}")
                    except Exception as e:
                        logging.error(f"Error checking {lib_name}: {e}")
            except Exception as e:
                logging.error(f"Error checking CUDA libraries: {e}")
            
            return False
    except Exception as e:
        logging.error(f"Error checking CUDA with PyTorch: {e}")
        import traceback
        logging.error(traceback.format_exc())
        return False

if __name__ == "__main__":
    result = configure_torch_for_cuda()
    print(f"CUDA Available: {result}")
    sys.exit(0 if result else 1)
EOF

# 4. Create first-run helper for model download
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

# 5. Create model manager with CUDA support
echo "Creating model manager..."
cat > "$APPDIR/usr/bin/model_manager.py" << 'EOF'
import os
import sys
import subprocess
import threading
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    filename=os.path.expanduser('~/.cache/whisper-transcriber/model_manager.log'),
    filemode='a'
)

def ensure_model_available():
    """Check if the Whisper model is available, download if not."""
    import whisper
    
    # Check CUDA first to ensure it's properly configured before model loading
    import cuda_helper
    cuda_helper.configure_torch_for_cuda()
    
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

# 6. Patch the main application for CUDA support
echo "Patching main application..."
MAIN_SCRIPT="$APPDIR/usr/bin/whisper-transcriber"
# Add imports at the top
sed -i '1i import cuda_helper' "$MAIN_SCRIPT"
sed -i '2i import model_manager' "$MAIN_SCRIPT"
# Replace the model loading line
sed -i 's/whisper.load_model("small")/whisper.load_model(model_manager.ensure_model_available())/' "$MAIN_SCRIPT"

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

# 8. Set up Python environment with PyTorch that can use system CUDA
echo "Setting up Python environment..."
cd "$BUILD_DIR"
python3 -m venv venv
source venv/bin/activate

# Install packages with CUDA-enabled PyTorch
pip install --no-cache-dir --upgrade pip wheel setuptools

# Install PyTorch with CUDA support - IMPORTANT CHANGE!
echo "Installing PyTorch with CUDA support..."
if [ -f "$PROJECT_ROOT/requirements.txt" ]; then
    echo "Using requirements.txt for installation..."
    # Use the provided requirements.txt which should include CUDA-enabled torch
    pip install --no-cache-dir -r "$PROJECT_ROOT/requirements.txt"
else
    echo "Installing packages manually with CUDA support..."
    # Install PyTorch with CUDA support
    pip install --no-cache-dir torch==2.6.0+cu122 --extra-index-url https://download.pytorch.org/whl/cu122
    pip install --no-cache-dir openai-whisper==20240930
    pip install --no-cache-dir numpy==2.1.3
    pip install --no-cache-dir PyAudio==0.2.14
    pip install --no-cache-dir PyGObject==3.50.0
fi

# 9. Bundle Python interpreter and minimal libraries
echo "Bundling Python and essential libraries..."
cp $(which python3) "$APPDIR/usr/bin/"
mkdir -p "$APPDIR/usr/lib/python$PYTHON_VERSION/site-packages"

# Get the actual site-packages path from the virtual environment
SITE_PACKAGES_PATH="venv/lib/python$PYTHON_VERSION/site-packages"
echo "Using site-packages from: $SITE_PACKAGES_PATH"

# Copy essential packages using the correct Python version path
for pkg in whisper torch gi pyaudio numpy regex tiktoken tqdm numba llvmlite; do
  if [ -d "$SITE_PACKAGES_PATH/$pkg" ]; then
    echo "Copying $pkg"
    cp -r "$SITE_PACKAGES_PATH/$pkg" "$APPDIR/usr/lib/python$PYTHON_VERSION/site-packages/"
  else
    echo "Warning: Package directory $pkg not found, skipping"
  fi
done

# Copy all .egg-info and .dist-info directories
echo "Copying package metadata..."
find "$SITE_PACKAGES_PATH" -maxdepth 1 -name "*.egg-info" -o -name "*.dist-info" | xargs -I{} cp -r {} "$APPDIR/usr/lib/python$PYTHON_VERSION/site-packages/" 2>/dev/null || true

# 10. Bundle PyTorch CUDA libraries - IMPORTANT ADDITION!
echo "Bundling PyTorch CUDA libraries..."
# Find torch lib directory
TORCH_PATH=$(python -c "import torch; print(torch.__path__[0])")
echo "PyTorch path: $TORCH_PATH"

# Copy CUDA libraries from PyTorch
if [ -d "$TORCH_PATH/lib" ]; then
    echo "Copying PyTorch CUDA libraries..."
    # Copy all CUDA-related libraries from torch
    cp -L "$TORCH_PATH/lib/"*.so* "$APPDIR/usr/lib/cuda/" 2>/dev/null || true
    
    # Also look for CUDA-specific libraries
    for cuda_lib in libcudart libcusparse libcusparseLt libcublas libcudnn; do
        find "$TORCH_PATH" -name "${cuda_lib}*.so*" | xargs -I{} cp -L {} "$APPDIR/usr/lib/cuda/" 2>/dev/null || true
    done
else
    echo "Warning: PyTorch lib directory not found at $TORCH_PATH/lib"
fi

# Also copy NVIDIA libraries from site-packages
echo "Searching for NVIDIA libraries in site-packages..."
for nvidia_pkg in nvidia-*; do
    if [ -d "$SITE_PACKAGES_PATH/$nvidia_pkg" ]; then
        echo "Processing package $nvidia_pkg..."
        find "$SITE_PACKAGES_PATH/$nvidia_pkg" -name "*.so*" | xargs -I{} cp -L {} "$APPDIR/usr/lib/cuda/" 2>/dev/null || true
    fi
done

# 11. Bundle only essential system libraries
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

# 12. Check for CUDA libraries and copy if possible
echo "Checking for system CUDA libraries to include..."
CUDA_LIB_PATHS=(
    "/usr/local/cuda/lib64"
    "/usr/lib/cuda"
    "/usr/lib/x86_64-linux-gnu"
)

for cuda_path in "${CUDA_LIB_PATHS[@]}"; do
    if [ -d "$cuda_path" ]; then
        echo "Found CUDA library path: $cuda_path"
        # Copy critical CUDA libraries
        for cuda_lib in libcudart libcusparse libcusparseLt libcublas libcudnn; do
            find "$cuda_path" -name "${cuda_lib}*.so*" | xargs -I{} cp -L {} "$APPDIR/usr/lib/cuda/" 2>/dev/null || true
        done
    fi
done

# List the included CUDA libraries
echo "CUDA libraries included in AppImage:"
ls -la "$APPDIR/usr/lib/cuda/"

# 13. Build AppImage
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

# Rename to final version with fallback handling
mv Whisper_Transcriber-x86_64.AppImage WhisperTranscriber-$VERSION-x86_64.AppImage 2>/dev/null || true

# Get final size and display success message
if [ -f "WhisperTranscriber-$VERSION-x86_64.AppImage" ]; then
    FINAL_SIZE=$(du -h WhisperTranscriber-$VERSION-x86_64.AppImage | cut -f1)
    echo "=== AppImage created successfully! ==="
    echo "Location: $(pwd)/WhisperTranscriber-$VERSION-x86_64.AppImage"
    echo "Size: $FINAL_SIZE"
else
    echo "=== AppImage created as Whisper_Transcriber-x86_64.AppImage ==="
    echo "Location: $(pwd)/Whisper_Transcriber-x86_64.AppImage"
    echo "Size: $(du -h Whisper_Transcriber-x86_64.AppImage | cut -f1)"
fi

echo "This AppImage now includes PyTorch CUDA libraries."
echo "It will also try to use the system's CUDA libraries if available."
echo "New in v0.9.1: Fixed CUDA library dependency issue"
echo "To run the AppImage, make it executable and double-click or run from terminal."