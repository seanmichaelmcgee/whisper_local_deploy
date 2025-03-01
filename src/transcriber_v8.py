import threading
import pyaudio
import wave
import time
import tempfile
import os
import logging
import whisper
import torch

# Audio configuration
CHUNK = 1024
FORMAT = pyaudio.paInt16
CHANNELS = 1
DEFAULT_CHUNK_DURATION = 30  # seconds for normal mode processing
OVERLAP_DURATION = 1  # 1 second overlap

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

# A prompt to prime the transcription for technical terminology
TECHNICAL_PROMPT = (
    "This transcription involves technical content related to Python programming, "
    "machine learning, neural networks, and artificial intelligence. Please ensure that "
    "technical terms (e.g., neural network, backpropagation, gradient descent, overfitting, "
    "Python, list, dict, lambda) are transcribed accurately."
)

class RealTimeTranscriber:
    def __init__(self, model):
        self.model = model
        # Move model to GPU if available
        if torch.cuda.is_available():
            self.model.to("cuda")
        if next(self.model.parameters()).is_cuda:
            logging.info("GPU acceleration is enabled.")
        else:
            logging.info("GPU acceleration is NOT enabled.")
        
        self.transcriptions = []
        self.running = False
        self.partial_frames = []
        self.overlap_frames = []
        self.audio_interface = pyaudio.PyAudio()
        self.num_overlap_buffers = int((OVERLAP_DURATION * 16000) / CHUNK)
        self.chunk_duration = DEFAULT_CHUNK_DURATION  # for normal mode

        # For long record mode
        self.long_mode = False
        self.long_frames = []

    def start_recording(self, mode="normal"):
        """
        mode: "normal" for normal incremental transcription,
              "long" for accumulating audio until session end (max 180 seconds auto-stop)
        """
        self.long_mode = (mode == "long")
        self.chunk_duration = DEFAULT_CHUNK_DURATION  # used in normal mode
        self.running = True
        self.overlap_frames = []
        self.partial_frames = []
        
        if self.long_mode:
            self.long_frames = []
            self.long_start_time = time.time()
        # Open audio stream
        self.stream = self.audio_interface.open(
            format=FORMAT,
            channels=CHANNELS,
            rate=16000,
            input=True,
            frames_per_buffer=CHUNK
        )
        self.record_thread = threading.Thread(target=self.record_loop, daemon=True)
        self.record_thread.start()

    def stop_recording(self):
        self.running = False
        if self.record_thread.is_alive():
            self.record_thread.join()
        self.stream.stop_stream()
        self.stream.close()

    def record_loop(self):
        if self.long_mode:
            # In long mode, simply accumulate all audio frames.
            while self.running:
                try:
                    data = self.stream.read(CHUNK, exception_on_overflow=False)
                except Exception as e:
                    logging.error("Error reading audio stream", exc_info=True)
                    continue
                self.long_frames.append(data)
                # Auto-stop after 180 seconds if not interrupted
                if time.time() - self.long_start_time >= 180:
                    self.running = False
            # Once stopped, process the entire accumulated audio as one chunk.
            if self.long_frames:
                self.process_audio_chunk(self.long_frames)
        else:
            # Normal mode: process audio in DEFAULT_CHUNK_DURATION-second chunks.
            while self.running:
                frames = []
                chunk_start = time.time()
                while time.time() - chunk_start < self.chunk_duration:
                    if not self.running:
                        break
                    try:
                        data = self.stream.read(CHUNK, exception_on_overflow=False)
                    except Exception as e:
                        logging.error("Error reading audio stream", exc_info=True)
                        continue
                    frames.append(data)
                if not frames:
                    continue
                all_frames = self.overlap_frames + frames
                if all_frames:
                    self.process_audio_chunk(all_frames)
                if len(all_frames) >= self.num_overlap_buffers:
                    self.overlap_frames = all_frames[-self.num_overlap_buffers:]
                else:
                    self.overlap_frames = all_frames

    def process_audio_chunk(self, frames):
        if not frames:
            return
        wav_filename = None
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_wav:
                wav_filename = temp_wav.name
            with wave.open(wav_filename, 'wb') as wf:
                wf.setnchannels(CHANNELS)
                wf.setsampwidth(self.audio_interface.get_sample_size(FORMAT))
                wf.setframerate(16000)
                wf.writeframes(b''.join(frames))
            use_fp16 = next(self.model.parameters()).is_cuda
            result = self.model.transcribe(
                wav_filename,
                fp16=use_fp16,
                language="en",
                task="transcribe",
                initial_prompt=TECHNICAL_PROMPT
            )
            new_text = result.get("text", "").strip()
            self.transcriptions.append(new_text)
        except RuntimeError as e:
            if "Expected key.size(1) == value.size(1)" in str(e):
                msg = "[Transcription Error: shape mismatch, skipping this chunk]"
                logging.error(msg, exc_info=True)
                self.transcriptions.append(msg)
            else:
                logging.error("Transcription error", exc_info=True)
                self.transcriptions.append(f"[Transcription Error: {e}]")
        except Exception as e:
            logging.error("Transcription error", exc_info=True)
            self.transcriptions.append(f"[Transcription Error: {e}]")
        finally:
            if wav_filename and os.path.exists(wav_filename):
                os.remove(wav_filename)
        self.partial_frames = []

    def force_process_partial_frames(self):
        try:
            if self.running and self.stream.is_active():
                data = self.stream.read(self.stream.get_read_available(), exception_on_overflow=False)
                if self.long_mode:
                    self.long_frames.append(data)
                else:
                    self.partial_frames.append(data)
        except Exception:
            pass
        if not self.long_mode:
            final_frames = self.overlap_frames + self.partial_frames
            if final_frames:
                self.process_audio_chunk(final_frames)
