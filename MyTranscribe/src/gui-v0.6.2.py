import sys
import time
import gi
import torch
import whisper
from transcriber_v8 import RealTimeTranscriber  # The updated transcriber

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib

def apply_css():
    css = b"""
    .start-button {
        background-color: #00FF00;
        color: black;
        font-weight: bold;
    }
    .stop-button {
        background-color: #FF0000;
        color: black;
        font-weight: bold;
    }
    .long-record-button {
        background-color: #0000FF;
        color: black;
        font-weight: bold;
    }
    """
    style_provider = Gtk.CssProvider()
    style_provider.load_from_data(css)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(),
        style_provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )

class TranscriptionApp:
    def __init__(self):
        self.window = Gtk.Window()
        self.window.set_default_size(650, 200)
        self.window.set_position(Gtk.WindowPosition.CENTER)
        self.window.set_title("Real-Time Transcription")
        # Always on top and slightly transparent
        self.window.set_keep_above(True)
        self.window.set_opacity(0.9)
        
        header_bar = Gtk.HeaderBar()
        header_bar.set_show_close_button(True)
        header_bar.set_title("Real-Time Transcription")
        self.window.set_titlebar(header_bar)
        
        self.transcribing = False
        self.recording_mode = None  # "normal" or "long"
        self.update_timeout_id = None
        
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.model = whisper.load_model("small", device=self.device)
        self.transcriber = RealTimeTranscriber(self.model)
        
        self.init_ui()
        
        self.window.connect("destroy", Gtk.main_quit)
        self.window.connect("key-press-event", self.on_key_press)
        self.window.show_all()
    
    def init_ui(self):
        apply_css()
        
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        vbox.set_border_width(10)
        
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.set_hexpand(True)
        scroll.set_vexpand(True)
        
        self.text_view = Gtk.TextView()
        self.text_view.set_editable(False)
        self.text_view.set_cursor_visible(False)
        self.text_view.set_wrap_mode(Gtk.WrapMode.WORD)
        self.text_buffer = self.text_view.get_buffer()
        
        scroll.add(self.text_view)
        vbox.pack_start(scroll, True, True, 0)
        
        button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        
        self.start_button = Gtk.Button(label="Start")
        self.long_record_button = Gtk.Button(label="Long Record")
        self.stop_button = Gtk.Button(label="Stop")
        
        self.start_button.get_style_context().add_class("start-button")
        self.long_record_button.get_style_context().add_class("long-record-button")
        self.stop_button.get_style_context().add_class("stop-button")
        
        self.start_button.connect("clicked", self.start_transcription)
        self.long_record_button.connect("clicked", self.start_long_recording)
        self.stop_button.connect("clicked", self.stop_transcription)
        
        # Pack Start and Stop buttons on the left
        button_box.pack_start(self.start_button, True, True, 0)
        button_box.pack_start(self.stop_button, True, True, 0)
        # Pack the Long Record button to the right
        button_box.pack_end(self.long_record_button, True, True, 0)
        
        vbox.pack_start(button_box, False, False, 0)
        self.window.add(vbox)
        self.update_button_states()
    
    def on_key_press(self, widget, event):
        if event.keyval == Gdk.KEY_space:
            # Only toggle via space bar if in normal mode.
            if self.transcribing and self.recording_mode == "normal":
                self.stop_transcription()
            elif not self.transcribing:
                self.start_transcription()
    
    def start_transcription(self, widget=None):
        if self.transcribing:
            return
        self.recording_mode = "normal"
        self.transcribing = True
        self.text_buffer.set_text("")
        self.transcriber.transcriptions = []
        self.update_button_states()
        
        self.transcriber.start_recording(mode="normal")
        self.update_timeout_id = GLib.timeout_add(100, self.update_transcription_callback)
    
    def start_long_recording(self, widget=None):
        if self.transcribing:
            return
        self.recording_mode = "long"
        self.transcribing = True
        self.text_buffer.set_text("")
        self.transcriber.transcriptions = []
        self.update_button_states()
        
        self.transcriber.start_recording(mode="long")
        self.update_timeout_id = GLib.timeout_add(100, self.update_transcription_callback)
    
    def stop_transcription(self, widget=None):
        if not self.transcribing:
            return
        self.transcribing = False
        self.recording_mode = None
        if self.update_timeout_id:
            GLib.source_remove(self.update_timeout_id)
            self.update_timeout_id = None
        
        self.transcriber.force_process_partial_frames()
        self.transcriber.stop_recording()
        self.update_button_states()
        
        final_text = "\n".join(self.transcriber.transcriptions)
        GLib.idle_add(self.text_buffer.set_text, final_text)
        self.copy_to_clipboard(final_text)
    
    def update_transcription_callback(self):
        if self.recording_mode == "long":
            # During long recording, display a placeholder message.
            self.text_buffer.set_text("Recording in long mode...")
        else:
            current_text = "\n".join(self.transcriber.transcriptions)
            self.text_buffer.set_text(current_text)
        return self.transcribing
    
    def copy_to_clipboard(self, text):
        clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        clipboard.set_text(text, -1)
        clipboard.store()
        print(f"[DEBUG] Copied to clipboard: {text[:60]}{'...' if len(text)>60 else ''}")
    
    def update_button_states(self):
        self.start_button.set_sensitive(not self.transcribing)
        self.long_record_button.set_sensitive(not self.transcribing)
        self.stop_button.set_sensitive(self.transcribing)

def main():
    app = TranscriptionApp()
    Gtk.main()

if __name__ == "__main__":
    main()
