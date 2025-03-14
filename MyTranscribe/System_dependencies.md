# System Dependencies

> **Note:** The following dependencies must be installed system-wide (using your package manager, e.g., apt-get on Ubuntu) because they provide the libraries and header files required to compile native Python extensions. These are not installed in your Python virtual environment.

- **libcairo2-dev**: Development files for the Cairo graphics library, required by the `pycairo` package.
- **pkg-config**: A helper tool used to retrieve information about installed libraries, ensuring the correct compile and link flags are used.
- **python3-dev**: Contains Python header files and a static library necessary for compiling Python C extensions.
- **libgirepository1.0-dev**: Provides the development files for GObject Introspection, which is required by the `pygobject` package.
- **portaudio19-dev**: Supplies the development files for PortAudio, necessary for building the `PyAudio` package.

