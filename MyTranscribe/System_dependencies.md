# System Dependencies

> **Note:** The following dependencies must be installed system-wide (using your package manager, e.g., apt-get on Ubuntu) because they provide the libraries and header files required to compile native Python extensions. These are not installed in your Python virtual environment.

- **libcairo2-dev**: Development files for the Cairo graphics library, required by the `pycairo` package.
- **pkg-config**: A helper tool used to retrieve information about installed libraries, ensuring the correct compile and link flags are used.
- **python3-dev**: Contains Python header files and a static library necessary for compiling Python C extensions.
- **libgirepository1.0-dev**: Provides the development files for GObject Introspection, which is required by the `pygobject` package.
- **portaudio19-dev**: Supplies the development files for PortAudio, necessary for building the `PyAudio` package.

## ffmpeg Installation Requirement

This project requires **ffmpeg** to be installed and available in your system's PATH. If you encounter the error:

    FileNotFoundError: [Errno 2] No such file or directory: 'ffmpeg'

it means that **ffmpeg** is missing. To resolve this, please install **ffmpeg**.

For Debian/Ubuntu systems, you can install it using:
    
    sudo apt-get update
    sudo apt-get install ffmpeg

For other platforms, refer to your distribution's installation guidelines for **ffmpeg**.
